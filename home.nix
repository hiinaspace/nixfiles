{ config, pkgs, ... }:

let
  # The retry support landed immediately after the latest 1.4.0 release, so
  # pin upstream master until nixpkgs updates lighthouse-steamvr.
  lighthouse-steamvr = pkgs.lighthouse-steamvr.overrideAttrs (old: {
    version = "1.4.0-unstable-2026-07-14";
    src = pkgs.fetchFromGitHub {
      owner = "ShayBox";
      repo = "Lighthouse";
      rev = "d069399af2d493b0c540095a495c68e74e75adfe";
      hash = "sha256-u6xO0l+p7NBGSdB6JTlWDdFapl17TxZ9UdQ2r2O7dIQ=";
    };
    # The retry patch does not change Cargo.lock.
    cargoHash = old.cargoHash;
  });

  vr-lighthouses = pkgs.writeShellApplication {
    name = "vr-lighthouses";
    runtimeInputs = [ lighthouse-steamvr ];
    text = ''
      if [ "$#" -ne 1 ] || [[ "$1" != "on" && "$1" != "off" ]]; then
        echo "usage: vr-lighthouses on|off" >&2
        exit 2
      fi

      exec lighthouse -vv \
        --state "$1" \
        --bsid "hci0/dev_DC_01_7A_6B_04_AD" \
        --bsid "hci0/dev_F6_4A_4B_5B_EE_CB" \
        --retries 5 \
        --retry-delay 2
    '';
  };

  start-vr = pkgs.writeShellApplication {
    name = "start-vr";
    runtimeInputs = with pkgs; [ coreutils gnugrep libnotify systemd ];
    text = ''
      controller_count() {
        local invocation
        invocation=$(systemctl --user show monado.service --property=InvocationID --value)
        if [ -z "$invocation" ]; then
          echo 0
          return
        fi
        journalctl --user "_SYSTEMD_INVOCATION_ID=$invocation" --output=cat \
          | grep -c 'Found lighthouse controller' || true
      }

      wait_for_controllers() {
        local count=0
        for _ in $(seq 1 15); do
          count=$(controller_count)
          if [ "$count" -ge 2 ]; then
            echo "Monado detected both Index controllers."
            return 0
          fi
          sleep 1
        done
        return 1
      }

      prompt_for_controllers() {
        notify-send --app-name=start-vr \
          "VR startup" "Turn on both Index controllers, then continue in the terminal." || true
        if [ -t 0 ]; then
          read -r -p "Turn on both Index controllers, then press Enter to start Monado... "
        else
          echo "Turn on both Index controllers; starting Monado in 10 seconds..."
          sleep 10
        fi
      }

      if [ "$#" -ne 0 ]; then
        echo "usage: start-vr" >&2
        exit 2
      fi

      cleanup_incomplete_start() {
        status=$?
        if [ "$status" -ne 0 ] && ! systemctl --user is-active --quiet vr-session.target; then
          systemctl --user stop vr-lighthouses.service || true
        fi
        exit "$status"
      }
      trap cleanup_incomplete_start EXIT

      systemctl --user start vr-lighthouses.service

      if ! systemctl --user is-active --quiet vr-session.target; then
        # Clear a socket-activated instance before the user powers on the
        # controllers. With standby-on-exit enabled, this may turn off any
        # controller the old instance already knew about.
        systemctl --user stop wayvr-debug.service || true
        systemctl --user stop monado.service monado.socket || true
        prompt_for_controllers
        systemctl --user start vr-session.target
      fi

      if wait_for_controllers; then
        exit 0
      fi

      count=$(controller_count)
      echo "Monado detected only $count of 2 Index controllers; restarting the VR clients."
      systemctl --user stop wayvr-debug.service || true
      systemctl --user stop monado.service || true
      prompt_for_controllers
      systemctl --user start monado.socket monado.service wayvr-debug.service

      if ! wait_for_controllers; then
        echo "Monado still did not detect both controllers; check its journal." >&2
        systemctl --user stop vr-session.target || true
        exit 1
      fi
    '';
  };

  stop-vr = pkgs.writeShellApplication {
    name = "stop-vr";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [ "$#" -ne 0 ]; then
        echo "usage: stop-vr" >&2
        exit 2
      fi

      # Stop clients before the runtime. Monado's SteamVR lighthouse driver
      # then puts the known controllers into standby, and finally the BLE
      # helper powers down both base stations.
      systemctl --user stop wayvr-debug.service || true
      systemctl --user stop monado.service monado.socket || true
      systemctl --user stop vr-lighthouses.service || true
      systemctl --user stop vr-session.target || true
    '';
  };

  stop-wayvr = pkgs.writeShellApplication {
    name = "stop-wayvr";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [ -z "''${MAINPID:-}" ] || ! kill -0 "$MAINPID" 2>/dev/null; then
        exit 0
      fi

      kill -TERM "$MAINPID"
      for _ in $(seq 1 50); do
        if ! kill -0 "$MAINPID" 2>/dev/null; then
          exit 0
        fi
        sleep 0.1
      done

      echo "WayVR did not finish teardown after 5 seconds; using SIGKILL" >&2
      kill -KILL "$MAINPID" 2>/dev/null || true
    '';
  };
