# ============================================================================
# STAGED — NOT imported by flake.nix yet. Wire this in only AFTER the reinstall
# lays out a btrfs root with a roll-back-on-boot @ subvolume and a /persist mount.
#
# Activation at reinstall:
#   1. flake.nix: add `inputs.impermanence.nixosModules.impermanence` and
#      `./impermanence.nix` to the sayu module list (both currently commented there).
#   2. Restore the critical state onto /persist before first real boot, esp.
#      /persist/etc/ssh/ssh_host_* (so host identity + the sops-nix age identity
#      derived from it stay stable) and /persist/var/lib/{nixos,systemd,...}.
#
# ---- Target btrfs layout (built at install time, goes in hardware-configuration.nix) ----
#   LUKS -> btrfs with subvolumes:
#     @          -> /          (rolled back to @blank every boot)
#     @nix       -> /nix       (persistent)
#     @home      -> /home      (persistent; holds sops age key, ssh user key, dotfiles)
#     @persist   -> /persist   (persistent; everything listed below)
#     @log       -> /var/log   (persistent)
#     @snapshots -> /.snapshots
#   plus the existing ESP at /boot.
#   Mount @persist, @nix, @home, @log with `neededForBoot = true` where required so
#   the persistence bind-mounts are available early.
#
# ---- Roll-back-on-boot recipe (initrd; subvol ids are illustrative) ----
#   boot.initrd.systemd.services.rollback = {
#     description = "Rollback btrfs root to a blank snapshot";
#     wantedBy = [ "initrd.target" ];
#     after = [ "systemd-cryptsetup@luksroot.service" ];   # after LUKS open
#     before = [ "sysroot.mount" ];
#     unitConfig.DefaultDependencies = "no";
#     serviceConfig.Type = "oneshot";
#     script = ''
#       mkdir -p /mnt
#       mount -o subvol=/ /dev/mapper/luksroot /mnt
#       btrfs subvolume list -o /mnt/@ | cut -f9 -d' ' |
#         while read sub; do btrfs subvolume delete "/mnt/$sub"; done
#       btrfs subvolume delete /mnt/@
#       btrfs subvolume snapshot /mnt/@blank /mnt/@
#       umount /mnt
#     '';
#   };
#   (Create @blank once at install: snapshot the empty @ right after creating it.)
# ============================================================================
{ lib, ... }:

{
  # Keep host SSH identity (and the sops-nix age identity derived from it) on /persist
  # so it's stable across the per-boot root wipe. Copy the existing keys here at restore.
  services.openssh.hostKeys = [
    { path = "/persist/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
    { path = "/persist/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
  ];

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      # stable uid/gid maps — without this, file ownership drifts after a rebuild
      "/var/lib/nixos"
      # Persistent=true timer last-run state (borgmatic daily timer) + random seed
      "/var/lib/systemd"
      # saved networks + leases (wifi passwords land in system-connections)
      "/var/lib/NetworkManager"
      "/etc/NetworkManager/system-connections"
      # VR headset/controller bluetooth pairings
      "/var/lib/bluetooth"
      # borgmatic bookkeeping
      "/var/lib/borgmatic"

      # Optional service state — regenerable, persist to avoid re-downloads/rebuilds:
      # "/var/lib/ollama"
      # "/var/lib/comfyui"
    ];

    files = [
      # systemd/journald machine identity
      "/etc/machine-id"
    ];
  };

  # /var/log is its own persistent @log subvolume (see header), so it is NOT listed
  # above. If you'd rather bind it from /persist instead of a subvolume, move it into
  # `directories` and drop the @log subvolume. Kept as a subvolume here.
}
