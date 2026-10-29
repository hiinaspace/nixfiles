{ lib, pkgs, ... }:
{
  # --- Wired VR (Bigscreen Beyond 2 + lighthouses) via Monado ---------------

  # https://wiki.nixos.org/wiki/VR
  services.monado = {
    enable = true;
    defaultRuntime = true; # Publish Monado as the active OpenXR runtime for native clients like WayVR
    highPriority = true;   # CAP_SYS_NICE for compositor thread priority
  };
  systemd.user.services.monado.serviceConfig = {
    # Reset the BSB's Tundra tracking module before Monado opens it. Ignore a
    # missing/disconnected headset instead of making Monado fail to start.
    ExecStartPre = [
      "-${pkgs.usbutils}/bin/usbreset 28de:2300"
      "${pkgs.systemd}/bin/udevadm settle"
    ];
    # A wedged Vulkan/OpenXR teardown can otherwise consume most of the user
    # manager's two-minute shutdown timeout.
    TimeoutStopSec = "10s";
  };
  systemd.user.services.monado.environment = {
    # Startup may restart Monado while waiting for all lighthouse devices.
    # Keep retries from putting already-discovered controllers to sleep.
    # A separate standby probe cannot be used here: monado-cli test selects
    # libsurvive and leaves the radios detached from usbhid on this hardware.
    LH_STANDBY_ON_EXIT = "0";
    XRT_NO_STDIN = "1";
    XRT_COMPOSITOR_DESIRED_MODE = "1";
    XRT_COMPOSITOR_COMPUTE = "1";
    XRT_COMPOSITOR_FORCE_GPU_INDEX = "0";
    XRT_COMPOSITOR_FORCE_CLIENT_GPU_INDEX = "0";
    XRT_COMPOSITOR_PIPEWIRE_MIRROR = "0";
    XRT_COMPOSITOR_FORCE_WAYLAND_DIRECT = "1";
    XRT_COMPOSITOR_WAYLAND_CONNECTOR = "DP-4";
    # Monado is socket-activated by the user manager, which does not retain
    # Niri's display name across suspend. Pin the session's compositor socket
    # so a post-resume compositor initialization can always acquire its lease.
    WAYLAND_DISPLAY = "wayland-1";
    U_PACING_COMP_MIN_TIME_MS = "5";
    XRT_COMPOSITOR_USE_PRESENT_WAIT = "1";
    U_PACING_COMP_TIME_FRACTION_PERCENT = "90";

    # The BSB display is leased from the NVIDIA card. Use Wayland DRM leasing
    # to avoid the NVIDIA Xlib direct-display path getting wedged after resume.
    # Keep Monado from auto-selecting the AMD iGPU's RADV device.
    VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";

    # libsurvive: freeze global scene solver, fix timing for BSB2
    # (harmless when using steamvr_lh builder)
    SURVIVE_GLOBALSCENESOLVER = "0";
    SURVIVE_TIMECODE_OFFSET_MS = "-6.94";

    # SteamVR lighthouse builder: loads driver_lighthouse.so directly,
    # does NOT require vrserver to be running.
    # With this set, Monado uses SteamVR's lighthouse driver for tracking
    # instead of libsurvive. BSB2 tracking via libsurvive was unstable;
    # SteamVR's driver knows the BSB2 correctly.
    STEAMVR_LH_ENABLE = "true";
    STEAMVR_PATH = "/home/s/.local/share/Steam/steamapps/common/SteamVR";

    # Make GStreamer plugin discovery explicit for the user service so
    # PipeWire sink/source elements are visible from Monado.
    GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer
      pkgs.gst_all_1.gst-plugins-base
      pkgs.pipewire
    ];
    GST_PLUGIN_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer
      pkgs.gst_all_1.gst-plugins-base
      pkgs.pipewire
    ];
    GST_PLUGIN_SCANNER = "${pkgs.gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner";
  };

  # https://github.com/TayouVR/nixfiles/blob/49e1f3b4f7351c1601b0cf7a4479008dac95bb78/configs/common/optional/vr/vr.nix#L34
  # Bigscreen Beyond udev rules (all interfaces: HMD, Bigeye, audio strap, firmware mode)
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="0101", MODE="0660", GROUP="video"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="0202", MODE="0660", GROUP="video"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="0105", MODE="0660", GROUP="video"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="4004", MODE="0660", GROUP="video"
  '';

  # Direct-mode Vulkan and lighthouse USB state do not reliably survive
  # suspend. Leave the VR stack stopped after resume; the next WayVR launch
  # socket-activates a fresh Monado instance.
  systemd.services.vr-stop-before-sleep = {
    description = "Stop the user VR stack before sleep";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.systemd}/bin/systemctl --user --machine=s@.host \
        stop wayvr-debug.service monado.service || true
    '';
  };

  # Expose the host OpenXR runtime inside Steam's pressure-vessel sandbox.
  # Without this, Proton can't see Monado's active_runtime.json.
  # https://lvra.gitlab.io/docs/fossvr/xrizer/
  environment.sessionVariables.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
  # Make xrizer's OpenXR runtime lookup explicit for Proton/OpenVR games.
  environment.sessionVariables.XR_RUNTIME_JSON = "/run/current-system/sw/share/openxr/1/openxr_monado.json";
  # Expose /nix store paths inside pressure-vessel so that openvrpaths.vrpath
  # (which references xrizer's nix store path) can be resolved by Proton.
  environment.sessionVariables.PRESSURE_VESSEL_FILESYSTEMS_RO = "/nix:/run/current-system";
  # Expose Monado's user IPC socket inside pressure-vessel for xrizer clients.
  environment.sessionVariables.PRESSURE_VESSEL_FILESYSTEMS_RW = "/run/user/1000/monado_comp_ipc";
  environment.systemPackages = with pkgs; [
    # OpenVR → OpenXR bridge for games like VRChat
    # https://lvra.gitlab.io/docs/fossvr/xrizer/
    xrizer
    # (opencomposite kept as fallback)
    opencomposite
    # vr overlay thing
    wayvr
    lovr-playspace
  ];
}
