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
        "/home/s/.ollama"
        "/home/s/SwarmUI/Models"
        "/home/s/SwarmUI/dlbackend"
        "/home/s/invokeai/models"
        # regenerable map export output
        "/home/s/mapgen-run"
        # Steam: keep userdata/config (saves), drop re-downloadable game payloads
        "/home/s/.local/share/Steam/steamapps/common"
        "/home/s/.local/share/Steam/steamapps/downloading"
        "/home/s/.local/share/Steam/steamapps/shadercache"
        "/home/s/.local/share/Steam/steamapps/workshop"
        "/home/s/.local/share/Steam/ubuntu12_32"
        "/home/s/.local/share/Steam/ubuntu12_64"
        # browser caches (keep the profile: bookmarks, saved logins, sessions)
        "sh:/home/s/.mozilla/firefox/*/cache2"
        "sh:/home/s/.mozilla/firefox/*/storage/**/cache"
        # build artifacts not tagged as caches
        "sh:**/node_modules"
        "sh:**/__pycache__"
        "sh:**/.venv"
      ];

      # retention (prune runs as part of the daily borgmatic job)
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };
  };
}
