# Optional, independently scheduled Borg 1.x offsite backup.
#
# This intentionally uses services.borgbackup rather than adding another
# borgmatic repository: the LAN backup in backup.nix remains a separate job and
# continues to work if the offsite provider is unavailable.  The module is inert
# until services.borgOffsite.enable is set after the provider endpoint and SOPS
# secrets have been added locally.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.borgOffsite;

  defaultExcludes = [
    # CACHEDIR.TAG directories are excluded separately by --exclude-caches.
    # These paths are known re-fetchable caches, package/toolchain state, or
    # model weights. Keep Downloads, projects, creative work, and application
    # profiles as ordinary default-included home data.
    "/home/s/.cache"
    "/home/s/.cargo"
    "/home/s/.rustup"
    "/home/s/.npm"
    "/home/s/.nuget"
    "/home/s/.dotnet"
    "/home/s/.local/share/uv"
    "/home/s/.local/share/NuGet"
    "/home/s/.ollama"
    "/home/s/SwarmUI/Models"
    "/home/s/SwarmUI/dlbackend"
    "/home/s/invokeai/models"
    "/home/s/mapgen-run"

    # Steam games and client/runtime caches are re-downloadable. Do not exclude
    # steamapps/compatdata or userdata: they can contain saves and settings.
    "/home/s/.local/share/Steam/steamapps/common"
    "/home/s/.local/share/Steam/steamapps/downloading"
    "/home/s/.local/share/Steam/steamapps/shadercache"
    "/home/s/.local/share/Steam/steamapps/workshop"
    "/home/s/.local/share/Steam/steamapps/temp"
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
    "/home/s/.local/share/Steam/appcache"
    "/home/s/.local/share/Steam/depotcache"
    "/home/s/.local/share/Steam/logs"
    "/home/s/.local/share/Steam/dumps"
    "/home/s/.local/share/Steam/config/htmlcache"

    # Regenerable caches inside otherwise retained Proton prefixes and profiles.
    "sh:**/pfx/drive_c/users/steamuser/AppData/Local/dxvk"
    "sh:**/LocalLow/VRChat/VRChat/*Cache-WindowsPlayer"
    "sh:**/node_modules"
    "sh:**/__pycache__"
    "sh:**/.venv"
    "sh:**/.stversions"
    # Syncthing's index is a LevelDB directory (index-v*/...), not a single DB
    # file. The synchronized files themselves remain included.
    "sh:/home/s/.local/state/syncthing/index-v*"
    "/home/s/.config/Element/EventStore"
    "/home/s/.config/element-desktop/EventStore"
    "/home/s/.config/Element/Cache"
    "/home/s/.config/Element/Code Cache"
    "/home/s/.config/Element/GPUCache"
    "/home/s/.config/element-desktop/Cache"
    "/home/s/.config/element-desktop/Code Cache"
    "/home/s/.config/element-desktop/GPUCache"
    "sh:/home/s/.thunderbird/*/global-messages-db.sqlite*"

    # Preserve browser profiles but omit their content and code caches.
    "sh:**/.mozilla/firefox/*/cache2"
    "sh:**/.mozilla/firefox/*/storage/**/cache"
    "sh:/home/s/.config/google-chrome/*/Cache"
    "sh:/home/s/.config/google-chrome/*/Code Cache"
    "sh:/home/s/.config/google-chrome/*/GPUCache"
    "/home/s/.config/google-chrome/component_crx_cache"
    "/home/s/.config/google-chrome/optimization_guide_model_store"
    "sh:/home/s/.config/chromium/*/Cache"
    "sh:/home/s/.config/chromium/*/Code Cache"
    "sh:/home/s/.config/chromium/*/GPUCache"
    "/home/s/.config/chromium/component_crx_cache"
    "/home/s/.config/chromium/optimization_guide_model_store"
  ];
