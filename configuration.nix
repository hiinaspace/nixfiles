# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# enable flakes
{ config, lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.max-jobs = 2;
  nix.settings.cores = 8;

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./cachix.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
      };
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = true;
        # I think the osprober works now so unnecessary
        #extraEntries = ''
        #  menuentry "Windows 11" {
        #    insmod part_gpt
        #    insmod fat
        #    insmod search_fs_uuid
        #    insmod chain
        #    search --fs-uuid --set=root EA39-327B
        #    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        #  }
        #'';

        # if usb stick is inserted, boot to windows by default
        # https://danb.me/blog/grub-usb/
        extraConfig = ''
          search --no-floppy --fs-uuid --set usbswitch C867-7FAC
          if [ "$usbswitch" ] ; then
            set default=2
          fi
        '';
      };
    };
    initrd.luks.devices.luksroot = {
      device = "/dev/disk/by-uuid/4339faab-55ba-4eaf-b3cd-f894508f70aa";
      keyFile = "/lukskeyfile";
      fallbackToPassword = true;
      preLVM = false; # might not be necessary for keyfile booting
    };
    initrd.secrets = {
      "/lukskeyfile" = "/boot/lukskeyfile";
    };
  };

  networking.hostName = "sayu";
  networking.networkmanager.enable = true;

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
    powerManagement.enable = false;
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
  ];

  programs.steam = {
    enable = true;
    extraCompatPackages = with pkgs; [
      # from https://github.com/nix-community/nixpkgs-xr
      # https://lvra.gitlab.io/docs/vrchat/video_players/
      proton-ge-rtsp-bin
    ];
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
  systemd.user.services.monado.environment = {
    XRT_NO_STDIN = "1";
    XRT_COMPOSITOR_DESIRED_MODE = "1";
    XRT_COMPOSITOR_COMPUTE = "1";
    U_PACING_COMP_MIN_TIME_MS = "5";
    XRT_COMPOSITOR_USE_PRESENT_WAIT = "1";
    U_PACING_COMP_TIME_FRACTION_PERCENT = "90";

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
  };

  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;  # Enable the built-in ComfyUI Manager
    listenAddress = "0.0.0.0";
    openFirewall = true;
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
  };
  # Expose the host OpenXR runtime inside Steam's pressure-vessel sandbox.
  # Without this, Proton can't see Monado's active_runtime.json.
  # https://lvra.gitlab.io/docs/fossvr/xrizer/
  environment.sessionVariables.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
  # Expose /nix store paths inside pressure-vessel so that openvrpaths.vrpath
  # (which references xrizer's nix store path) can be resolved by Proton.
  environment.sessionVariables.PRESSURE_VESSEL_FILESYSTEMS_RO = "/nix:/run/current-system";

  nixpkgs.config.allowUnfree = true;
  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    grim # screenshot
    slurp # more screenshot
    wl-clipboard # wayland clipboard
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
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'sway --unsupported-gpu'";
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

  users.users.s = {
    isNormalUser = true;
    # sudo, video and input for maybe VR compat
    extraGroups = [ "wheel" "video" "input" ];
    packages = with pkgs; [
      tree
    ];
    hashedPasswordFile = config.sops.secrets.spassword.path;
  };

  programs.firefox.enable = true;
  
  # apparently needed for secret storage through dbus
  services.gnome.gnome-keyring.enable = true;

  # window manager
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
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
