# Home Manager side of the wired VR stack: base-station power, start-vr/stop-vr,
# the vr-session target, and OpenVR/xrizer config for Proton games.
{ config, pkgs, ... }:

let
  # Lighthouse 2.0.0 includes our base-station write retries.
  lighthouse-steamvr = pkgs.lighthouse-steamvr;

  vr-lighthouses = pkgs.writeShellApplication {
    name = "vr-lighthouses";
    runtimeInputs = [ lighthouse-steamvr ];
    text = builtins.readFile ./scripts/vr/vr-lighthouses.sh;
  };

  start-vr = pkgs.writeShellApplication {
    name = "start-vr";
    runtimeInputs = with pkgs; [ coreutils gnugrep libnotify systemd ];
    text = builtins.readFile ./scripts/vr/start-vr.sh;
  };

  stop-vr = pkgs.writeShellApplication {
    name = "stop-vr";
    runtimeInputs = [ pkgs.systemd ];
    text = builtins.readFile ./scripts/vr/stop-vr.sh;
  };

  stop-wayvr = pkgs.writeShellApplication {
    name = "stop-wayvr";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/vr/stop-wayvr.sh;
  };
in {
  home.packages = [
    lighthouse-steamvr
    vr-lighthouses
    start-vr
    stop-vr
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
  # in vr.nix.
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
}
