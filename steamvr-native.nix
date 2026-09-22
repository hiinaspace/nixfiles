{ pkgs, ... }:
let
  session = pkgs.writeShellApplication {
    name = "steamvr-native-session";
    runtimeInputs = [ pkgs.python3 pkgs.systemd pkgs.steam-run ];
    text = ''
      exec python3 ${./scripts/steamvr-session.py}
    '';
  };
  start = pkgs.writeShellApplication {
    name = "start-steamvr";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      systemctl --user start steamvr-native.service
      systemctl --user --no-pager status steamvr-native.service
    '';
  };
  stop = pkgs.writeShellApplication {
    name = "stop-steamvr";
    runtimeInputs = [ pkgs.systemd ];
    text = ''systemctl --user stop steamvr-native.service'';
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
in {
  # Standard SteamVR capability, reapplied on rebuild after SteamVR updates.
  system.activationScripts.steamvrCompositorCapability.text = ''
    launcher=/home/s/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher
    if [ -f "$launcher" ] && [ ! -L "$launcher" ]; then
      ${pkgs.libcap}/bin/setcap cap_sys_nice=eip "$launcher"
    fi
  '';
  home-manager.users.s = {
    home.packages = [ start stop run ];
    systemd.user.services.steamvr-native = {
      Unit = {
        Description = "Native SteamVR with temporary OpenVR selection";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${session}/bin/steamvr-native-session";
        TimeoutStopSec = 30;
        KillMode = "mixed";
      };
    };
  };
}
