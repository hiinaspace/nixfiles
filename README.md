# nixfiles

My NixOS + home-manager configuration for reference. Main point of interest is
probably the VR setup.

## Hardware

- GPU: NVIDIA 4090 with open kernel driver
- HMD: Bigscreen Beyond 2e

## VR Stack

- xrizer for OpenVR API games like vrchat
- Monado for OpenXR runtime
  - running `driver_lighthouse` for tracking

libsurvive for BSB2 did almost work but the tracking drifts all over; at time
of writing BSB2 is WIP anyway.

To make xriser work, `openvrpaths.vrpath` (managed by home-manager) points
Proton's OpenVR loader at xrizer's nix store path. `/nix` is exposed inside
Steam's pressure-vessel sandbox via `PRESSURE_VESSEL_FILESYSTEMS_RO` so that
path is resolvable.

SteamVR sort of works with the same hardware but has bad screen tearing, and
the steamVR UI renders distorted. IIRC it didn't seem to negotiate the refresh
rate with the bsb2, defaulting to 90 despite the hardware expecting 75. 

## Bigscreen Beyond 2 quirks

- `bsb-dsc-fix.patch` patches the NVIDIA kernel module to fix
  Display Stream Compression for the BSB2's wired connection. Applied via
`hardware.nvidia.package.open.overrideAttrs`.
- kernel param `nvidia-modeset.conceal_vrr_caps=1` prevents VRR negotiation
  issues on the BSB2.

Also monado sometimes breaks the USB interfaces for the BSB2's T20 tracking
module after close, causing SteamVR to lose the headset (if you need to run it
for calibration or something). `reset-devices.sh` rebinds the relevant `usbhid`
interfaces without requiring a reboot on my specific system. This is probably
also automatable in udev or something but didn't try yet.

- [nixpkgs-xr](https://github.com/nix-community/nixpkgs-xr): up-to-date VR packages for NixOS
- [Linux VR Adventures Wiki](https://lvra.gitlab.io/): general Linux VR setup guide
- [sops-nix](https://github.com/Mic92/sops-nix): secrets management for NixOS
