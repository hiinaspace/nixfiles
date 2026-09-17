# Sayu NVIDIA reset investigation — 2026-09-17

## Findings before any activation

RTX 4090 (0000:01:00.0), Linux 6.18.49, NVIDIA open kernel module,
userspace and GSP 610.57.04. Niri Wayland; normal Monado uses the patched
nixpkgs-xr build, compute compositor, NVIDIA ICD, Wayland DRM lease on DP-4,
present-wait enabled. Existing Beyond DSC patch is applied to the open driver.
Memory preservation and kernel suspend notifiers are enabled, alongside local
legacy suspend/resume services. This overlap is worth a separate suspend audit;
neither matching crash is shown to be a suspend/resume event.

Retained kernel journals (24 boots, beginning June 29) contain two exact matches:

| Local MDT time | Process | Failure |
| --- | --- | --- |
| September 14 21:03:27 | monado-service 3023114 | Xid 51 BAD_TSG, runlist 0, error 4; Xid 154 None -> PF FLR |
| September 17 15:55:15 | monado-service 75109 | Same signature |

Both boots loaded 610.57.04 and kernel 6.18.49. September 11 also has a distinct
Godot Xid 31 MMU fault; older June graphics exceptions are not this signature.
No matching AER error, hardware-error or fallen-off-bus messages were found in
the retained kernel journal search. Current PCIe replay counters are zero;
50 C and ~55 W were observed after the crash, not at its onset. These observations
do not exclude a transient power, temperature or hardware fault.

NVIDIA reports GPU Recovery Action: Reset. New Vulkan device creation fails
with NV_ERR_RESET_REQUIRED / VK_ERROR_INITIALIZATION_FAILED even after the test
processes exit. Existing GPU clients remain alive. Restarting Prim alone is
therefore insufficient.

The Prim runner creates a private XDG_RUNTIME_DIR and QWERTY/null Monado runtime;
its runtime.terminate() targets that child, not normal Monado PID 75109. The
private runtime still shares the physical GPU. The 15:54:58 run reaches runtime
loss and desktop fallback, then cannot re-enter XR; the 15:56:10 isolated launch
fails at initial Vulkan creation. The preceding 15:32:04 run succeeded per its
recorded checks. Normal Monado logs frame misses before both matching incidents,
without a recorded teardown in those immediate windows.

Working hypothesis: NVIDIA scheduling/GSP recovery failure triggered by a VR /
Vulkan interaction. The named process identifies the affected context, not proof
that Monado supplied invalid work. Teardown/concurrent submission remains a
possible trigger, and the first incident predates today's injection. No single
root cause is established; do not repeat runtime-loss injection to prove it.

## Driver choice and limits

NVIDIA's live Unix page lists 615.71.09 as the new-feature release (September 9),
595.99.02 as production. Both the checkout's package source and fetched
nixos-unstable default.nix still select 610.57.04 as latest. Thus a whole-flake
update is neither necessary nor sufficient evidence of a newer driver.

615.71.09 is a reasonable optional trial, not a known fix for Xid 51/error 4.
Release notes mention a Vulkan instance-unload file descriptor leak, Wayland /
display low-latency fixes and an unrelated Xid 109 fix. They do not claim a
Monado BAD_TSG fix. RTX 4090 is supported. A first-hand report describes DPMS/DSC
restore failure on RTX 5080 + Samsung monitor; applicability to Beyond/4090 is
unknown, but it is a concrete regression risk to test.

The narrow configuration change uses nvidiaPackages.mkDriver, pins all four
source hashes, and retains open=true and bsb-dsc-fix.patch. The pinned NixOS
module supports mkDriver, gsp.enable and powerManagement.kernelSuspendNotifier;
GSP and the notifier evaluate true. No GSP-disable or power-management experiment
is combined with the version change. Existing firewall and flake.lock edits are
preserved; no Prim files were changed.

Sources checked live:
- https://www.nvidia.com/en-us/drivers/unix/
- https://forums.developer.nvidia.com/t/615-release-feedback-discussion/382815
- https://download.nvidia.com/XFree86/Linux-x86_64/615.71.09/README/supportedchips.html
- https://forums.developer.nvidia.com/t/615-71-09-regression-displayport-link-never-re-established-after-monitor-dpms-sleep-connector-marked-zombie-flush-mode-fails-no-signal-until-phy/383236
- https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/pkgs/os-specific/linux/nvidia-x11/default.nix

## Candidate and rollback

Build-only command (does not install a boot entry or activate):

```sh
nix build .#nixosConfigurations.sayu.config.system.build.toplevel \
  --out-link .local/nvidia-investigation-20260917/candidate -L
```

Evidence and build log: `.local/nvidia-investigation-20260917/`.
Current and booted system both resolve to:
`/nix/store/ilsk3m835xbklc5r9zd5mvcrn9dr89fj-nixos-system-sayu-26.11.20260907.dc5d91f`.
This is system generation 101, present in `/boot/grub/grub.cfg` as
`NixOS - Configuration 101 (2026-09-14 - 26.11.20260907.dc5d91f)`.

Only after explicit authorization: install the reviewed candidate for next boot
using `nixos-rebuild boot --flake .#sayu` (not switch), verify the generated GRUB
entry, and reboot when the user chooses. Re-check the resulting store path against
the reviewed candidate before reboot. Preserve generation 101; do not garbage
collect it. If the candidate fails, select Configuration 101 from GRUB's NixOS
configurations submenu. Revert only the mkDriver stanza to the previous `latest`
selection for source rollback; preserve unrelated dirty changes.

After boot: verify kernel module, nvidia-smi/GSP and userspace all report 615.71.09;
check fresh Vulkan device creation, then normal Monado, headset image/controllers,
ordinary Prim desktop/VR transitions, and DP/display wake. Monitor for new Xids.
A successful build is not a boot, headset, suspend or crash-fix validation.
No reset, desktop/service restart, switch, boot installation or reboot has been
performed by this investigation.

Build result: success (exit 0). Candidate:
`/nix/store/9ks5dgkf1mww6fvysbl5qmfhpgzs52r2-nixos-system-sayu-26.11.20260907.dc5d91f`.
Bootspec, kernel and initrd exist. `modinfo` on the candidate module reports
615.71.09 and vermagic `6.18.49 SMP preempt mod_unload`. All Beyond patch hunks
applied with line offsets only. Closure comparison against the running system
shows only NVIDIA package version changes and a rebuilt initrd (about 21 KiB
smaller); kernel remains identical. `git diff --check` passes and the pre-existing
flake.lock diff is byte-for-byte unchanged. The build emitted initrd library
warnings for several systemd tools; comparison of old/new archive libraries is
recorded separately below. Bootloader installation and actual boot remain untested.

Initrd archive comparison: both running and candidate archives contain 2,097
entries, the same OpenSSL 3.6.3 libcrypto.so.3/libssl.so.3 paths, and no .so.4
libraries. systemd did not change in the closure. The .so.4 warning is therefore
not a dependency regression introduced by this driver update, although it does
not prove all optional initrd tools work. Both initrds are approximately 30 MiB.
