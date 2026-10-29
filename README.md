# nixfiles (VR)

The VR part of Hiina's NixOS config, published for reference: read it, copy
what's useful, modify it for your machine. It is not a supported drop-in flake.
(The rest of the config is private and imports these files as a flake input,
which is the only reason it has a `flake.nix`.)

Nearly all of it was written by coding agents, and the expected reader is
probably another agent adapting it to a different machine. So it is kept as the
config that actually runs, quirks and all, rather than tidied into a general
module with options. Comments say why each odd setting exists.

## Hardware it runs on

- NVIDIA RTX 4090 (open kernel module) next to an AMD iGPU that drives the desktop
- Bigscreen Beyond 2e (wired, DisplayPort leased to Monado via Wayland DRM lease)
- Valve Index controllers and SteamVR base stations
- niri (Wayland) desktop, home-manager as a NixOS module

## What's here

| File | Output | What it does |
| --- | --- | --- |
| `vr.nix` | `nixosModules.monado` | Monado user service with SteamVR's `driver_lighthouse` (`STEAMVR_LH_ENABLE`) instead of libsurvive, compositor env (DRM lease on `DP-4`, NVIDIA ICD only), `usbreset` of the BSB2 tracking module before start, BSB udev rules, stop-VR-before-suspend, pressure-vessel env so Proton sees Monado and `/nix`, xrizer/opencomposite/wayvr packages |
| `nvidia.nix` | `nixosModules.bsb2-nvidia` | pinned NVIDIA driver, [BSB2 DSC fix](https://github.com/triple-groove/nvidia-bsb-dsc-fix) patch (`bsb-dsc-fix.patch`) on the open module, `conceal_vrr_caps`, patchelf 0.15 re-patch of driver programs, explicit nvidia suspend/resume units |
| `steam.nix` | `nixosModules.steam` | Steam with `ntsync` for Proton 11, proton-rtsp (VRChat video players) plus a pinned fallback, latest GE-Proton |
| `steamvr-native.nix` | `nixosModules.steamvr-native` | real SteamVR as a home-manager user unit with temporary OpenVR runtime selection (`scripts/steamvr-session.py`), `start-steamvr`/`stop-steamvr`/`steamvr-run`, VRChat/Forefront launchers, `setcap` on vrcompositor-launcher at activation. Needs home-manager; not in `default` |
| `home-vr.nix` | `homeManagerModules.vr-session` | `start-vr`/`stop-vr`, `vr-session.target`, base-station power (IDs read from `~/.config/vr-lighthouses`, one per line), `openvrpaths.vrpath` pointing at xrizer, VRChat Index bindings, VRChat photo folder out of the Proton prefix |
| `wivrn-local.nix` | `overlays.wivrn-frame` | WiVRn built with CUDA/NVENC from a pinned source; Monado is fetched at WiVRn's `monado-rev` with WiVRn's own `patches/monado` applied |
| `docs/` | | investigation notes: NVIDIA Xid resets under Monado, native SteamVR |

## Using it

Read the files and copy what you need; most of the value is in the comments
next to each setting. Importing the flake directly would get you this exact
machine's settings, which is probably not what you want.

Things that are specific to this machine: user `s` (uid 1000), the headset
connector `DP-4`, `WAYLAND_DISPLAY=wayland-1`, SteamVR under
`/home/s/.local/share/Steam`, the NVIDIA driver version, and the WayVR debug
unit linked from a local checkout. xrizer comes from nixpkgs-xr here; the
author's machine overrides it with a locally patched build.

## Links

- [Linux VR Adventures wiki, NixOS page](https://vronlinux.org/docs/distros/nixos/)
- [nixpkgs-xr](https://github.com/nix-community/nixpkgs-xr)
- [NixOS wiki: VR](https://wiki.nixos.org/wiki/VR)

## License

WTFPL (see `LICENSE`).
