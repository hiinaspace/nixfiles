{ pkgs, ... }:

let
  synthvPackages = import ./synthv-packages.nix { inherit pkgs; };
  inherit (synthvPackages) yabridge yabridgectl;
  synthvWine = synthvPackages.wine;

  # Native third-party plugins are commonly built for FHS distributions and
  # expect these libraries to be globally discoverable. The Flatpak runtime
  # used to provide them implicitly.
  bitwigStudio = pkgs.symlinkJoin {
    name = "bitwig-studio-with-plugin-libraries";
    paths = [ pkgs.bitwig-studio ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/bitwig-studio" \
        --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [
          pkgs.freetype
          pkgs.fontconfig
          pkgs.stdenv.cc.cc.lib
        ]}
    '';
  };

  synthv2 = pkgs.writeShellApplication {
    name = "synthv2";
    runtimeInputs = [
      pkgs.coreutils
      synthvWine
      pkgs.winetricks
      yabridgectl
    ];
    text = ''
      prefix="''${SYNTHV2_WINEPREFIX:-$HOME/.local/share/wineprefixes/synthv2}"
      vst3_dir="$prefix/drive_c/Program Files/Common Files/VST3"
      export WINEPREFIX="$prefix"

      usage() {
        cat <<'EOF'
      usage: synthv2 COMMAND [ARG]

      Commands:
        init                    Initialize the dedicated Wine prefix
        install INSTALLER      Run the Synthesizer V Studio 2 Core installer
        webview INSTALLER      Run the Microsoft Edge WebView2 installer
        sync                    Register the prefix's VST3 directory with yabridge
        status                  Show the prefix and yabridge status
        login URI               Forward a Dreamtonics login callback to Core
        winecfg                 Open Wine configuration for this prefix
        kill                    Stop Wine processes belonging to this prefix
        prefix                  Print the Wine prefix path

      Override the prefix with SYNTHV2_WINEPREFIX if needed.
      EOF
      }

      init_prefix() {
        mkdir -p "$prefix"
        wineboot --init
        # Prefixes created by Wine 9 may not contain cryptbase.dll. Wine 11's
        # advapi32 forwards SystemFunction036 to it, so force Wine's builtin
        # implementation instead of letting service startup fail.
        wine reg add 'HKCU\Software\Wine\DllOverrides' \
          /v cryptbase /t REG_SZ /d builtin /f >/dev/null
        install -m 0644 ${synthvWine}/lib/wine/x86_64-windows/cryptbase.dll \
          "$prefix/drive_c/windows/system32/cryptbase.dll"
        install -m 0644 ${synthvWine}/lib/wine/i386-windows/cryptbase.dll \
          "$prefix/drive_c/windows/syswow64/cryptbase.dll"
      }

      require_installer() {
        if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
          echo "expected the path to an installer file" >&2
          exit 2
        fi
      }

      command="''${1:-}"
      case "$command" in
        init)
          [ "$#" -eq 1 ] || { usage >&2; exit 2; }
          init_prefix
          ;;
        install|webview)
          shift
          require_installer "$@"
          installer=$(realpath "$1")
          init_prefix
          wine "$installer"
          ;;
        sync)
          [ "$#" -eq 1 ] || { usage >&2; exit 2; }
          if [ ! -d "$vst3_dir" ]; then
            echo "VST3 directory does not exist yet: $vst3_dir" >&2
            echo "Install Synthesizer V Studio 2 Core first." >&2
            exit 1
          fi
          yabridgectl add "$vst3_dir"
          yabridgectl sync
          ;;
        status)
          [ "$#" -eq 1 ] || { usage >&2; exit 2; }
          echo "Wine prefix: $prefix"
          echo "Windows VST3 directory: $vst3_dir"
          yabridgectl status
          ;;
        login)
          shift
          if [ "$#" -ne 1 ]; then
            echo "expected one Dreamtonics callback URI" >&2
            exit 2
          fi
          case "$1" in
            dreamtonics-svstudio2://*|dreamtonics-svstudio2-core://*) ;;
            *)
              echo "refusing unexpected callback URI: $1" >&2
              exit 2
              ;;
          esac
          login_helper="$prefix/drive_c/Program Files/Synthesizer V Studio 2 Core/loginhelper.exe"
          if [ ! -f "$login_helper" ]; then
            echo "SynthV Core login helper is not installed: $login_helper" >&2
            exit 1
          fi
          wine "$login_helper" "$1"
          ;;
        winecfg)
          [ "$#" -eq 1 ] || { usage >&2; exit 2; }
          init_prefix
          winecfg
          ;;
        kill)
          [ "$#" -eq 1 ] || { usage >&2; exit 2; }
          wineserver --kill
          ;;
        prefix)
          [ "$#" -eq 1 ] || { usage >&2; exit 2; }
          printf '%s\n' "$prefix"
          ;;
        help|-h|--help)
          usage
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '';
  };

  # Niri intentionally does not let X11 clients position their own top-level
  # windows. Run Bitwig and Wine's plugin editor under a nested stacking
  # compositor when a plugin GUI needs conventional X11 window behavior.
  bitwigNested = pkgs.writeShellApplication {
    name = "bitwig-nested";
    runtimeInputs = [
      bitwigStudio
      pkgs.labwc
      pkgs.procps
    ];
    text = ''
      if pgrep -u "$UID" -f '/BitwigStudio([[:space:]]|$)' >/dev/null; then
        echo "Bitwig is already running; quit it before using bitwig-nested." >&2
        exit 1
      fi

      exec labwc -s bitwig-studio
    '';
  };

  bitwigNestedDebug = pkgs.writeShellApplication {
    name = "bitwig-nested-debug";
    runtimeInputs = [ bitwigNested ];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/yabridge"
      mkdir -p "$state_dir"
      export YABRIDGE_DEBUG_FILE="$state_dir/synthv.log"
      export YABRIDGE_DEBUG_LEVEL="1+editor"
      exec bitwig-nested
    '';
  };
in
{
  # Native Bitwig is required for yabridge; yabridge cannot run inside the
  # Flatpak sandbox. SynthV Core itself is installed interactively into the
  # persistent per-user prefix managed by the synthv2 helper.
  home.packages = [
    bitwigStudio
    yabridge
    yabridgectl
    synthvWine
    pkgs.winetricks
    synthv2
    bitwigNested
    bitwigNestedDebug
  ];

  home.file.".vst3/yabridge/yabridge.toml".text = ''
    ["Synthesizer V Studio 2 Core.vst3"]
    editor_disable_host_scaling = true
  '';

  xdg.desktopEntries.bitwig-nested = {
    name = "Bitwig Studio (Nested XWayland)";
    comment = "Run Bitwig and Wine plugin editors under a nested stacking compositor";
    exec = "bitwig-nested";
    icon = "com.bitwig.BitwigStudio";
    terminal = false;
    categories = [ "AudioVideo" "Audio" ];
  };

  # Dreamtonics currently registers a Core-specific scheme, while some login
  # pages and older releases use the generic Studio 2 scheme.
  xdg.desktopEntries.synthv-login = {
    name = "Synthesizer V Studio 2 Login Handler";
    exec = "synthv2 login %u";
    terminal = false;
    noDisplay = true;
    mimeType = [
      "x-scheme-handler/dreamtonics-svstudio2"
      "x-scheme-handler/dreamtonics-svstudio2-core"
    ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/dreamtonics-svstudio2" = [ "synthv-login.desktop" ];
      "x-scheme-handler/dreamtonics-svstudio2-core" = [ "synthv-login.desktop" ];
    };
  };
}
