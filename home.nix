{ config, pkgs, ... }:

{
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
    pkgs.pre-commit
    pkgs.obsidian
    pkgs.btop
    pkgs.jq
    pkgs.godot
    pkgs.mpv
    pkgs.krita
    pkgs.blender
    pkgs.gh
    pkgs.obs-studio
    pkgs.ffmpeg-full
    pkgs.opencode
    pkgs.mumble
    pkgs.swappy
    pkgs.grim
    pkgs.slurp
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
  xdg.configFile."niri/config.kdl".source = ./dotfiles/niri/config.kdl;
  xdg.configFile."mpv/scripts/webm.lua".source = ./dotfiles/mpv/scripts/webm.lua;
  xdg.configFile."waybar/config.jsonc".source = ./dotfiles/waybar/config.jsonc;
  xdg.configFile."waybar/style.css".source = ./dotfiles/waybar/style.css;

  programs.waybar.enable = true;

  services.syncthing = {
    enable = true;
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
