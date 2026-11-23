{ pkgs, ... }:
let
  session = pkgs.writeShellApplication {
    name = "steamvr-native-session";
    runtimeInputs = [ pkgs.python3 pkgs.systemd pkgs.steam-run ];
    text = ''
      exec python3 ${./scripts/steamvr-session.py}
    '';
  };
  # The user manager keeps whatever display env was last imported, which a
  # nested or headless compositor can leave pointing at a dead socket. Re-import
  # the caller's env when it names a live Wayland socket.
  importDisplay = ''
    if [ -n "''${WAYLAND_DISPLAY:-}" ] && [ -S "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WAYLAND_DISPLAY" ]; then
      systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP
    fi
  '';
  mkStart = name: unit: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      ${importDisplay}
      systemctl --user start ${unit}.service
      systemctl --user --no-pager status ${unit}.service
    '';
  };
  # Lighthouse headsets (vr-lighthouses powers the base stations).
  start = mkStart "start-steamvr" "steamvr-native";
  # Steam Frame streaming: forcedDriver vrlink, base stations left off.
  startFrame = mkStart "start-steamvr-frame" "steamvr-native-frame";
  stop = pkgs.writeShellApplication {
    name = "stop-steamvr";
    runtimeInputs = [ pkgs.systemd ];
    text = ''systemctl --user stop steamvr-native.service steamvr-native-frame.service'';
  };
  run = pkgs.writeShellApplication {
    name = "steamvr-run";
    runtimeInputs = [ pkgs.steam-run ];
    text = ''
      export VR_OVERRIDE="$HOME/.local/share/Steam/steamapps/common/SteamVR"
      export XR_RUNTIME_JSON="$VR_OVERRIDE/steamxr_linux64.json"
      exec steam-run "$@"
    '';
  };
  vrchatFrame = pkgs.writeShellApplication {
    name = "vrchat-frame";
    runtimeInputs = [ pkgs.python3 pkgs.steam-run ];
    text = ''exec python3 ${./scripts/steamvr-frame-game.py} --game vrchat "$@"'';
  };
  forefrontFrame = pkgs.writeShellApplication {
    name = "forefront-frame";
    runtimeInputs = [ pkgs.python3 pkgs.steam-run ];
    text = ''exec python3 ${./scripts/steamvr-frame-game.py} --game forefront "$@"'';
  };
in {
  # Standard SteamVR capability, reapplied on rebuild after SteamVR updates.
  system.activationScripts.steamvrCompositorCapability.text = ''
    launcher=/home/s/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher
    if [ -f "$launcher" ] && [ ! -L "$launcher" ]; then
      ${pkgs.libcap}/bin/setcap cap_sys_nice=eip "$launcher"
    fi
  '';
  home-manager.users.s = {
    home.packages = [ start startFrame stop run vrchatFrame forefrontFrame ];
    systemd.user.services = let
      unit = description: extra: {
        Unit = {
          Description = description;
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${session}/bin/steamvr-native-session";
          TimeoutStopSec = 30;
          KillMode = "mixed";
        } // extra;
      };
    in {
      steamvr-native = unit "Native SteamVR (lighthouse) with temporary OpenVR selection" { };
      steamvr-native-frame = unit "Native SteamVR (Steam Frame, vrlink) with temporary OpenVR selection" {
        Environment = [ "STEAMVR_FRAME_SESSION=1" ];
      };
    };
  };
}
