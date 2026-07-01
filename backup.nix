# Home backup to chirashi's /pool via borgmatic.
# Repo lives at /mnt/pool/borg/sayu (matches the existing /pool/borg/<host> convention).
# Encryption passphrase is the sops `borgpassphrase` secret; it is supplied to borg
# automatically via encryption_passcommand, so it is never typed interactively.
{ config, ... }:

{
  # Decrypted by sops-nix to /run/secrets/borgpassphrase (root, mode 0400).
  sops.secrets.borgpassphrase = { };

  services.borgmatic = {
    enable = true;
    enableConfigCheck = true; # `borgmatic config validate` at build time
    settings = {
      source_directories = [ "/home/s" ];

      repositories = [
        {
          # User, host IP and port come from the `chirashi` alias in
          # /home/s/.ssh/config (not tracked here) so they stay out of this public repo.
          path = "ssh://chirashi/mnt/pool/borg/sayu";
          label = "chirashi";
        }
      ];

      # The borgmatic systemd unit runs as root, so load the user's ssh config for the
      # alias but force absolute key + known_hosts (the config's ~/ paths would resolve
      # under /root otherwise).
      ssh_command = "ssh -F /home/s/.ssh/config -i /home/s/.ssh/id_ed25519 -o UserKnownHostsFile=/home/s/.ssh/known_hosts -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=120";

      encryption_passcommand = "cat ${config.sops.secrets.borgpassphrase.path}";

      compression = "zstd";

      # Auto-skip any dir tagged with CACHEDIR.TAG (cargo target/, etc.).
      exclude_caches = true;

      exclude_patterns = [
        # caches / re-fetchable toolchain state
        "/home/s/.cache"
        "/home/s/.cargo"
        "/home/s/.rustup"
        "/home/s/.npm"
        "/home/s/.nuget"
        "/home/s/.dotnet"
        "/home/s/.local/share/uv"
        "/home/s/.local/share/NuGet"
        # re-downloadable model weights
        "/home/s/SwarmUI/Models"
        "/home/s/SwarmUI/dlbackend"
        "/home/s/invokeai/models"
        # regenerable map export output
        "/home/s/mapgen-run"
        # Steam: keep userdata (saves/screenshots) + compatdata (local game saves);
        # everything else is re-fetched on reinstall. See restic/borg community lists.
        # games + per-game caches
        "/home/s/.local/share/Steam/steamapps/common"
        "/home/s/.local/share/Steam/steamapps/downloading"
        "/home/s/.local/share/Steam/steamapps/shadercache"
        "/home/s/.local/share/Steam/steamapps/workshop"
        "/home/s/.local/share/Steam/steamapps/temp"
        # Steam client runtime (re-downloaded on first launch)
        "/home/s/.local/share/Steam/ubuntu12_32"
        "/home/s/.local/share/Steam/ubuntu12_64"
        "/home/s/.local/share/Steam/steamrt64"
        "/home/s/.local/share/Steam/steamrt32"
        "/home/s/.local/share/Steam/package"
        "/home/s/.local/share/Steam/steamui"
        "/home/s/.local/share/Steam/clientui"
        "/home/s/.local/share/Steam/linux32"
        "/home/s/.local/share/Steam/linux64"
        "/home/s/.local/share/Steam/legacycompat"
        # Steam client caches / logs
        "/home/s/.local/share/Steam/appcache"
        "/home/s/.local/share/Steam/depotcache"
        "/home/s/.local/share/Steam/logs"
        "/home/s/.local/share/Steam/dumps"
        "/home/s/.local/share/Steam/config/htmlcache"
        # regenerable caches *inside* Proton prefixes (keep saves/configs alongside):
        # DXVK shader state, and VRChat's world/texture caches (account-based game,
        # so LocalAvatarData / worldconfig / LocalPlayerModerations are kept).
        "sh:**/pfx/drive_c/users/steamuser/AppData/Local/dxvk"
        "sh:**/LocalLow/VRChat/VRChat/*Cache-WindowsPlayer"
        # browser caches (keep the profile: bookmarks, saved logins, sessions)
        "sh:/home/s/.mozilla/firefox/*/cache2"
        "sh:/home/s/.mozilla/firefox/*/storage/**/cache"
        # build artifacts not tagged as caches
        "sh:**/node_modules"
        "sh:**/__pycache__"
        "sh:**/.venv"
      ];

      relocated_repo_access_is_ok = true;

      # retention (prune runs as part of the daily borgmatic job)
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };
  };
}
