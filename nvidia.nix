{ config, pkgs, ... }:
{
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
      # Trial for recurring Monado Xid 51/154; see docs/nvidia-reset-20260917.md.
      # Keep nixpkgs/kernel fixed and retain the Beyond DSC patch below.
      let base = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "615.78.08";
        sha256_64bit = "sha256-Pj9t3cLudnoIGFMAr3vjyyhuznZpjS3eNSRZl4LQf/4=";
        openSha256 = "sha256-HBINiOjL0ZJLIAJeNIBYHBnwgUXtNwPPtnFpAI1YwF4=";
        settingsSha256 = "sha256-inDRpG02sdDgHmlqgu/DsgK8OFdOt1fZIYyXdhlGC/c=";
        persistencedSha256 = "sha256-RzeR6Ldct6MUxjnXRyThdh5Y3jjMehTVg85MtwuWNX4=";
      };

        # nixpkgs 02c087f moved stdenv to patchelf 0.19.2; patchelf >= 0.18 adds
        # a RW LOAD segment to nvidia-smi that overlaps the next R-only one, so
        # .dynamic ends up read-only and ld.so segfaults in dl_main
        # (SEGV_ACCERR). Re-patch the programs from the pristine origBin/ copies
        # with 0.15.2 (nixpkgs' previous patchelf; verified to work here).
        patchelf_0_15 = pkgs.patchelf.overrideAttrs (finalAttrs: _: {
          version = "0.15.2";
          src = pkgs.fetchurl {
            url = "https://github.com/NixOS/patchelf/releases/download/${finalAttrs.version}/patchelf-${finalAttrs.version}.tar.bz2";
            hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
          };
          doCheck = false;
        });
        fixed = base.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            for f in $bin/origBin/*; do
              p=$bin/bin/$(basename $f)
              interp=$(${patchelf_0_15}/bin/patchelf --print-interpreter $p)
              rpath=$(${patchelf_0_15}/bin/patchelf --print-rpath $p)
              install -m755 $f $p
              ${patchelf_0_15}/bin/patchelf --set-interpreter $interp --set-rpath $rpath $p
            done
          '';
        });
      in fixed // {
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
}