in
{
  options.services.borgOffsite = {
    enable = lib.mkEnableOption "the separate Borg offsite backup job";

    label = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = "offsite";
      description = ''
        Stable local identifier for this repository. It is used in the dedicated
        borgbackup systemd service/timer and archive name prefix.
      '';
    };

    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "user@ch-s000.rsync.net:borg/sayu";
      description = "Borg-over-SSH repository URL supplied by the offsite provider.";
    };

    passphraseSecret = lib.mkOption {
      type = lib.types.str;
      default = "borg-offsite-passphrase";
      description = ''
        Name of the SOPS secret containing this repository's Borg passphrase.
        It is materialized as a root-only file and read via BORG_PASSCOMMAND.
      '';
    };

    sshKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "borg-offsite-ssh-key";
      description = ''
        Name of the SOPS secret containing the dedicated offsite SSH private
        key. The unattended key is materialized only as a root-readable runtime
        file.
      '';
    };

    knownHostsFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ssh/ssh_known_hosts";
      description = ''
        Known-hosts file containing the provider host key verified during
        provisioning. Strict host-key checking is always enabled.
      '';
    };

    healthchecksUrlSecret = lib.mkOption {
      type = lib.types.str;
      default = "borg-offsite-healthchecks-url";
      description = ''
        Name of the SOPS secret containing this job's private Healthchecks ping
        URL. The URL is read at runtime and never embedded in the Nix store.
      '';
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/home/s" ];
      description = "Paths backed up by the offsite job.";
    };

    startAt = lib.mkOption {
      type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
      default = "02:30";
      description = "Calendar schedule for the dedicated offsite Borg timer.";
    };

    additionalExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional Borg exclude patterns beyond the conservative defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repository != null;
        message = "services.borgOffsite.repository must be set when the offsite job is enabled.";
      }
    ];

    # sops-nix defaults to root ownership; make the boundary explicit because
    # Borg invokes this file only from the root-owned systemd job.
    sops.secrets.${cfg.passphraseSecret} = {
      owner = "root";
      group = "root";
      mode = "0400";
    };
    sops.secrets.${cfg.sshKeySecret} = {
      owner = "root";
      group = "root";
      mode = "0400";
    };
    sops.secrets.${cfg.healthchecksUrlSecret} = {
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # The pinned nixpkgs Borg package is Borg 1.4.x. repokey-blake2 stores the
    # repository key with the remote repository and leaves the passphrase out
    # of the Nix store, which is suitable for the recovery-bundle design.
    services.borgbackup.package = lib.mkDefault pkgs.borgbackup;
    services.borgbackup.jobs.${cfg.label} = {
      inherit (cfg) paths startAt;
      repo = cfg.repository;
      archiveBaseName = "${config.networking.hostName}-${cfg.label}";
      # Provisioning initializes and checks the repository explicitly. Do not
      # mistake a transient SSH/auth failure during a scheduled run for a
      # missing repository and attempt `borg init`.
      doInit = false;
      persistentTimer = true;
      inhibitsSleep = true;
      compression = "zstd";
      failOnWarnings = false;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.sops.secrets.${cfg.passphraseSecret}.path}";
      };
      environment.BORG_RSH = lib.concatStringsSep " " [
        "ssh"
        "-i ${config.sops.secrets.${cfg.sshKeySecret}.path}"
        "-o IdentitiesOnly=yes"
        "-o PubkeyAuthentication=yes"
        "-o PreferredAuthentications=publickey"
        "-o BatchMode=yes"
        "-o StrictHostKeyChecking=yes"
        "-o UserKnownHostsFile=${cfg.knownHostsFile}"
        "-o ServerAliveInterval=120"
      ];
      # rsync.net exposes versioned Borg server commands through its restricted
      # shell. Keep the server on the same 1.4 series as the local client.
      extraArgs = [ "--remote-path=borg14" ];
      preHook = ''
        hc_url="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.${cfg.healthchecksUrlSecret}.path})"
        ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 20 \
          --retry 2 --retry-delay 2 "$hc_url/start" >/dev/null || true
      '';
      postHook = ''
        hc_url="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.${cfg.healthchecksUrlSecret}.path})"
        if [ "$exitStatus" -eq 0 ]; then
          hc_suffix=""
        else
          hc_suffix="/fail"
        fi
        ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 20 \
          --retry 2 --retry-delay 2 "$hc_url$hc_suffix" >/dev/null || true
      '';
      exclude = lib.unique (defaultExcludes ++ cfg.additionalExcludes);
      extraCreateArgs = [ "--exclude-caches" ];
      prune = {
        keep = {
          daily = 7;
          weekly = 4;
          monthly = 6;
          yearly = 1;
        };
      };
    };
  };
}
