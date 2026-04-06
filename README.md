# nixfiles

NixOS + home-manager configuration for a VR workstation.

## Hardware

- GPU: NVIDIA (open kernel modules)
- HMD: Bigscreen Beyond 2
- Tracking: Valve Lighthouse (via SteamVR driver)

## VR Stack

```
VRChat / OpenVR game
       │
    xrizer          ← OpenVR → OpenXR bridge (replaces SteamVR's vrclient.so)
       │
    Monado          ← OpenXR runtime (systemd user service)
       │
 driver_lighthouse  ← SteamVR's lighthouse driver, loaded directly by Monado
                      (no vrserver needed)
```

**Why not libsurvive?** Monado's libsurvive path for BSB2 was incomplete at the time of writing — tracking was unstable and optical calibration was not BSB2-specific. SteamVR's lighthouse driver knows the BSB2 correctly, so Monado is configured with `STEAMVR_LH_ENABLE=true` to load it directly.

**xrizer** bridges OpenVR API calls (used by VRChat and most SteamVR games) to Monado's OpenXR runtime. `openvrpaths.vrpath` (managed by home-manager) points Proton's OpenVR loader at xrizer's nix store path. `/nix` is exposed inside Steam's pressure-vessel sandbox via `PRESSURE_VESSEL_FILESYSTEMS_RO` so that path is resolvable.

**WayVR** provides a Wayland compositor overlay in VR, accessible via Monado's OpenXR runtime.

## Bigscreen Beyond 2 quirks

- **DSC fix**: `bsb-dsc-fix.patch` patches the NVIDIA kernel module to fix Display Stream Compression for the BSB2's wired connection. Applied via `hardware.nvidia.package.open.overrideAttrs`.
- **Kernel param**: `nvidia-modeset.conceal_vrr_caps=1` prevents VRR negotiation issues on the BSB2.
- **USB HID rebind**: Running Monado can occasionally leave USB interfaces for the BSB2's T20 tracking module unbound, causing SteamVR to lose the headset. A recovery script at `~/reset-devices.sh` rebinds the relevant `usbhid` interfaces without requiring a reboot.

## Other notable components

- **ComfyUI**: Enabled via [comfyui-nix](https://github.com/utensils/comfyui-nix) with CUDA support.
- **sops-nix**: Secrets in `secrets.yaml` are AGE-encrypted and safe to commit. You will need your own age key at `~/.config/sops/age/keys.txt` and must update `.sops.yaml` with your public key.
- **nixpkgs-xr**: Used for up-to-date VR packages (Monado, xrizer, WayVR, etc.).

## Adapting this config

1. Run `nixos-generate-config` to get your own `hardware-configuration.nix` — the one in this repo is machine-specific and will not work on different hardware.
2. Set up your own sops age key and re-encrypt `secrets.yaml` for it.
3. Update `networking.hostName` in `configuration.nix`.
4. If you don't have a BSB2, remove `bsb-dsc-fix.patch` and the related kernel params/udev rules.

## Useful references

- [nixpkgs-xr](https://github.com/nix-community/nixpkgs-xr) — up-to-date VR packages for NixOS
- [Linux VR Adventures Wiki](https://lvra.gitlab.io/) — general Linux VR setup guide
- [sops-nix](https://github.com/Mic92/sops-nix) — secrets management for NixOS
- [comfyui-nix](https://github.com/utensils/comfyui-nix) — ComfyUI NixOS module