in {
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "s";
  home.homeDirectory = "/home/s";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment. (allowUnfree comes from the system pkgs via useGlobalPkgs.)
  home.packages = [
    lighthouse-steamvr
    vr-lighthouses
    start-vr
    stop-vr
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    pkgs.fuzzel
    pkgs.unzip
    pkgs.pre-commit
    pkgs.obsidian
    pkgs.btop
    pkgs.jq
    pkgs.godot
    pkgs.mpv
    pkgs.krita
    pkgs.blender
    # VRChat world/avatar dev on Linux (multibox project). unityhub installs the
    # Editor into ~/Unity, which persists: /home is the @home subvolume, not the
    # ephemeral @ root — so keep the Editor install + licenses under $HOME.
    # VRChat's Unity version is 2022.3.22f1 (unityhub://2022.3.22f1/887be4894c44).
    # alcom = FOSS VRChat Creator Companion (VCC) replacement for VPM packages.
    # NVIDIA: launch the Editor with `-force-gfx-direct -force-vulkan`.
    # See https://wiki.vronlinux.org/docs/vrchat/unity/
    pkgs.unityhub
    pkgs.alcom
    # niri runs X11 apps through rootless xwayland-satellite, which won't let a
    # client position its own top-level windows — so Unity's tear-off/re-dock and
    # dock-dragging silently fail. Fix per niri docs: run Unity inside a nested
    # *stacking* compositor. `unity-nested [unityhub|ALCOM]` (default unityhub)
    # opens a labwc window and launches the editor front-end inside it, so the
    # Editor it spawns inherits labwc's display and can dock normally.
    # https://github.com/niri-wm/niri/wiki/Xwayland
    pkgs.labwc
    (pkgs.writeShellScriptBin "unity-nested" ''
      # Fully quit any Unity Hub / ALCOM already on niri first — they're
      # single-instance, so a stray copy would swallow the launch and the Editor
      # would open on niri (undockable) instead of inside labwc.
      exec ${pkgs.labwc}/bin/labwc -s "''${*:-unityhub}"
    '')
    pkgs.gh
    pkgs.obs-studio
    pkgs.ffmpeg-full
    pkgs.opencode
    pkgs.mumble
    pkgs.swappy
    pkgs.grim
    pkgs.slurp
    # Terminal session persistence (attach/detach). Not in nixpkgs; packaged
    # locally from the upstream static release — see ./zmx.nix.
    (pkgs.callPackage ./zmx.nix { })
    (pkgs.writeShellScriptBin "llama-unload" ''
      set -euo pipefail
      loaded=$(${pkgs.curl}/bin/curl -s http://127.0.0.1:11434/v1/models \
        | ${pkgs.jq}/bin/jq -r '.data[] | select(.status.value == "loaded") | .id')
      if [ -z "$loaded" ]; then
        echo "no model currently loaded"
        exit 0
      fi
      for m in $loaded; do
        echo "unloading $m"
        ${pkgs.curl}/bin/curl -s -X POST http://127.0.0.1:11434/models/unload \
          -H "Content-Type: application/json" -d "{\"model\":\"$m\"}"
        echo
      done
    '')
    (pkgs.writeShellScriptBin "llama-status" ''
      set -euo pipefail
      loaded=$(${pkgs.curl}/bin/curl -s http://127.0.0.1:11434/v1/models \
        | ${pkgs.jq}/bin/jq -r '.data[] | select(.status.value == "loaded") | .id')
      if [ -z "$loaded" ]; then
        echo "no model loaded"
      else
        echo "loaded models:"
        echo "$loaded"
      fi
    '')
  ];

  systemd.user.targets.vr-session = {
    Unit = {
      Description = "Local VR session";
      Wants = [
        "vr-lighthouses.service"
        "monado.socket"
        "monado.service"
        "wayvr-debug.service"
      ];
      After = [
        "vr-lighthouses.service"
        "monado.socket"
        "monado.service"
        "wayvr-debug.service"
      ];
    };
  };

  systemd.user.services.vr-lighthouses = {
    Unit = {
      Description = "Power the VR base stations";
      Before = [ "monado.service" ];
      PartOf = [ "vr-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${vr-lighthouses}/bin/vr-lighthouses on";
      ExecStop = "${vr-lighthouses}/bin/vr-lighthouses off";
      TimeoutStartSec = 90;
      TimeoutStopSec = 90;
    };
  };

  # The Monado units come from the NixOS module, while WayVR's debug unit is
  # linked from its checkout. Drop-ins let the session target stop all three
  # without replacing either source unit.
  xdg.configFile."systemd/user/monado.service.d/vr-session.conf".text = ''
    [Unit]
    PartOf=vr-session.target
  '';
  xdg.configFile."systemd/user/monado.socket.d/vr-session.conf".text = ''
    [Unit]
    PartOf=vr-session.target
  '';
  xdg.configFile."systemd/user/wayvr-debug.service.d/vr-session.conf".text = ''
    [Unit]
    PartOf=vr-session.target

    [Service]
    ExecStop=${stop-wayvr}/bin/stop-wayvr
    SuccessExitStatus=SIGKILL
    TimeoutStopSec=10s
  '';

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Relocate VRChat's camera photos out of the disposable Proton prefix into
  # ~/Pictures/VRChat so they survive prefix/Steam wipes (and are backed up without
  # dragging the prefix cache along). https://wiki.vronlinux.org/docs/vrchat/pictures/
  # One-time migration of any existing photos is done outside HM; this just keeps the
  # in-prefix path pointing at the real directory.
  home.file.".local/share/Steam/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/Pictures/VRChat".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Pictures/VRChat";

  # Keep the customized xrizer/SteamVR bindings for Valve Index controllers out
  # of Steam's disposable app payload. xrizer reads this parent SteamVR binding
  # file for VRChat, not the adjacent SteamVR/xrizer/knuckles.json.
  home.file.".local/share/Steam/steamapps/common/VRChat/VRChat_Data/StreamingAssets/SteamVR/bindings_knuckles.json" = {
    source = ./steamvr/vrchat/bindings_knuckles.json;
    force = true;
  };

  # xrizer checks XRIZER_CUSTOM_BINDINGS_DIR/<controller>.json before falling
  # back to the binding_url from VRChat's action manifest.
  xdg.configFile."xrizer/bindings/knuckles.json".source =
    ./steamvr/vrchat/bindings_knuckles.json;

  # https://lvra.gitlab.io/docs/distros/nixos/#recommendations
  # Tell the OpenVR loader (inside Proton/Wine) to use xrizer as the runtime.
  # xrizer bridges OpenVR → OpenXR → Monado.
  # NOTE: /nix must be visible in pressure-vessel; see PRESSURE_VESSEL_FILESYSTEMS_RO
  # in configuration.nix.
  xdg.configFile."openvr/openvrpaths.vrpath".text = ''
    {
      "config" :
      [
        "/home/s/.local/share/Steam/config"
      ],
      "external_drivers" : null,
      "jsonid" : "vrpathreg",
      "log" :
      [
        "/home/s/.local/share/Steam/logs"
      ],
      "runtime" :
      [
        "${pkgs.xrizer}/lib/xrizer"
      ],
      "version" : 1
    }
  '';

  xdg.configFile."opencode/opencode.json".text = ''
    {
      "$schema": "https://opencode.ai/config.json",
      "model": "llama-cpp/qwen3.6-35b-a3b",
      "provider": {
        "llama-cpp": {
          "npm": "@ai-sdk/openai-compatible",
          "name": "llama.cpp (local)",
          "options": {
            "baseURL": "http://127.0.0.1:11434/v1"
          },
          "models": {
            "qwen3.6-35b-a3b": {
              "name": "Qwen3.6 35B-A3B (llama.cpp)",
              "limit": {
                "context": 98304,
                "output": 16384
              }
            },
            "gemma-4-e4b": {
              "name": "Gemma4 E4B (llama.cpp)",
              "limit": {
                "context": 65536,
                "output": 8192
              }
            }
          }
        }
      }
    }
  '';


  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/s/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };
  };

  programs.tmux.enable = true;
  # fix colors
  programs.tmux.terminal = "xterm-256color";

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
    '';
    shellAliases = {
      vim = "nvim";
      "e" = "nvim";
    };
  };
  home.shell.enableFishIntegration = true;

  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    # Hand-tuned TOML parsed into native settings (HM round-trips it back to TOML),
    # so there's a single source of truth and no separate verbatim file to manage.
    settings = builtins.fromTOML (builtins.readFile ./dotfiles/starship.toml);
  };

  programs.eza = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fd.enable = true;
  programs.ripgrep.enable = true;

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
  };

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    sway.enable = true;
  };

  # Hand-authored configs, version-controlled in ./dotfiles and deployed verbatim as
  # store symlinks. Edit the repo copy and `home-manager switch` to apply.
  xdg.configFile."sway/config".source = ./dotfiles/sway/config;
  # niri config (KDL). Added alongside sway; niri itself is enabled via
  # programs.niri in configuration.nix.
  # TEMPORARY (hot iteration): out-of-store symlink to the live repo file so
  # edits are picked up by niri's autoreload without a rebuild. Restore to the
  # plain `source = ./dotfiles/niri/config.kdl;` (store copy) once the config
  # settles.
  xdg.configFile."niri/config.kdl".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos-config/dotfiles/niri/config.kdl";
  xdg.configFile."mpv/scripts/webm.lua".source = ./dotfiles/mpv/scripts/webm.lua;
  xdg.configFile."waybar/config.jsonc".source = ./dotfiles/waybar/config.jsonc;
  xdg.configFile."waybar/style.css".source = ./dotfiles/waybar/style.css;

  programs.waybar.enable = true;

  services.syncthing = {
    enable = true;
  };

  # turn darkmode on/off by time of day
  services.darkman = {
    enable = true;
    lightModeScripts.gtk-theme = ''
      ${pkgs.dconf}/bin/dconf write \
          /org/gnome/desktop/interface/color-scheme "'prefer-light'"
    '';
    darkModeScripts.gtk-theme = ''
      ${pkgs.dconf}/bin/dconf write \
          /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
    '';
    settings = {
      lat = 40.16;
      lng = -105.1;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "hiina";
      user.email = "hiina@hiina.space";
      init.defaultBranch = "main";
      extraConfig = {
      };
    };
  };
}
