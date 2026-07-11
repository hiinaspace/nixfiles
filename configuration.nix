# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# enable flakes
{ config, lib, pkgs, ... }:

let
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
    ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    kernel.sysctl = {
      "fs.inotify.max_user_watches" = 1048576;
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

  programs.steam = {
    enable = true;
    extraCompatPackages = with pkgs; [
      # from https://github.com/nix-community/nixpkgs-xr
      # https://lvra.gitlab.io/docs/vrchat/video_players/
      proton-ge-rtsp-bin
    ];
  };

  services.clipboard-sync.enable = true;
  
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
  systemd.user.services.monado.environment = {
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
    environment.LD_LIBRARY_PATH = lib.makeLibraryPath [
      config.services.comfyui.package.pythonRuntime.pkgs.torch.cudaPackages.cuda_nvrtc.lib
    ];
  };

  systemd.services.comfyui.serviceConfig.ReadWritePaths = lib.mkAfter [
    "/mnt/s/comfyuimodels"
  ];

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
    wantedBy = [ "multi-user.target" ];
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
    python3
    bubblewrap
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
        command = "${pkgs.tuigreet}/bin/tuigreet --time --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd 'niri'";
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

  # Impermanence wipes /etc (incl. /etc/shadow) every boot, so passwords must be
  # fully declarative: mutableUsers=false makes NixOS re-assert hashedPasswordFile
  # into /etc/shadow on every activation. With the default (true), the sops hash
  # lands in /run/secrets-for-users but never reliably reaches the wiped shadow,
  # so console/sudo auth fails even though the hash matches the password.
  users.mutableUsers = false;

  users.users.s = {
    isNormalUser = true;
    # sudo, video and input for maybe VR compat
    extraGroups = [ "wheel" "video" "input" ];
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
