# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# enable flakes
{ config, lib, pkgs, ... }:

let
  sudoplzPackage = pkgs.python3Packages.buildPythonApplication rec {
    pname = "sudoplz";
    version = "0.3.0";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "crypdick";
      repo = "sudoplz";
      rev = "b54495c2eda89337249b2415ec65d4303fb90a26";
      hash = "sha256-/4/nRNfHgQwm1X+Tg3MxIMEGztRmQ5cEo7TBwzbdnG0=";
    };

    build-system = with pkgs.python3Packages; [ hatchling ];
    dependencies = with pkgs.python3Packages; [ keyring ];
    doCheck = false;
  };

  chirashiSsh = pkgs.writeShellScript "chirashi-sshfs-ssh" ''
    exec ${pkgs.openssh}/bin/ssh -F /home/s/.ssh/config "$@"
  '';

  chirashiSshfsOptions = [
    "noauto"
    "x-systemd.automount"
    "_netdev"
    "users"
    "noatime"
    "idmap=user"
    "uid=1000"
    "gid=100"
    "allow_other"
    "default_permissions"
    "reconnect"
    "ServerAliveInterval=15"
    "ServerAliveCountMax=3"
    "IdentityFile=/home/s/.ssh/id_ed25519"
    "UserKnownHostsFile=/home/s/.ssh/known_hosts"
    "ssh_command=${chirashiSsh}"
  ];

  chirashiSshfsMount = remotePath: {
    device = "chirashi:${remotePath}";
    fsType = "sshfs";
    noCheck = true;
    options = chirashiSshfsOptions;
  };

  llama-cpp-cuda = pkgs.llama-cpp.override { cudaSupport = true; };

  # Keep VRChat's media-focused Proton current independently of the broader
  # nixpkgs-xr pin.  The upstream package still points at the older GE 10
  # build; this is the maintained Proton 11 continuation of the same RTSP/MF
  # patchset.  Give the old package a distinct Steam name so it remains an
  # immediately selectable fallback.
  protonRtsp11 =
    (pkgs.proton-ge-bin.override { steamDisplayName = "GE-Proton-rtsp"; }).overrideAttrs
      (
        finalAttrs: _: {
          pname = "proton-rtsp-bin";
          version = "proton-rtsp-11.0-20260609-3";
          src = pkgs.fetchzip {
            url = "https://github.com/SpookySkeletons/proton-rtsp/releases/download/${finalAttrs.version}/${finalAttrs.version}.tar.gz";
            hash = "sha256-Toj9kApuJmmZahBjNWJjE/YfiWEXGi2Oq8PYm3Ub+nI=";
          };
          meta.homepage = "https://github.com/SpookySkeletons/proton-rtsp";
        }
      );

  protonRtsp10Fallback =
    (pkgs.proton-ge-bin.override { steamDisplayName = "GE-Proton-rtsp-10-fallback"; }).overrideAttrs
      (
        finalAttrs: _: {
          pname = "proton-ge-rtsp-bin";
          inherit (pkgs.proton-ge-rtsp-bin) version src;
          meta.homepage = "https://github.com/SpookySkeletons/proton-rtsp";
        }
      );

  # GE 11-6 carries newer upstream VRChat AVPro finite-video and livestream
  # fixes than the June Wine base used by protonRtsp11.  Keep it as an opt-in
  # comparison build rather than changing VRChat's selected RTSP tool.
  protonGe116Vrchat =
    (pkgs.proton-ge-bin.override { steamDisplayName = "GE-Proton11-6-VRChat-test"; }).overrideAttrs
      (
        finalAttrs: _: {
          version = "GE-Proton11-6";
          src = pkgs.fetchzip {
            url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.gz";
            hash = "sha256-rX27DUrrrHtR1cgyr/424m9JPjrdASIisVGv2vWzMAs=";
          };
        }
      );

  # Synchronize the Niri Wayland clipboard and Xwayland's clipboard for Proton
  # applications. This deliberately uses one event-driven Wayland watcher and
  # a small X11 poller rather than scanning every wayland-N/:N display as
  # clipboard-sync does. The latter leaks Wayland file descriptors here and
  # also blocks on WayVR's independent compositor socket.
  clipboard-bridge-wayland-consumer = pkgs.writeShellApplication {
    name = "clipboard-bridge-wayland-consumer";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux pkgs.wl-clipboard pkgs.xclip ];
    text = ''
      set -euo pipefail

      runtime_dir="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
      state_dir="$runtime_dir/clipboard-bridge"
      mkdir -p "$state_dir"
      x11_display="''${DISPLAY:-:0}"


      content="$(mktemp "$state_dir/wayland.XXXXXX")"
      trap 'rm -f "$content"' EXIT
      cat > "$content"
      hash="$(sha256sum "$content" | cut -d ' ' -f 1)"

      if (
        flock -x 9
        test -f "$state_dir/wayland.hash" && test "$(cat "$state_dir/wayland.hash")" = "$hash" && exit 1
        printf '%s' "$hash" > "$state_dir/wayland.hash"
      ) 9> "$state_dir/lock"; then
        # xclip forks to retain X11 selection ownership. Keep it outside the
        # flock scope so the fork cannot inherit and retain the lock FD.
        if timeout 2 env DISPLAY="$x11_display" xclip -selection clipboard -in < "$content"; then
          (
            flock -x 9
            printf '%s' "$hash" > "$state_dir/x11.hash"
          ) 9> "$state_dir/lock"
        fi
      fi
    '';
  };

  clipboard-bridge = pkgs.writeShellApplication {
    name = "clipboard-bridge";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux pkgs.wl-clipboard pkgs.xclip ];
    text = ''
      set -euo pipefail

      runtime_dir="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
      state_dir="$runtime_dir/clipboard-bridge"
      mkdir -p "$state_dir"

      wayland_display="''${WAYLAND_DISPLAY:-wayland-1}"
      x11_display="''${DISPLAY:-:0}"

      poll_x11() {
        while true; do
          content="$(mktemp "$state_dir/x11.XXXXXX")"
          if timeout 2 env DISPLAY="$x11_display" xclip -selection clipboard -out > "$content" 2>/dev/null; then
            hash="$(sha256sum "$content" | cut -d ' ' -f 1)"
            if (
              flock -x 9
              test -f "$state_dir/x11.hash" && test "$(cat "$state_dir/x11.hash")" = "$hash" && exit 1
              printf '%s' "$hash" > "$state_dir/x11.hash"
            ) 9> "$state_dir/lock"; then
              # wl-copy also backgrounds by default, so do not run it while
              # holding the lock for the same reason as xclip above.
              if timeout 2 env WAYLAND_DISPLAY="$wayland_display" wl-copy --type text/plain < "$content"; then
                (
                  flock -x 9
                  printf '%s' "$hash" > "$state_dir/wayland.hash"
                ) 9> "$state_dir/lock"
              fi
            fi
          fi
          rm -f "$content"
          sleep 0.25
        done
      }

      rm -f "$state_dir"/*.hash
      poll_x11 &
      x11_poller=$!
      trap 'kill "$x11_poller" 2>/dev/null || true' EXIT INT TERM
      # wl-paste --watch accepts the callback executable path, but no separate
      # arguments, hence the small dedicated consumer above.
      env WAYLAND_DISPLAY="$wayland_display" \
        wl-paste --no-newline --type text/plain --watch \
          ${clipboard-bridge-wayland-consumer}/bin/clipboard-bridge-wayland-consumer
    '';
  };
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.max-jobs = 2;
  nix.settings.cores = 8;

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./cachix.nix
      ./backup.nix
      ./offsite-borg.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    kernel.sysctl = {
      "fs.inotify.max_user_watches" = 1048576;
      # Keep Magic SysRq available when userspace is too memory-starved to
      # recover normally. This enables REISUB and the emergency OOM trigger (F).
      "kernel.sysrq" = 1;
    };

    loader = {
      efi = {
        canTouchEfiVariables = true;
      };
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        # os-prober can't see Windows here: it skips mounted partitions, and the
        # Windows C: drive is auto-mounted at /mnt/c. Use an explicit entry instead.
        useOSProber = false;
        # Windows lives on the p1 ESP (EA39-327B), restored to /EFI/Microsoft after
        # the reinstall deleted the old shared ESP. This is menu index 2 (after the
        # default NixOS entry + the generations submenu), matching the USB switch below.
        extraEntries = ''
          menuentry "Windows 11" {
            insmod part_gpt
            insmod fat
            insmod search_fs_uuid
            insmod chain
            search --fs-uuid --set=root EA39-327B
            chainloader /EFI/Microsoft/Boot/bootmgfw.efi
          }
        '';

        # if usb stick is inserted, boot to windows by default
        # https://danb.me/blog/grub-usb/
        extraConfig = ''
          search --no-floppy --fs-uuid --set usbswitch C867-7FAC
          if [ "$usbswitch" ] ; then
            set default="Windows 11"
          fi
        '';
      };
    };
    initrd.luks.devices.luksroot = {
      device = "/dev/disk/by-uuid/4339faab-55ba-4eaf-b3cd-f894508f70aa";
      keyFile = "/lukskeyfile";
      #fallbackToPassword = true;
      #preLVM = false; # might not be necessary for keyfile booting
    };
    initrd.secrets = {
      "/lukskeyfile" = "/boot/lukskeyfile";
    };
  };

  networking.hostName = "sayu";
  networking.networkmanager.enable = true;
  networking.interfaces.enp7s0.wakeOnLan.enable = true;

  fileSystems = {
    "/mnt/pool" = chirashiSshfsMount "/mnt/pool";
    "/mnt/nvme" = chirashiSshfsMount "/mnt/nvme";
    "/mnt/www" = chirashiSshfsMount "/mnt/nvme/webdav";
  };
  programs.fuse.userAllowOther = true;

  # Set your time zone.
  time.timeZone = "America/Denver";

  # https://wiki.nixos.org/wiki/NVIDIA
  hardware.graphics.enable = true;
  # Allow UHK Agent to configure and flash Ultimate Hacking Keyboard devices.
  hardware.keyboard.uhk.enable = true;

  # not sure if needed on wayland
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # copying from 
    # https://github.com/TayouVR/nixfiles/blob/49e1f3b4f7351c1601b0cf7a4479008dac95bb78/configs/common/optional/graphics/nvidia.nix#L4
    open = true; # required for BSB2 DSC display fix
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    forceFullCompositionPipeline = false; 
    nvidiaSettings = true;
 
    # https://nixos.wiki/wiki/Nvidia
    # Override to add BSB2 DSC fix patch (https://github.com/triple-groove/nvidia-bsb-dsc-fix)
    package =
      let base = config.boot.kernelPackages.nvidiaPackages.latest;
      in base // {
        open = base.open.overrideAttrs (old: {
          patches = (old.patches or []) ++ [ ./bsb-dsc-fix.patch ];
        });
      };
  };
  # NVIDIA direct mode quirks for wired VR on Wayland.
  boot.kernelParams = [
    "nvidia_drm.fbdev=1"
    "nvidia-modeset.conceal_vrr_caps=1"
    "nvidia.NVreg_TemporaryFilePath=/var/tmp"
  ];

  # NixOS 26.05 doesn't auto-generate nvidia-suspend/resume services.
  # Without the pre-suspend service, the compositor has in-flight DRM flip
  # operations when the driver is suspended → Xid 13 on resume → blank display.
  # nvidia-sleep.sh "suspend" does chvt 63 (stops compositor rendering) then
  # writes to /proc/driver/nvidia/suspend to save driver state cleanly.
  systemd.services.nvidia-suspend = {
    description = "NVIDIA system suspend actions";
    before = [ "systemd-suspend.service" "systemd-hibernate.service" "systemd-hybrid-sleep.service" ];
    wantedBy = [ "systemd-suspend.service" "systemd-hibernate.service" "systemd-hybrid-sleep.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.hardware.nvidia.package}/bin/nvidia-sleep.sh suspend";
      Environment = "PATH=/run/current-system/sw/bin";
    };
  };

  systemd.services.nvidia-resume = {
    description = "NVIDIA system resume actions";
    after = [ "systemd-suspend.service" "systemd-hibernate.service" "systemd-hybrid-sleep.service" ];
    wantedBy = [ "systemd-suspend.service" "systemd-hibernate.service" "systemd-hybrid-sleep.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.hardware.nvidia.package}/bin/nvidia-sleep.sh resume";
      Environment = "PATH=/run/current-system/sw/bin";
    };
  };

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

  programs.steam = {
    enable = true;
    extraCompatPackages = [
      # Current VRChat RTSP/Media Foundation fork, packaged locally above.
      # https://lvra.gitlab.io/docs/vrchat/video_players/
      protonRtsp11
      # Keep the previously working nixpkgs-xr build selectable in Steam.
      protonRtsp10Fallback
      # Opt-in comparison for the newer upstream AVPro implementation.
      protonGe116Vrchat
    ];
  };

  systemd.user.services.clipboard-bridge = {
    description = "Synchronize Niri and Xwayland text clipboards";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${clipboard-bridge}/bin/clipboard-bridge run";
      Restart = "always";
      RestartSec = 1;
    };
  };
  
  # https://github.com/TayouVR/nixfiles/blob/49e1f3b4f7351c1601b0cf7a4479008dac95bb78/configs/common/optional/vr/vr.nix#L34
  # Bigscreen Beyond udev rules (all interfaces: HMD, Bigeye, audio strap, firmware mode)
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="0101", MODE="0660", GROUP="video"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="0202", MODE="0660", GROUP="video"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="0105", MODE="0660", GROUP="video"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="35bd", ATTRS{idProduct}=="4004", MODE="0660", GROUP="video"
  '';

  # https://lvra.gitlab.io/docs/hardware/#applying-a-kernel-patch-for-vive-pro-2-bigscreen-beyond-pimax
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPatches = [
  #  {
  #    name = "bigscreen beyond";
  #    patch = ./beyondKernel.patch;
  #  }
  #];

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

  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;  # Enable the built-in ComfyUI Manager
    listenAddress = "0.0.0.0";
    openFirewall = true;
    extraArgs = [
      "--reserve-vram" "2"
      # ComfyUI otherwise sizes pinned/offload memory against total host RAM,
      # without accounting for this service's cgroup limit.
      "--disable-pinned-memory"
      "--disable-async-offload"
      "--cache-none"
    ];
    customNodes = {
      ComfyUI-ControlNet-Aux = pkgs.fetchFromGitHub {
        owner = "Fannovel16";
        repo = "comfyui_controlnet_aux";
        rev = "e8b689a513c3e6b63edc44066560ca5919c0576e";
        hash = "sha256-tMmERf4y7sfuEGao7JHC7FLjBgPuViCtHxr8f9NnHzo=";
      };
      ComfyUI-segment-anything-2 = pkgs.fetchFromGitHub {
        owner = "kijai";
        repo = "ComfyUI-segment-anything-2";
        rev = "0c35fff5f382803e2310103357b5e985f5437f32";
        hash = "sha256-5e64dKo1VZmwDh1geAVrryb15S5mRXOuOrEJ8ZUfQxM=";
      };
      ComfyUI-workflow-to-api = pkgs.fetchFromGitHub {
        owner = "SethRobinson";
        repo = "comfyui-workflow-to-api-converter-endpoint";
        rev = "bc8538278f82053b3ca10a44d62d02596f8e1a37";
        hash = "sha256-lew7iu788v0FbPyOq6j6KuYJqvRXaiOqYazXyFwU84A=";
      };
      # GGUF-quantized model loading. Needed because the fp8 Wan2.2-Animate-14B
      # weights are 17.1 GiB and cannot load through this service's 12 GiB
      # MemoryMax with MemorySwapMax=0; a Q4_K_M quant is 10.7 GiB and fits.
      # Taken from comfyui-nix's own packaged set (already pinned upstream) rather
      # than a local fetchFromGitHub, and its Python deps (gguf, sentencepiece,
      # protobuf) are already unconditional in the module's pythonRuntime.
      ComfyUI-GGUF = pkgs.comfyui-custom-nodes.gguf;
    };
    environment = {
      AUX_ANNOTATOR_CKPTS_PATH = "/mnt/s/comfyuimodels/controlnet_aux";
      LD_LIBRARY_PATH = lib.makeLibraryPath [
        config.services.comfyui.package.pythonRuntime.pkgs.torch.cudaPackages.cuda_nvrtc.lib
      ];
    };
  };

  # Raised 2026-08-03 from 10G/12G for MiniMax H3. H3 needs two models that each
  # individually exceeded the old cap: the Ref2VA DiT at 13.26 GiB (Q3_K_M) and
  # a Qwen3VL-32B text encoder at 13.58 GiB (Q4_K_M). They load sequentially and
  # --cache-none frees between stages, so the peak is one model plus working
  # buffers, ~16 GiB. MemoryHigh sits under that to apply reclaim pressure
  # first; MemoryMax is the hard stop.
  #
  # This only fits with llama-server and the Unity editor stopped. MemorySwapMax
  # stays 0 so ComfyUI can never push into the 15.2 GiB zram and start a
  # swap-thrash spiral, and OOMScoreAdjust stays 1000 so that if anything must
  # die under pressure it is this service and not the interactive session.
  systemd.services.comfyui.serviceConfig = {
    MemoryAccounting = true;
    MemoryHigh = "15G";
    MemoryMax = "18G";
    MemorySwapMax = 0;
    OOMScoreAdjust = 1000;
    OOMPolicy = "stop";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    ReadWritePaths = lib.mkAfter [
      "/mnt/s/comfyuimodels"
    ];
  };
  systemd.tmpfiles.rules = [
    "L+ /var/lib/comfyui/models - - - - /mnt/s/comfyuimodels"
  ];

  # Added 2026-08-03 alongside the ComfyUI limit raise. With 30.5 GiB of RAM and
  # models that peak near 16 GiB, the failure mode to avoid is not a clean OOM
  # kill but a swap-thrash livelock where the desktop and the agent session stop
  # responding long before the kernel acts. The 15.2 GiB of swap here is zram --
  # RAM-backed compression, so filling it is more memory pressure, not relief,
  # which makes the kernel's own "plenty of swap left" heuristic misleading.
  #
  # ignoreOOMScoreAdjust is left at its default false, so earlyoom honours the
  # OOMScoreAdjust=1000 set on comfyui above and reaches for it first.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 8;
    freeMemKillThreshold = 4;
    freeSwapThreshold = 20;
    freeSwapKillThreshold = 10;
    extraArgs = [
      # Never the session, the compositor, or the agent driving it.
      "--avoid" "^(\\.claude-unwrapp|niri|sshd|systemd|dbus-daemon|kitty)$"
      # The things that are cheap to restart and are usually the actual cause.
      "--prefer" "^(python3\\.12|llama-server|Unity|\\.firefox-wrappe)$"
    ];
  };

  # llama.cpp router mode: serves Qwen3.6-35B-A3B (MoE, 3B active params, Q4_K_XL,
  # 12 expert layers offloaded to CPU RAM - ~105-110 tok/s gen, ~1700 tok/s pp,
  # 98k context in ~20.4GB VRAM) and Gemma4 E4B (small model for quick one-off
  # tasks, ~7.5GB VRAM) from one process. --models-max 1 means only one model is
  # resident at a time - the router evicts the LRU model and loads the requested
  # one on demand (Ollama-style hot-swap), confirmed ~5-10s per swap. Per-model
  # settings live in router-presets.ini alongside the model weights. Exposes both
  # an OpenAI-compatible API (for opencode, at /v1) and a native Anthropic Messages
  # API (for Claude Code, at /v1/messages) - no proxy needed for either.
  systemd.services.llama-server = {
    description = "llama.cpp server (router: Qwen3.6-35B-A3B / Gemma4 E4B)";
    # Deliberately not in multi-user.target as of 2026-08-03: it holds ~7.3 GiB
    # of VRAM resident, which is the difference between MiniMax H3 loading and
    # OOMing on a 24 GiB card, and it was auto-restarting on every rebuild.
    # Start it on demand with `systemctl start llama-server`.
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = ''
        ${llama-cpp-cuda}/bin/llama-server \
          --models-dir /home/s/.cache/llama-models \
          --models-preset /home/s/.cache/llama-models/router-presets.ini \
          --models-max 1 \
          --host 127.0.0.1 --port 11434
      '';
      Restart = "on-failure";
      User = "s";
      Group = "users";
    };
  };

  # Enable sound.
  security.rtkit.enable = true;

  # Wine audio plugins bridged by yabridge use shared-memory audio buffers.
  # Let members of the audio group lock those buffers instead of falling back
  # to the host's small default memlock limit.
  security.pam.loginLimits = [
    {
      domain = "@audio";
      type = "-";
      item = "memlock";
      value = "unlimited";
    }
  ];

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };
  
  # xdg portal for screensharing
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    # pikeru as the file picker backend (its .portal/dbus/systemd units ship in the package).
    extraPortals = [ pkgs.pikeru ];
    # Set FileChooser on both the common config and the sway-specific one.
    # programs.sway generates sway-portals.conf with `default=gtk`, which takes
    # precedence over portals.conf for sway sessions; without an explicit
    # FileChooser there, `default=gtk` would catch it and shadow pikeru.
    config.common."org.freedesktop.impl.portal.FileChooser" = [ "pikeru" ];
    config.sway."org.freedesktop.impl.portal.FileChooser" = [ "pikeru" ];
  };

  # pikeru's portal binary searches /usr/... for its wrapper, which doesn't exist
  # on NixOS, so point it at the store path via the system config (read from
  # /etc/xdg per portal.rs find_config()).
  environment.etc."xdg/xdg-desktop-portal-pikeru/config".text = ''
    log_level = info

    [filepicker]
    cmd = ${pkgs.pikeru}/share/xdg-desktop-portal-pikeru/pikeru-wrapper.sh
    default_save_dir = ~/Downloads
    postprocessor =
    postprocess_dir = /tmp/pk_postprocess

    [indexer]
    enable = false
  '';

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
    ];
    fontconfig = {
      antialias = true;
      hinting.enable = true;
      defaultFonts = {
        sansSerif = [
          "Noto Sans"
          "Noto Sans CJK JP"
          "Noto Sans CJK KR"
          "Noto Sans CJK SC"
          "Noto Sans CJK TC"
          "Noto Sans CJK HK"
        ];
        serif = [
          "Noto Serif"
          "Noto Serif CJK JP"
          "Noto Serif CJK KR"
          "Noto Serif CJK SC"
          "Noto Serif CJK TC"
          "Noto Serif CJK HK"
        ];
        monospace = [
          "Noto Sans Mono"
          "Noto Sans Mono CJK JP"
          "Noto Sans Mono CJK KR"
          "Noto Sans Mono CJK SC"
          "Noto Sans Mono CJK TC"
          "Noto Sans Mono CJK HK"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
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
  environment.sessionVariables.SUDO_ASKPASS = "${sudoplzPackage}/bin/askpass";

  # Lets prebuilt/non-Nix binaries (e.g. `uv run --with numpy`'s manylinux
  # wheels) find standard FHS-layout shared libs like libstdc++.so.6 that
  # NixOS doesn't expose by default.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = [ pkgs.stdenv.cc.cc.lib ];

  nixpkgs.config.allowUnfree = true;
  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    binutils
    efibootmgr
    neovim
    wget
    grim # screenshot
    slurp # more screenshot
    wl-clipboard # wayland clipboard
    xclip # xwayland clipboard bridge
    xwayland-satellite # X11 support for niri; niri >=25.08 auto-spawns it on-demand when in PATH
    mako # sway notifications
    element-desktop
    uhk-agent
    #factorio-space-age
    pavucontrol
    usbutils # lsusb
    # OpenVR → OpenXR bridge for games like VRChat
    # https://lvra.gitlab.io/docs/fossvr/xrizer/
    xrizer
    # (opencomposite kept as fallback)
    opencomposite
    # vr overlay thing
    wayvr
    comfy-ui-cuda
    lovr-playspace
    age
    sudoplzPackage
    zenity
    python3
    bubblewrap
    glib # for gsettings
    gsettings-desktop-schemas # for prefer-dark/prefer-light
    dconf-editor # also for prefer-dark/light
  ];

  # some sort of graphical greeter login prommpt
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Default (just press Enter) stays the working sway command with the
        # NVIDIA `--unsupported-gpu` flag. `--sessions` adds a selectable session
        # menu (toggle in tuigreet) populated from the registered Wayland sessions
        # (programs.niri adds niri.desktop there), so niri is pickable without
        # touching sway's default path.
        # CAVEAT: the menu's plain "sway" entry (from programs.sway) lacks
        # `--unsupported-gpu`; for sway just press Enter to use this default cmd,
        # and select "niri" from the menu when you want niri.
        # Do not launch the compositor directly: niri-session imports the login
        # environment into both systemd --user and D-Bus, then starts the
        # niri.service lifecycle. Bare `niri` leaves D-Bus-activated portals
        # and user services without WAYLAND_DISPLAY / XDG_CURRENT_DESKTOP.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd 'niri-session'";
        user = "greeter";
      };
    };
  };

  # This will add secrets.yml to the nix store
  # You can avoid this by adding a string to the full path instead, i.e.
  # sops.defaultSopsFile = "/root/.sops/secrets/example.yaml";
  sops.defaultSopsFile = ./secrets.yaml;
  # This is using an age key that is expected to already be in the filesystem
  sops.age.keyFile = "/home/s/.config/sops/age/keys.txt";
  sops.secrets.spassword.neededForUsers = true;

  # Curated offsite home backup. This is intentionally independent of the LAN
  # borgmatic job in backup.nix, so an Internet/provider failure cannot suppress
  # the local copy to chirashi.
  services.borgOffsite = {
    enable = true;
    repository = "fm3170@fm3170.rsync.net:borg/sayu";
    startAt = "02:30";
  };
  programs.ssh.knownHosts."fm3170.rsync.net".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdUkGe6kKn5ssz4WRZKjcws0InbQqZayenzk9obmP1z";

  # Impermanence wipes /etc (incl. /etc/shadow) every boot, so passwords must be
  # fully declarative: mutableUsers=false makes NixOS re-assert hashedPasswordFile
  # into /etc/shadow on every activation. With the default (true), the sops hash
  # lands in /run/secrets-for-users but never reliably reaches the wiped shadow,
  # so console/sudo auth fails even though the hash matches the password.
  users.mutableUsers = false;

  users.users.s = {
    isNormalUser = true;
    # sudo, video and input for maybe VR compat
    extraGroups = [ "wheel" "video" "input" "audio" ];
    packages = with pkgs; [
      tree
    ];
    hashedPasswordFile = config.sops.secrets.spassword.path;
  };

  security.sudo.extraRules = [
    {
      users = [ "s" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          # Allow a manual acceptance/restore-drill run without granting broad
          # passwordless systemctl access.
          command = "/run/current-system/sw/bin/systemctl start --no-block borgbackup-job-offsite.service";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Impermanence wipes /var each boot, which resets sudo's per-user "lectured"
  # flag, so the lecture would show on the first sudo of every boot. Silence it.
  security.sudo.extraConfig = "Defaults lecture = never";

  programs.firefox.enable = true;
  
  # apparently needed for secret storage through dbus
  services.gnome.gnome-keyring.enable = true;

  # window manager
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  # niri, added alongside sway (groundwork for the viri project). programs.niri
  # (nixos-unstable) installs the package, registers the Wayland session via
  # services.displayManager.sessionPackages so the greeter can launch it, wires
  # systemd user units, and sets up portals. Config lives in ~/.config/niri/
  # config.kdl (deployed from dotfiles/niri via home.nix).
  programs.niri = {
    enable = true;
    # Don't pull in GNOME Nautilus as the file chooser; we use pikeru (below),
    # matching the sway session.
    useNautilus = false;
  };
  # Route niri's FileChooser portal to pikeru, mirroring config.sway above.
  # programs.niri (with useNautilus=false) already sets this key to "gtk", so
  # mkForce is needed to override that into pikeru.
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = lib.mkForce [ "pikeru" ];

  # The GTK portal is D-Bus activated by the user systemd manager. That
  # manager can lose the compositor environment (notably after resume), at
  # which point the backend exits with "cannot open display" and cannot expose
  # the desktop color scheme through the Settings portal. Niri's socket is
  # deliberately stable on this host; make it available directly to the
  # backend instead of relying on an activation-environment import.
  systemd.user.services.xdg-desktop-portal-gtk.environment = {
    GDK_BACKEND = "wayland";
    WAYLAND_DISPLAY = "wayland-1";
  };

  # https://nixos.wiki/wiki/Fish
  programs.fish.enable = true;
  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };

  # https://wiki.nixos.org/wiki/Storage_optimization
  nix.settings.auto-optimise-store = true;

  # Compressed RAM swap; no on-disk swap (the old in-LUKS swap partition is gone
  # with the btrfs reinstall). No hibernate.
  zramSwap.enable = true;

  # /etc/nixos -> the flake repo in /home (persistent). Declarative so it survives
  # the per-boot impermanence wipe of /etc; the repo itself lives on @home.
  environment.etc."nixos".source = "/home/s/nixos-config";

  # for bitwig
  services.flatpak.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # Shows battery charge of connected devices on supported
        # Bluetooth adapters. Defaults to 'false'.
        Experimental = true;
        # When enabled other devices can connect faster to us, however
        # the tradeoff is increased power consumption. Defaults to
        # 'false'.
        FastConnectable = true;
      };
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?

}
