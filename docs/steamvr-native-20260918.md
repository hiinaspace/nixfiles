# Native SteamVR on sayu

September 18, 2026: SteamVR 2.17.10 (build 25330290), Bigscreen Beyond,
NVIDIA 615.71.09, kernel 6.18.49. User confirmed tracking, dashboard and Home.

## Commands

- Stop Monado normally before `start-steamvr`; the launcher refuses an existing
  Monado or SteamVR server. It powers the lighthouses using the existing service.
- `steamvr-run COMMAND ...` selects native SteamVR's OpenVR/OpenXR libraries for
  that command, inside the Steam FHS environment.
- `vrchat-frame [ARGS...]` and `forefront-frame [ARGS...]` launch the games
  directly through the configured Proton-RTSP 11 and Steam Linux Runtime 4,
  using their existing Steam prefixes and normal launch executables. Start
  Steam and the Frame SteamVR session and connect the headset first. These
  commands bypass saved Steam launch options, including Monado overrides.
  Forefront retains Steam's default `-controlscheme openxr` arguments.
  Add `--dry-run` to inspect the command without starting the game.
  Both commands inherit Steam's video authorization token and repair the
  active session's OpenVR registry after Home Manager activations.
- `stop-steamvr` stops the native runtime, restores the exact previous OpenVR
  registry symlink/file, and leaves the lighthouses powered on.
- `journalctl --user -u steamvr-native` and Steam's `logs/vrserver.txt` /
  `logs/vrcompositor.txt` provide startup and runtime diagnostics.

The launcher service must receive the graphical session environment, notably
`WAYLAND_DISPLAY` (wayland-1 on this session) and DISPLAY. SteamVR can use its
X11 UI while separately acquiring the headset through Wayland DRM leasing.
Missing WAYLAND_DISPLAY caused Compositor_CannotDRMLeaseDisplay. Forcing the
whole SDL application to Wayland was not needed.

Home Manager normally selects XRizer through a read-only OpenVR registry
symlink. SteamVR's container/Steam-launched child processes do not reliably
inherit VR_OVERRIDE, so the session wrapper temporarily replaces that registry.
It renames the original to `~/.config/openvr/openvrpaths.vrpath.before-steamvr`.
On normal shutdown it restores the original only if no external edit changed
the runtime selection. If Home Manager already restored identical contents via
a new generation symlink, cleanup keeps that newer link. An existing backup blocks startup rather than losing it.
If interrupted abnormally, first verify both runtimes are stopped; inspect the
current registry and backup before restoring that exact original. Do not delete
the backup blindly. The global OpenXR default is not changed.

The module reapplies cap_sys_nice to the installed vrcompositor-launcher at Nix
activation. Steam updates can replace that file; rebuilding reapplies it.
The Beyond DSC patch and NVIDIA version were preserved. No reboot was required.

## Scope of validation

- Nix candidate built, closure diff reviewed, and configuration switched.
- Startup, user-visible Home/dashboard/head tracking, orderly stop, exact XRizer
  symlink restoration, lighthouse persistence, and second startup passed.
- OpenVR Background preserved a disposable scene and returned valid tracking.
- XR_MND_headless exists, XR_EXTX_overlay does not. Creating a headless OpenXR
  session evicted the disposable scene. Prim must use OpenVR for coexistence.
- Prim with the Vulkan extension fix passed 14 live scene checks: stereo/IPD on
  two entries, tracked head/hands, game eviction, 45-second process survival,
  and orderly disable. Windows and long-session performance remain separate gates.

Primary setup reference: https://vronlinux.org/docs/hardware/bigscreen-beyond/
