{ pkgs, ... }:
let
  wivrn = pkgs.wivrn-frame;
  manifest = "${wivrn}/share/openxr/1/openxr_wivrn.json";
  xrizer = "${pkgs.xrizer}/lib/xrizer";
  command = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ pkgs.systemd pkgs.python3 pkgs.steam-run pkgs.procps ];
  };
  start = command "start-wivrn-frame" ''
    if pgrep -u "$UID" -x vrserver >/dev/null || pgrep -u "$UID" -x monado-service >/dev/null; then
      echo "Stop SteamVR/Monado before starting WiVRn." >&2
      exit 1
    fi
    systemctl --user start wivrn.service
    systemctl --user --no-pager status wivrn.service
  '';
  stop = command "stop-wivrn-frame" ''
    systemctl --user stop wayvr-wivrn.service
    systemctl --user stop wivrn.service
  '';
  wayvr = command "wayvr-wivrn" ''systemctl --user start wayvr-wivrn.service'';
  game = name: title: command name ''
    exec python3 ${./scripts/steamvr-frame-game.py} --game ${title} --backend wivrn \
      --xr-runtime ${manifest} --openvr-runtime ${xrizer} "$@"
  '';
in {
  services.wivrn = {
    enable = true;
    package = wivrn;
    autoStart = false;
    highPriority = true;
    extraServerFlags = [ "--no-manage-active-runtime" ];
    config.enable = true;
    config.json = {
      encoder = { encoder = "nvenc"; codec = "h264"; };
      bit-depth = 8;
      openvr-compat-path = null;
    };
    monadoEnvironment = {
      XR_RUNTIME_JSON = manifest;
      XRT_COMPOSITOR_FORCE_GPU_INDEX = "0";
      XRT_COMPOSITOR_FORCE_CLIENT_GPU_INDEX = "0";
      VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
    };
  };
  networking.firewall.interfaces.enp7s0 = { allowedTCPPorts = [ 9757 ]; allowedUDPPorts = [ 9757 ]; };
  networking.firewall.interfaces.wlp116s0f4u1 = { allowedTCPPorts = [ 9757 ]; allowedUDPPorts = [ 9757 ]; };
  home-manager.users.s = {
    home.packages = [ start stop wayvr (game "vrchat-wivrn" "vrchat") (game "forefront-wivrn" "forefront") ];
    systemd.user.services.wayvr-wivrn = {
      Unit = {
        Description = "WayVR debug build on WiVRn";
        Requires = [ "wivrn.service" ];
        After = [ "wivrn.service" "graphical-session.target" ];
        BindsTo = [ "wivrn.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        WorkingDirectory = "/home/s/code/wayvr";
        ExecStart = "/home/s/code/wayvr/target/debug/wayvr --replace --openxr";
        Environment = [
          "XR_RUNTIME_JSON=${manifest}"
          "WAYLAND_DISPLAY=wayland-1"
          "WAYVR_LOGFILE=/dev/null"
          "RUST_BACKTRACE=1"
        ];
        TimeoutStopSec = 10;
      };
    };
  };
}
