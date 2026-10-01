# WiVRn on sayu and Steam Frame

## Source and development

Local checkout: `/home/s/code/wivrn`, branch `codex/frame-experiment`, starting
at upstream `3e73d98ae22cfdc2cdd6a3a0db7e41a958bba936` (2026-09-30).
The NixOS flake pins that same source for reproducibility. `wivrn-local.nix`
adapts the upstream flake/nixpkgs recipe, enables NVENC, and applies WiVRn's
patches to the Monado revision in `monado-rev`. It excludes `.git`, build
folders and result links from the derivation source.

Build local edits:

```sh
/home/s/nixos-config/scripts/build-wivrn-local.sh
```

Build dependencies and compiler environment:

```sh
cd /home/s/code/wivrn
nix develop /home/s/nixos-config#wivrn \
  --override-input wivrn-src path:/home/s/code/wivrn --no-write-lock-file
```

Build and activate local edits in the service:

```sh
cd /home/s/nixos-config
nix build .#nixosConfigurations.sayu.config.system.build.toplevel \
  --override-input wivrn-src path:/home/s/code/wivrn --no-write-lock-file
sudo nixos-rebuild switch --flake /home/s/nixos-config#sayu \
  --override-input wivrn-src path:/home/s/code/wivrn --no-write-lock-file
```

Stop the streaming session before switching its package. A normal rebuild
without the override returns to the pinned source. Local changes never update
`flake.lock` with these commands. If updating `monado-rev`, update the fixed
Monado fetch hash as well. The initial Frame client is an upstream CI binary,
not a locally compiled ARM64 binary; server changes that alter the network
protocol require rebuilding the matching client too.

## Headset client

SSH target `steamos@192.168.1.16`, hostname `sneed`.
Installed entirely under `/home/steamos/Applications/wivrn`:

- `3e73d98/bin/wivrn` plus the complete `share` directory from upstream CI
  run https://github.com/WiVRn/WiVRn/actions/runs/36683625311,
  artifact `wivrn-frame-client.zip`.
- `runtime/SteamLinuxRuntime_4-arm64` from Valve's
  `steamrt4/images/4.0.20260805.254769/SteamLinuxRuntime_4-arm64.tar.xz`.
  SHA256 `caa4b3bc3aad1cac43d94dbd802a963c13ed63ea1c414f04669ae402af505adf`.
- `start-client`, copied from `scripts/frame-wivrn-client.sh`.

This runtime supplies libopenxr_loader.so.1 and the required OpenSSL 3.4 ABI.
The pre-existing steamrt64 container is x86 and cannot execute natively here.
The headset's OpenXR runtime remains `/opt/steamvr/steamxr_linuxarm64.json`:
WiVRn uses that local runtime for tracking/display, while host games use WiVRn.

Start/stop the client over SSH:

```sh
systemd-run --user --unit=wivrn-frame-client --collect \
  /home/steamos/Applications/wivrn/start-client
systemctl --user stop wivrn-frame-client.service
journalctl --user -u wivrn-frame-client -n 50 --no-pager
```

The wrapper can also be added to Steam as a non-Steam application. The client
config is `~/.config/wivrn/client.json`; initially set to 60 Mbit/s and render
resolution scale 1.0 with a manual `sayu dongle` entry for `10.35.78.26:9757`.
Pair through the headset UI using the server's current PIN. Private keys and
pairing state stay in the user config directories, outside this repository.

## Host session and game launchers

```sh
stop-steamvr              # if host SteamVR is running
start-wivrn-frame
wayvr-wivrn              # after the headset connects
forefront-wivrn
# or vrchat-wivrn
stop-wivrn-frame         # stops WayVR first, then WiVRn
```

Steam remains running for Proton licensing/anti-cheat/media authorization.
The launchers retain the existing GE-Proton-rtsp, prefixes and Steam video token
handling, but select WiVRn's manifest, XRizer and `/run/user/1000/wivrn` socket
directory explicitly. The Forefront 1.0 render-scale patch applies only to the
SteamVR launcher; WiVRn uses the current game setting without changing it.

WiVRn does not manage the global OpenXR/OpenVR selection in this experiment.
The normal Home Manager OpenVR registry must select XRizer. WiVRn and its WayVR
service are manual-start; the original wired Monado/WayVR units remain separate.
WayVR discovers WiVRn's matching libmonado through its manifest. Do not point it
at the standalone Monado library or bypass IPC version checks.

Server codec: NVENC H.264 8-bit. TCP/UDP port 9757 is opened on `enp7s0` and
`wlp116s0f4u1`. Avahi supplies discovery; the manual IPv4 entry avoids interface
selection ambiguity. Dongle path: host `10.35.78.26`, headset `10.35.78.1`.
This is a direct single network path, not a demonstrated multipath implementation.

## Initial verification

Nix build and activation passed. The Frame client initialized native Vulkan on
Adreno 750 and OpenXR through the local headset SteamVR. Pairing succeeded and
the TCP connection uses the dongle addresses. Server logs confirm NVENC H.264
8-bit, approximately 60 Mbit/s across the streams, Frame controller profiles and
PipeWire speaker/microphone creation. WayVR reports the WiVRn runtime and enters
FOCUSED. Subjective image quality, controller behavior, audio and game rendering
are separate checks. User confirmed Forefront renders correctly, as do WiVRn's
statistics window and WayVR overlays. Tracking and the overlay toggle work.
User confirmed doubled controllers/lasers disappear when WiVRn's own interface
is closed with both thumbsticks. The artifact is isolated to that local UI;
Forefront and WayVR render correctly.

WayVR had a separate optional-extension bug: openxr-rs stores unknown extension
names including their trailing NUL byte, but `helpers.rs` checked names without
it. Fixed the Frame controller and MNDX system-button names in the local checkout,
rebuilt WayVR/wayvrctl, restored the OpenVR library RUNPATH, and restarted only
`wayvr-wivrn`. Frame binding rejection disappeared. The two-line patch is saved
as `wayvr-frame-extension-nul.patch`; unrelated WayVR edits are untouched. The
Frame's overlay toggle currently works on double-tap D-pad right with the existing
user bindings, not the old Index A binding.

Forefront audio initially went to the monitor. Moved its running sink input to
`wivrn.sink`; the sink became RUNNING. WiVRn launchers set `PULSE_SINK=wivrn.sink`
and `PULSE_SOURCE=wivrn.source` for future launches without changing global audio
defaults. The headset client also shows an active speaker stream through its
SteamOS audio filter chain. User confirmed headset audio works. Microphone end-to-end operation still needs
testing.

Initial encode size was 704x704 per eye, with eye gaze enabled and the client's
default stream scale of 0.3. The render scale was set to 1.0. Improve stream
resolution/foveation before attributing rough quality entirely to 60 Mbit/s.

First quality trial: client bitrate 150 Mbit/s, `stream_scale=0.5` (50% in
the Foveated encoding slider), render scale unchanged at 1.0, 8-bit H.264.
Saved the previous client config on the headset as
`~/.config/wivrn/client.before-quality-tuning.json`. Reconnected and relaunched
WayVR and Forefront. Server confirms 150,000,000 bit/s and 1088x1088 main
encoders per eye, plus a 1088x544 auxiliary stream. Forefront's new audio input
automatically routes to `wivrn.sink`. User reported improved clarity but freezes
and stutters, also present at the earlier lower bitrate and with WayVR alone.

This pinned client has a fixed bitrate slider, changeable during streaming;
it has no Steam Link-style automatic bitrate tuner. Foveated encoding changes
require disconnection. The encoded dimensions describe the foveated image,
not the game's rendering resolution. Automatic codec selection and automatic
refresh rate selection are separate from adaptive bitrate.

Stutter investigation: UDP client logs show many incomplete video frames
(missing data shards), old shards discarded, and failure to find matching
frames across decoders. Server requests replacement IDR frames repeatedly.
Saved logs under `/home/s/.cache/wivrn-frame/diagnostics/*-150-udp.log`.
These observations point to delivery/reassembly trouble; they do not prove
whether the radio, host driver or client scheduling caused it. Dongle power
saving was enabled, with roughly -56 dBm signal and a 960.7 Mbit/s link rate.

Next comparison uses only WayVR, keeping the user's current saved 157 Mbit/s,
50% foveation, and H.264 settings. Changed the manual dongle server entry's
`tcp_only` to true, restarted the session and verified TCP to `10.35.78.1`
without the streaming UDP socket. Startup also logged exhausted headset V4L2
OUTPUT buffers, continuing thousands of times after startup. User reported
WayVR was not visible/responding. TCP trial failed; restored `tcp_only=false`
and restarted the client/server. This may be an independent early Frame
decoder bug, rather than evidence that TCP cannot carry the stream.
Forefront remains stopped for these trials.

Power-saving experiment: `nmcli device modify` could not apply the setting
live. Temporarily set the dongle connection's Wi-Fi powersave to 2 and
reactivated it. Activation reported failure, but the adapter recovered its
10.35.78.26 address and ping to the headset passed. Restored the profile's
original default (0); `iw` currently reports power saving off for this
connection. Do not treat the temporary state as a durable configuration fix.

At the user's suggestion, added a manual `sayu Wi-Fi` server entry for
192.168.1.26 to the headset client, using UDP with the same 157 Mbit/s and
50% foveation. User connected; verified both UDP and TCP endpoints are
192.168.1.26 to 192.168.1.16, and started only WayVR. The headset reports
5 GHz regular Wi-Fi, -63 dBm and 432.3 Mbit/s link rate. Missing-frame,
decoder synchronization and OUTPUT-buffer exhaustion messages also occur on
this path. User confirmed normal rendering with unchanged freezes. This is
evidence that the failure is not confined to the dongle, without ruling out
network sensitivity.

Next trial: HEVC/H.265 8-bit on regular Wi-Fi, keeping 157 Mbit/s and 50%
foveation. A temporary user-service drop-in at
`/run/user/1000/systemd/user/wivrn.service.d/quality-test.conf` selects
`/home/s/.cache/wivrn-frame/quality-test-hevc.json`, copied from the deployed
config with only the codec changed. No Nix rebuild was needed. Remove that
specific drop-in, run `systemctl --user daemon-reload`, and restart WiVRn
to restore the declarative H.264 config. User reconnected; started WayVR and
confirmed NVENC H.265 8-bit with the same dimensions and bitrate, using the
regular Wi-Fi endpoints. A 40-second log sample still includes incomplete
frames, decoder CAPTURE-buffer errors and failures to synchronize frames,
but no OUTPUT-buffer exhaustion messages in that sample. Subjective HEVC
result: user reports normal rendering but unchanged freezes. Codec change
did not fix it. Prepared another comparison, HEVC over TCP on regular Wi-Fi,
by setting only the Wi-Fi entry's `tcp_only=true` and restarting both ends;
reconnected, verified TCP-only regular Wi-Fi endpoints and started WayVR.
A 40-second sample had no OUTPUT-buffer exhaustion or V4L2 capture errors,
5 frame synchronization warnings and 245 no-shard messages. TCP showed
retransmissions (~0.5% of sent bytes at the sample), so reliable transport
does not establish low jitter. User reports TCP substantially better, with
small remaining jitters/drops and overall quality still below SteamVR.

User suspects jitter/buffering from WiVRn statistics. Source inspection shows
the UDP shard accumulator retains current and next frames, advancing past an
incomplete frame as newer frames arrive. Late delivery can therefore produce
missing-shard logs even without permanent network loss. This is a plausible
mechanism, not a measured attribution of the stutters. Requested which timing
section spikes to distinguish delivery from decode/display delays; user's
impression was rendering/display spikes, or unclear. Avoid interpreting this
as a measured network-only cause.

SteamVR comparison: retained Sep 30 host vrserver logs show actual 10-bit
video (`[HMDVulkan] Is 10 bit? Yes`), Vulkan video encoding and a packed
1024x4096 video session. Its dimensions are not directly comparable with
WiVRn's three foveated streams. Frame vrlink logs show SVLFEC recovery with
packet retries; exact parity settings/algorithm are not established. Prior
SteamVR session reported dual-path streaming, while our WiVRn session uses
one address pair. No measured SteamVR automatic average bitrate is available.

Current WiVRn NVENC uses P4 ultra-low-latency CBR, spatial AQ, no B frames,
intra refresh and a two-frame VBV size. UDP send code explicitly tolerates
short sends as packet loss, and video_encoder ignores send exceptions.
No video packet pacing or FEC implementation was found in the inspected
send/encode code. Upstream issue https://github.com/WiVRn/WiVRn/issues/626
reports UDP corruption/TCP stutter and proposes packet pacing at 500 Mbit/s;
its causal explanation is a reporter's hypothesis, not proof for this host.

Suggested next comparisons: HEVC/TCP on the dongle with unchanged image
settings, then HEVC 10-bit, then render/foveation tuning. For a local patch,
instrument short/failed UDP sends and packet timing before changing behavior;
if bursts are confirmed, try pacing and a tighter encoder VBV. A larger
client reassembly window trades latency for jitter tolerance; selective
packet recovery/FEC is a larger protocol/client change. Keep those trials
separate to preserve interpretable comparisons.

Follow-up trial: HEVC/TCP on the dongle, same 157 Mbit/s, 8-bit and 50%
foveation, verified 10.35.78.26 to 10.35.78.1 TCP-only. User reports better
jitter than regular Wi-Fi. TCP still retransmitted roughly 0.6% of bytes in
one snapshot. Kept this path and prepared HEVC 10-bit by selecting
`quality-test-hevc10.json` in the temporary drop-in and setting the client
bit depth to 10. Reconnected, but logs confirmed fallback to 8-bit due to
reported decoder capabilities. A fresh V4L2 context with HEVC selected exposes
Q10C (Qualcomm compressed 10-bit) but not linear P010. Current WiVRn's decoder
checks for P010 and supports linear NV12/P010 import, so this needs client
format/modifier support rather than forcing 10-bit on the server. Restored
explicit 8-bit settings.

Local diagnostics patch: `wivrn-send-diagnostics.patch` records per-stream
frame payload sizes, send duration, packet attempts and send failures,
aggregated once per second when `WIVRN_VIDEO_SEND_STATS` is set. It does not
change delivery or the protocol. Applied in the local checkout; package
and full NixOS build passed. Diagnostics were not active in the dongle/10-bit
comparisons. Activating the locally built system next, with
`WIVRN_VIDEO_SEND_STATS=1` in the temporary service drop-in, and returning
to the existing HEVC 8-bit config for measurement. No delivery changes yet.

Diagnostics activation passed, system
`/nix/store/fwd6gw6padp7ggjd9bbwq96sksqaf95a-nixos-system-sayu-26.11.20260907.dc5d91f`.
Verified modified server and runtime manifest, then reconnected dongle/TCP
and started WayVR. Saved send windows and socket samples under diagnostics.
In 126 per-stream windows, send failures were zero; 31 windows included sends
over 10 ms, with a maximum of 50.569 ms. Typical frame writes finish below
0.1 ms, handing whole frames to TCP; blocked sends occasionally coincided
with fewer frames sent that second. This is send-queue backpressure, not a
measurement of on-air burst rate or proof of what caused each headset freeze.

Prepared an opt-in TCP pacing patch (`wivrn-tcp-pacing.patch`) using
`SO_MAX_PACING_RATE`, controlled by `WIVRN_TCP_MAX_PACING_MBPS`. Default
behavior is unchanged when unset. Planned first cap: 200 Mbit/s, keeping
the video setting at 157 Mbit/s and encoder buffering unchanged. Package and
full NixOS builds passed; switched to
`/nix/store/wy0b2638lsham8b7fbddnzh5b3x8hvkl-nixos-system-sayu-26.11.20260907.dc5d91f`.
Enabled `WIVRN_TCP_MAX_PACING_MBPS=200` in the temporary drop-in. Socket-cap
verified `pacing_rate 200000000bps/200000000bps`, then started WayVR.
User reports jitter about the same. Paced sample: 120 stream windows, zero
send failures, 39 windows with sends above 10 ms, maximum 38.529 ms; TCP
queue peak 831729 bytes and RTT range 3.008 to 11.07 ms. Compared with the
baseline's 126 windows, 31 above 10 ms, 50.569 ms maximum and 886893 queue
peak, this is not a demonstrated improvement. Removed pacing environment
entry and restarted the session. Patch remains optional; no encoder VBV
changes were made.

Next clarity trial: client `resolution_scale=1.2`, retaining 157 Mbit/s,
50% foveation and HEVC 8-bit/TCP on the dongle. This raises game/compositor
render resolution and resulting foveated stream dimensions together.
Reconnected and started WayVR; main encoders now 1344x1344 per eye, alpha
1344x672, same bitrate. TCP socket confirms no fixed pacing cap. Subjective
assessment: clarity improved a little; jitter unchanged. This is separate from a jitter fix.

The initial fixed 90 Hz setting was later found to mismatch the Frame runtime
(72 Hz); see the timing capture below. The failed refresh-rate request was
relevant, rather than harmless. Missing SlimeVR socket
warnings do not indicate a Frame tracking failure.


## Automated diagnostics and refresh-rate correction

The paired client now autoconnects using its saved **discovered** `sayu` entry,
with `autoconnect=true`. Manual IP entries remain for fallback. Manual entries
are not visible to the upstream autoconnect loop without discovery, and the
server stops advertising while connected; those two facts explained the earlier
failed discovery attempts. No client patch was necessary. Saved pairing keys
remain outside the repository.

```sh
bash /home/s/nixos-config/scripts/reconnect-wivrn-frame.sh
python3 /home/s/nixos-config/scripts/capture-wivrn-frame.py \
  --label dongle-tcp --seconds 30
```

These commands use the existing authenticated SSH master socket
`/run/user/1000/frame-ssh`. The reconnect helper restarts the experimental server
and client, waits for HeadsetConnected, and starts WayVR. Discovery may select
LAN Wi-Fi or the dongle; inspect the printed socket endpoints before comparing
captures. Three autonomous reconnects succeeded. The headset still must be
awake and rendering to obtain display feedback.

The optional `wivrn-frame-timings.patch` exports incoming per-stream feedback
through `WIVRN_FRAME_TIMINGS`. It records encode, send, receive, decode, blit,
display timestamps and presentation counts. It does not change the protocol.
Buffered writes reduce diagnostic overhead; the file is truncated on each new
server session. The capture helper copies the observation window and saves
socket samples, server/client journals and a JSON summary. The summary merges
progress feedback per frame; zero timestamps mean unavailable stages. Display
is the runtime's reported predicted display time, not a photodiode measurement.

Current temporary server drop-in uses:

```ini
Environment=WIVRN_VIDEO_SEND_STATS=1
Environment=WIVRN_FRAME_TIMINGS=/home/s/.cache/wivrn-frame/diagnostics/feedback-current.csv
```

The HEVC test JSON additionally sets `"tcp-only": true` to preserve transport
when discovered service settings replace the saved client's TCP preference.

### Synthetic transport sweep

Scripts `frame-network-probe.py` and `frame-network-sweep.py` generate 157 Mbit/s,
90 Hz synthetic video bursts or paced UDP batches without codecs or XR. Stop
the Frame client first: the receiver uses its port 9757. The probe was copied to
`/home/steamos/Applications/wivrn/network-probe.py`. Results:
`/home/s/.cache/wivrn-frame/diagnostics/network-sweep-157/results.json`.
Each case lasted eight seconds; these are bounded transport tests, not sustained
VR-quality guarantees.

| Path | Transport/pattern | Lost packets | Arrival gap p99 / maximum |
| --- | --- | ---: | ---: |
| Dongle | UDP burst | 85 / 112320 | 11.76 / 12.13 ms |
| Dongle | UDP paced batches | 0 / 112320 | 12.39 / 13.50 ms |
| Dongle | TCP burst | 0 frames / 720 | 14.17 / 16.89 ms |
| LAN Wi-Fi | UDP burst | 718 / 112320 | 12.92 / 13.62 ms |
| LAN Wi-Fi | UDP paced batches | 28 / 112320 | 12.52 / 15.83 ms |
| LAN Wi-Fi | TCP burst | 0 frames / 720 | 21.42 / 37.59 ms |

Frame UDP socket-buffer error counters did not increase. Packet loss is real
and sensitive to burst delivery, but this does not locate it in radio versus
driver. Application UDP pacing differs from the earlier kernel TCP pacing cap.
SteamVR's successful dual-path streaming establishes hardware capability; its
recovery/path-selection behavior could hide losses that WiVRn exposes.

### Active WayVR timing comparison

Initial 30-second capture:
`/home/s/.cache/wivrn-frame/diagnostics/20261001-141612-dongle-tcp-active`.
The server encoded about 90 frames/s while display feedback had a 13.889 ms
cadence (72 Hz). D-Bus advertised only 72 Hz, preferred rate was 90 Hz, and the
Frame rejected requests for 90.00001 Hz. A saved fixed 72 preference still
resulted in 90 Hz requests in that trial; its exact failure mechanism remains
unresolved. Setting client `preferred_refresh_rate=0` (automatic) yielded 72 Hz
server setup and successful runtime requests, without rebuilding either end.

Matched-rate capture:
`/home/s/.cache/wivrn-frame/diagnostics/20261001-142319-dongle-tcp-auto-refresh`.
Both captures used the dongle, TCP, HEVC 8-bit, 157 Mbit/s, render scale 1.2 and
50% foveation. Main-stream results:

| Metric | Fixed 90 Hz | Automatic / 72 Hz |
| --- | ---: | ---: |
| Send-to-arrival median / maximum | 3.13 / 25.18 ms | 1.61 / 3.73 ms |
| Decode median / maximum | 3.04 / 5.17 ms | 1.11 / 2.76 ms |
| Decode-to-blit median | 27.83 ms | 5.38 ms |
| Encode-to-display median / p99 | 70.25 / 78.88 ms | 44.50 / 45.24 ms |
| Repeated presentations | 11 | 12 |
| Longest distinct-frame display gap | 27.78 ms | 27.78 ms |

The matched-rate sample had less queueing but did not eliminate repeated
frames. Later checking send diagnostics showed this sample had almost no video
payload (~0.05 Mbit/s per-stream windows), while the earlier mismatched sample
had ~72 Mbit/s per-eye windows. The numerical latency improvement is therefore
confounded by scene/overlay activity and cannot be attributed solely to refresh
matching. User feedback supports the refresh correction qualitatively. Nine repeated frames in the matched-rate sample recur exactly 256
source frames apart (indices congruent to 252 modulo 256), with additional
irregular repeats. Those frames had normal network arrival (~1.2–2.0 ms) and
decode (~1.1 ms), while the following source frame's encode-begin interval was
~17.1–17.6 ms rather than ~13.9 ms. This points toward scheduling/phase behavior
rather than isolated network or decoder stalls for that periodic component;
it does not yet identify which scheduler or prove the cause. Follow up with
server predicted-present/wake timestamps and client actual render-loop timing.
Do not infer an encoder GOP cause: upstream NVENC intra-refresh period is 100,
not 256.

Current session remains WayVR on dongle HEVC 8-bit/TCP, 157 Mbit/s, scale 1.2,
50% foveation, automatic refresh (72 Hz), fixed TCP pacing cap disabled.
User confirmed matching the input/output refresh rates felt better (correcting
an initially reversed response). The diagnostic scripts and source patches
remain uncommitted.


### Matched 90 Hz follow-up

The Frame's local SteamVR settings API reported:

- `steamvr/preferredRefreshRate`: 90 Hz
- `steamvr/defaultPerAppRefreshRate`: **72 Hz**
- `steamvr/powersaveRefreshRate`: 72 Hz

The compositor logs confirmed it switched from 90 Hz to 72 Hz when WiVRn
started. Set `defaultPerAppRefreshRate=90` through the running runtime's
IVRSettings_003 API, retaining client `preferred_refresh_rate=0`. This changes
the default for native apps on the Frame; the power-save setting is unchanged.
After autonomous reconnection, the server advertised only 90 Hz, the stream
setup requested 90.00001 Hz without rejection, and the local compositor
selected 4320x2160@90.000008 Hz. Rounded floats reflect the display mode timing.
No source rebuild or headset-runtime restart was needed.

Helper `scripts/frame-native-refresh.py` is installed on the Frame at
`/home/steamos/Applications/wivrn/frame-native-refresh.py`. Query/change over
SSH using the existing authenticated master socket:

```sh
ssh -S /run/user/1000/frame-ssh -o BatchMode=yes steamos@192.168.1.16 \
  'python3 ~/Applications/wivrn/frame-native-refresh.py'
# Set --set 90, or --set 72 to restore the original native-app default.
```

Reconnect WiVRn after changing the setting. The helper uses the function table
published in Valve's official `openvr_capi.h`:
https://github.com/ValveSoftware/openvr/blob/master/headers/openvr_capi.h.
It checks initialization, interface acquisition, writes and readback.

The first matched-90 capture contained a headset visibility transition and
only ~4.6 seconds of displayed frames; it verifies an 11.111 ms display cadence
but is not comparable to the full active 72 Hz quality capture. A fresh active
30-second capture follows. Current session is still dongle HEVC 8-bit/TCP,
157 Mbit/s, scale 1.2 and 50% foveation, now matched at 90 Hz.


User confirmed matched 90 Hz feels better than matched 72 Hz. The second
capture, `/home/s/.cache/wivrn-frame/diagnostics/20261001-143114-dongle-tcp-matched-90-active`,
contained real video payload (~63 Mbit/s median stream-window rate). Main-stream
feedback: 2618 frames, 2492 decoded, 2322 displayed, 439 repeat presentations;
median display gap 11.111 ms. Send-to-arrival median 3.819 ms, p95 119.286 ms,
maximum 217.058 ms; encode-to-display median 65.296 ms, maximum 324.287 ms.
These are substantial delivery stalls at actual payload load and keep network
queueing/retransmission relevant. The low-payload 72 Hz capture is not a valid
matched-content comparison. Retain matched 90 Hz as the user-preferred setting;
future jitter tests must keep overlay content/activity and observed payload
comparable, not just nominal bitrate/resolution. Both endpoints remain on the
dongle, with automatic client refresh and Frame native-app default 90 Hz.


### UDP retry at matched 90 Hz

Set temporary server JSON `"tcp-only": false` and reconnected automatically.
Confirmed both UDP and control TCP use dongle endpoints 10.35.78.26/10.35.78.1;
AvailableRefreshRates stayed 90 Hz. HEVC 8-bit, 157 Mbit/s, scale 1.2 and 50%
foveation unchanged. First window included a visibility transition, so captured
a second window with substantial video payload (~57 Mbit/s median per-stream
window, versus ~63 in the preceding active TCP capture).

Active UDP artifact:
`/home/s/.cache/wivrn-frame/diagnostics/20261001-143357-dongle-udp-matched-90-active`.
Main stream: 2689 feedback frames, 1986 decoded, 1873 displayed, 524 repeated
presentations. Send-to-arrival p95 12.501 ms / p99 33.641 ms / maximum 99.448 ms;
encode-to-display median 69.715 ms / p99 144.235 ms. Client logged 254
V4L2_BUF_FLAG_ERROR messages and 505 failures to synchronize a common frame
across decoders. A 4-second display-feedback gap requires visibility-state
correlation; do not call it a transport freeze from this statistic alone.
Missing decode feedback alone is not a literal packet-loss counter.

UDP reduced delivery-delay tails compared with the loaded TCP sample, but
matched refresh did not cure damaged/missing video or decoder synchronization.
Restored `"tcp-only": true` and reconnected at matched 90 Hz. User's UDP
assessment was pending at restoration; objective failures motivated returning
to the previous working transport.

Next useful UDP patch experiment: pace batches at the application level,
following the synthetic loss reduction. Instrument partial `sendmmsg` results
first: upstream UDP send_many_raw explicitly ignores positive short sends and
reports the full requested payload, so current failure=0 diagnostics cannot
exclude sender-side packet omissions. This is a candidate to measure, not an
established cause. Kernel TCP pacing was a separate experiment and its neutral
result does not disprove a UDP batch pacer.


## Upstream pacing audit (2026-10-01)

Current upstream master `1b0d13c431debeed15870ebaf6d94b60f1d1ebfe` is two
translation-only commits ahead of our pinned checkout. No newer send-path fix
is missing from this pin.

- Shared compositor pacer learns a 99.5th-percentile present-to-decode budget,
  adds `WIVRN_CLIENT_MARGIN_MS` (default 1 ms), and adjusts phase from client
  feedback. This schedules whole frames; it does not space outgoing datagrams.
  It runs on the Frame path as well as Quest.
- NVENC CBR/two-frame VBV tuning from merged PR #652 and improved IDR handling
  from merged PR #653 are already ancestors of our checkout. No extra switch
  is needed for Frame. Recovery detects missing frames before decoder submission;
  successful packet assembly followed by decoder failure is a different case.
- Tracking packet batching (`00a45626`, `c370d194`) is also already included
  and not Android-only. It reduces return-path syscall/preamble overhead.
- Upstream issue #626 explicitly requests network traffic shaping; maintainer
  says a demonstrated prototype could be considered but no implementation is
  supplied there. No current open PR adds a network packet pacer.
- `feat/multiple-udp` exists at `27fc4a1fddee6acf56e987b478b07ada44b99102`
  (2025-12-04), five commits beyond its common base and 758 behind our pin.
  Issue #609 reports worse loss/reordering in the prototype. It is multiple
  flows, not a packet pacer or a working dual-radio Frame mode. Issue #1114
  mentions reviving this work for Frame dual-channel support.
- Application pacer PR #1096 was withdrawn: its author reported reduced
  scheduled-frame drops but persistent stutter and a quality regression. It
  is not an accepted send pacing fix.
- Android acquires WIFI_MODE_FULL_LOW_LATENCY (or HIGH_PERF on old Android);
  native Linux wifi_lock is a no-op. Live Frame checks showed wlanap power save
  off, wlan0 power save on. These are platform power/network controls rather
  than packet pacing. Power-save-off does not establish equivalence to the
  Android lock or Valve's complete streaming policy.

Correction to the earlier partial-send recommendation: video_encoder::SendData
calls send_stream separately for each shard; typed_socket::send dispatches to
UDP::send_raw, which uses writev. UDP::send_many_raw/sendmmsg is used for batched
tracking traffic. Positive short-send instrumentation there would not directly
measure video loss. The next useful instrumentation is video send_raw and
receiver shard completeness, followed by an optional shared video datagram
pacer. `WIVRN_TCP_MAX_PACING_MBPS` is our local patch, not an upstream feature.

Primary references:
https://github.com/WiVRn/WiVRn/issues/626
https://github.com/WiVRn/WiVRn/issues/139
https://github.com/WiVRn/WiVRn/issues/609
https://github.com/WiVRn/WiVRn/issues/1114
https://github.com/WiVRn/WiVRn/pull/652
https://github.com/WiVRn/WiVRn/pull/653
https://github.com/WiVRn/WiVRn/pull/1096

Audit was read-only for runtime settings; matched-90 TCP session remains active.


## VRChat motion/audio investigation and Frame Wi-Fi power saving

User reports simultaneous audio/video glitches during motion, and apparent
alternating tracking positions in the desktop mirror. User then confirmed the
mirror becomes normal while the headset is actually worn/tracking. Do not treat
the unworn mirror behavior as evidence of active-stream pose corruption.

Code review confirms server speaker audio uses send_control (the TCP control
socket). With TCP-only streaming, video shares that same byte stream. TCP loss
recovery can therefore delay both audio and video, consistent with the report;
this does not establish a separate PipeWire bug. The active VRChat capture
logged zero V4L2 decoder buffer errors. Encode p99 ~4 ms and decode p99 ~5.6 ms
were below the 11.1 ms frame period. TCP receive windows remained large and
rwnd_limited stayed effectively zero; no evidence of receiver-window pressure.
CPU snapshot showed ~81% idle on Frame. Native WiVRn and local SteamVR main
threads had the same CPU mask (0–4); no obvious WiVRn-only CPU affinity mismatch.

The Frame has **one phy#0** with both wlanap (6 GHz / 160 MHz dongle AP) and
wlan0 (5 GHz / 80 MHz LAN station). wlanap power saving was off, wlan0 was on.
Host dongle power saving was also verified off with nixpkgs iw. Linux client's
wifi_lock is a no-op, unlike Android's low-latency lock. Tested **Frame wlan0**
power saving off while preserving the AP, SSH, VRChat, refresh rate, codec and
bitrate. No app/server reconnect or source rebuild.

```sh
# Run on Frame; reversible live setting, original wlan0 value was on.
sudo iw dev wlan0 set power_save off
iw dev wlan0 get power_save
# Restore: sudo iw dev wlan0 set power_save on
```

Frame's NetworkManager connection is `porchetta`, powersave property `default`.
The live iw change may be overwritten on reconnection/reboot; no persistent
profile change yet.

Captured under `/home/s/.cache/wivrn-frame/diagnostics`:

| Capture | Main video Mbit/s median | TCP retransmitted bytes | Network p99 / max | Repeated presentations |
| --- | ---: | ---: | ---: | ---: |
| `20261001-145912-vrchat-active-shared-stalls` (initial on) | 64.03 | 1227120 | 93.431 / 137.626 ms | 426 |
| powersave-off first window (see capture JSON) | 68.40 | 169606 | 6.390 / 12.371 ms | 104 |
| `20261001-150254-vrchat-frame-wifi-powersave-on-control` | 68.56 | 426239 | 13.522 / 35.244 ms | 248 |

The initial window includes low-payload/inactive portions and a stale frame
across a visibility transition, so its extreme encode-to-display maximum is
not a valid active-motion latency measurement. The later off/on windows have
similar actual payload and support a power-management effect; short captures
still have wireless variance. A final off repetition follows before drawing a
stronger conclusion. Mechanism (shared-radio firmware power/coexistence behavior)
is an inference, not established from packet captures.

A parallel 30-second small-ICMP probe had 300/300 replies, 3.05 ms mean and
9.31 ms maximum, showing small traffic remains responsive even when bulk TCP
has retransmissions. This does not rule out bulk traffic-specific radio loss.
Current runtime remains Frame wlan0 power save **off**, dongle TCP/HEVC 8-bit,
157 Mbit/s, render scale 1.2, matched 90 Hz. No packet pacer was added.


Final off repetition:
`20261001-150411-vrchat-frame-wifi-powersave-off-repeat`.
Main payload median 69.02 Mbit/s, 2757 feedback frames / 2754 decoded / 2579
displayed / 175 repeated presentations. Network p99 11.509 ms, max 19.624 ms;
encode-to-display median 62.305 ms, p99 73.368 ms. Retransmitted bytes increased
by 865521, **higher than the on control**, so do not claim a reproducible
retransmission reduction from these short windows. Both off samples had fewer
repeated presentations and lower network-tail maxima than the on control;
wireless variance and adaptive stream timing still confound causality. User
motion/audio assessment pending. Leave the reversible live setting off, without
making a durable connection-profile change until benefit is clearer.


### Dongle-only motion test

User clarified the preceding VRChat scene was static, so its timing results
need a separate movement test. Established an authenticated SSH master over the
AP at `steamos@10.35.78.1`, socket `/run/user/1000/frame-dongle-ssh`, verifying
hostname sneed and using HostKeyAlias=192.168.1.16 for the known host identity.
Then ran `sudo nmcli device disconnect wlan0` on Frame. Verified wlan0
STATE=30/disconnected, no LAN association; wlanap/AP remains enabled, power
saving off. Existing WiVRn TCP socket and client PID survived unchanged.
VRChat/server/client were not restarted.

Regular Wi-Fi remains disconnected for this experiment. To restore it, run
`sudo nmcli connection up porchetta ifname wlan0` on Frame through dongle SSH.
This may restore wlan0's default power-saving policy as well.

For subsequent helpers while LAN is disconnected:

```sh
FRAME_SSH_TARGET=steamos@10.35.78.1 \
FRAME_SSH_CONTROL=/run/user/1000/frame-dongle-ssh \
  bash /home/s/nixos-config/scripts/reconnect-wivrn-frame.sh
python3 /home/s/nixos-config/scripts/capture-wivrn-frame.py \
  --label dongle-only --seconds 45 --ssh steamos@10.35.78.1 \
  --ssh-control /run/user/1000/frame-dongle-ssh
```

Motion capture label `vrchat-dongle-only-motion`; saved capture JSON under the
existing diagnostics directory. User assessment pending.


User reported dongle-only motion was unchanged or worse. Active motion artifact:
`20261001-151643-vrchat-dongle-only-motion`. Main stream 3648 feedback frames,
3479 decoded, 2589 displayed, 1561 repeated presentations; network p99 346.956
ms/max 559.039 ms; TCP retransmissions +1844519 bytes. Decode p99 18.58 ms,
encode-to-display p99 429.727 ms. Disconnecting wlan0 did not remove severe
stalls. Static-scene off/on power-save tests should not be presented as a
motion-quality fix. Restored LAN connection porchetta after this negative
trial, keeping the prior temporary wlan0 power-save-off setting. Native-app
90 Hz and dongle TCP streaming remain unchanged. Both SSH master sockets are
available while authenticated; no WiVRn/game restart during this experiment.


## Paired endpoint captures after Astra review (2026-10-01)

Astra recommended measuring delivery and comparing SteamVR's actual paths before
transport patches. Retained SteamVR logs show primary path changing from dongle
to LAN, FEC initialization and timed retry; their exact recovery behavior remains
unknown. Thus smooth dual-path SteamVR is not yet a single-path control.

Captured host dongle and Frame wlanap using tcpdump, 192-byte snapshot, 8 MiB
capture buffers, filter restricted to the peer address (includes TCP, UDP and IP
fragments). SSH management went over LAN. Both 40-second synchronized trials
reported zero packets dropped by capture kernels. Capture/drop counts:

- TCP: host 598273 captured / 598883 received by filter; Frame 114454 / 114985.
- UDP: host 620225 / 620590; Frame 610465 / 611346.

Received-by-filter minus captured can include unread packets at stop; interior
windows exclude one second from each end. TCP receiver GRO aggregates up to
65160 payload bytes per captured packet; host TCP payload max 1448. Do not infer
loss from raw packet-count differences or treat GRO packets as MTU violations.

Artifacts under ~/.cache/wivrn-frame/diagnostics:

- paired-tcp-20261001: initial authentication-delayed trial, only ~5.75 s usable
  interior overlap. Not the main comparison.
- paired-tcp-sync-20261001: ~37.49 s interior overlap, PCAPs, TCP TSVs,
  paired-summary.json and retry-arrivals.json. Feedback capture
  20261001-154130-paired-tcp-synchronized.
- paired-udp-sync-20261001: ~37.49 s interior overlap, PCAPs, TCP/UDP TSVs,
  paired-summary.json, missing-datagram lists and loss-clusters.json. Feedback
  20261001-154608-paired-udp-synchronized.

TCP: 628 host retransmission flags in interior. 613 repeated starting sequence
ranges could be checked against receiver ranges including GRO; all first appeared
at Frame after their retry (maximum original-send-to-first-receive ~21.21 ms).
Matched forward data p99 ~9.57 ms. Host socket sampling nevertheless found up to
1630448 unsent bytes, cwnd as low as 40 segments. WiVRn send-to-arrival p99 87.11
ms/max 171.978 ms. This supports loss/recovery and congestion-window reduction
accumulating a substantial queue before the host capture point, without yet
locating initial loss. Application timing is not pure wire transit.

UDP: 2778/496171 host-to-Frame datagrams absent from Frame capture (0.5599%);
0/45592 reverse datagrams absent. Keys use source, UDP length and 32 captured
payload-prefix bytes (including encrypted per-packet IV); no duplicate sender
keys. Matched forward capture delay p99 10.356 ms/max 30.465 ms. Max IP length
1483, no captured UDP fragmentation. Frame UDP RcvbufErrors stayed 519 from
before trials through after UDP; no added socket-buffer errors. Frame interface
RX drop/error/fifo/missed counters zero, though driver reporting can be incomplete.
Losses formed 107 time clusters with <=2 ms inter-loss gap; largest cluster 84
packets across ~0.174 ms of host capture timestamps. Most missing packets had IP
length 1451. These timestamps describe driver enqueue observation, not radio
transmission timing. Loss is localized between capture points, not proven on-air.
WiVRn UDP feedback send-to-arrival p99 16.745 ms/max 46.73 ms, showing shorter
latency tails but unrecovered delivery loss.

Important capture confound: tcpdump default enabled promiscuous mode on the host
(and requested it on Frame). Repeat with -p before treating the precise loss rate
as baseline; capture/monitoring itself can perturb driver scheduling. Existing
no-capture synthetic loss already suggests loss is not wholly a capture artifact.
Clock offsets estimated with matched bidirectional TCP data; ~0.4 ms bound width
in TCP trial, ~0.26 ms in UDP trial. No physical on-air or userspace-consumption
timestamps were measured.

VRChat exit at 15:42:39 was intentional: user selected exit through WiVRn,
server issued exit requests at 15:42:29 then forced XR session loss ten seconds
later. Server and Frame client continued, no coredump found. UDP required restart
and relaunch; bitrate/codec/render scale/90 Hz retained, endpoints verified dongle.

After user closed VRChat, restored tcp-only=true and ran the reconnect helper;
WayVR returned on the dongle. VRChat was left closed. No source transport patch,
NixOS rebuild, commit or push performed during these captures.


## Non-promiscuous repeat and first SteamVR comparison (2026-10-01)

sudoplz now works via the configured askpass and its approval dialog; no secret
was read into task output or persisted in capture helpers.

Non-promiscuous UDP repeat: paired-udp-nopromisc-20261001 (~37.38 s interior),
WayVR alone, dongle, HEVC8/TCP-disabled/157M/1.2 scale/90 Hz. 7762/417091 forward
datagrams absent (1.861%), zero/28212 reverse absent. No capture-kernel drops:
host525680 captured/526094 filter; Frame491632/491684. Max IP1483, no UDP
fragmentation. Different scene/motion/load prevents an A/B percentage claim, but
loss persists without promiscuous capture. Firmware stats available on Frame:
ath12k_pci driver, device_dp_stats and fw_stats directory. Hostapd configuration
at /var/run/softap_hostapd.conf: recorded only explicit radio/QoS field whitelist,
never password/key fields. Baseline saved frame-ap-driver-state.txt.

First SteamVR capture paired-steamvr-20261001 is INVALID as a smooth-stream
control: Frame displayed dark green while tracking continued. PCAPs still useful
as failed-render diagnostics. Both endpoints captured all interfaces with -p,
192-byte snapshots and8MiB capture buffer, peer-filtered excludingSSH. Host114676
captured/114892 filter, Frame114659/114877; zero kernel drops both.
Host source UDP10400 flows each ~6.215Mbps to dongle and LAN. Exactly28460
outgoing datagrams per path;28430 have matching length/64-byte payload prefix
acrosspaths. Indicates extensive duplication in this failed, low-video-payload
session; do not extrapolate its video routing to a normal loaded session.
DSCP0 on capturedSteamVRIPv4 flows. WhitelistedAPconfig is identical to WiVRn
baseline (US,6GHzchannel37,160MHz observed, WMMenabled); hidden/runtimefirmware
policychanges remainpossible. Valve logs showFECHandleChange32 andtimedretry,
unknown exactcodingparameters.

HostSteamVRupdated from yesterday'sworking2.18.1 to2.18.2. Yesterday driver log
requested90Hz; firstcurrentrun requested144Hz. Setsteamvr/preferredRefreshRate90
using IVRSettings_003 API, extendingframe-native-refresh.py with --library and
--key options. Reconnect confirmedFrame90 butgreenpersisted. Desktopcompositor
loggedWaitForAcquiretimeouts. StoppedtestVRChat and restartedSteamVR cleanly90;
waitingforFrame reconnection to validate background beforeanothercapture.
Configuredcompositorcap_sys_nice capability is present. No rollback/reboot or
transportpatch has been performed.

90 Hz preference readback and Frame request/readback confirmed, but green persists
after reconnect, clean host SteamVR restart and Frame steamvr.service restart.
Frame Steam client also restarted automatically with its local VR runtime; both
returned active and streaming reconnected. No headset OS reboot. Working SteamVR
comparison still blocked; do not label low-rate green-stream capture as smooth.

### Exact SteamVR version comparison prepared

The authenticated desktop Steam client downloaded Linux depot 250823 manifest
2808668121719172829 and common depot 250824 manifest 8907040478893760745.
An isolated runtime was assembled at
`/home/s/.cache/wivrn-frame/steamvr-version-test/steamvr-2.18.1` by reflinking the
installed runtime and overlaying those two depots. The installed beta remains
unchanged. The copied compositor launcher has `cap_sys_nice=eip`.

The transient `steamvr-version-test.service` launches the source session script
with `STEAMVR_RUNTIME_DIR` selecting this directory. Startup logs confirm
2.18.1, the Frame connection at 90 Hz, and 10-bit encoder capability enabled.
The game launcher accepts the same runtime environment variable so a subsequent
VRChat test can use the matching libraries and OpenXR manifest. Visual outcome
is pending the headset check. Startup evidence is saved in the version-test
directory.

The user confirmed that the SteamVR background/grid rendered immediately with
2.18.1 and then confirmed VRChat rendered as well. This strongly implicates the
2.18.2 host beta update in the dark-green failure; it is not proof of the exact
encoder/compositor defect. A new paired capture was started only after that
visual confirmation, at
`/home/s/.cache/wivrn-frame/diagnostics/paired-steamvr-2181-20261001`.

### Working SteamVR 2.18.1 paired capture

The user confirmed movement and audio were smooth as before during the capture.
Both captures used non-promiscuous `any`, a 192-byte snapshot, and 8 MiB capture
buffers. Host: 923245 captured, 923968 received by filter, zero kernel drops.
Frame: 902137 captured, 902856 received by filter, zero kernel drops.

Host UDP/10400 traffic averaged 92.443 Mbit/s on the dongle and 92.437 Mbit/s on
the LAN path. All observed IPv4 DSCP values were zero. Of 441179 dongle host
datagrams, 441154 had matching length and first 64 payload bytes on the LAN
path. This is strong evidence of duplicated traffic in the working loaded
stream, although it is not a full protocol decode.

Matching shared unique payload-prefix keys over a 37.955-second host interior
window (one-second margins) found 422229 keys, with 18 repeated sender keys per
path. At the Frame capture point, 5670 dongle keys were absent (1.34%) and 13855
LAN keys were absent (3.28%). Only 154 shared keys were absent on both paths
(0.0365%). The other path supplied 5516 of the dongle misses and 13701 of the
LAN misses. These are kernel capture observations, not proof of on-air loss or
application decode loss. FEC semantics remain unresolved. Nevertheless, the
working smooth session has measurable single-path losses, and duplication
substantially reduces the combined missing set. This weakens the assumption
that smooth SteamVR implies a loss-free dongle/driver path.

Artifacts: `traffic-summary.json`, `redundancy-summary.json`, paired PCAPs and
UDP TSVs in `paired-steamvr-2181-20261001`. Analysis scripts are saved in
`/home/s/.cache/wivrn-frame/steamvr-version-test/`. The isolated old runtime and
VRChat remain running, with the installed beta untouched.

### SteamVR dongle-only test

With 2.18.1 and VRChat still running, established SSH over 10.35.78.1, then
disconnected only Frame `wlan0` using `sudo nmcli device disconnect wlan0`.
Frame `wlanap` remained up. A paired 40-second non-promiscuous capture at
`paired-steamvr-single-20261001` confirmed UDP/10400 streaming only over the
dongle. Host: 313297 captured / 313795 filtered; Frame: 302668 / 302804.
Both reported zero kernel capture drops.

Traffic averaged 60.831 Mbit/s outbound at host, 58.544 Mbit/s at Frame.
Compared with the earlier 92 Mbit/s per path, automatic bitrate/content changed,
so this is not a fixed-bitrate A/B. Over a 37.957-second host interior window,
3875 of 273929 unique length/64-byte payload-prefix keys were absent at Frame
(1.4146%); 16 sender repeated keys. Capture absence does not establish on-air
loss. DSCP remained zero. During the approximate 40-second log window, Frame
reported 62 substantive retries, 8 entirely dropped frames, 2 unrecoverable
errors, 5 late metadata reports, and no explicit FEC decode-fail messages.
Subjective headset outcome is pending.

FEC setting investigation: the shipped driver defaults and binary strings
contain `forceBaselineVideoFEC=false`, `enableTimedRetry=1`, and
`allowMultipleLinks=true`. No explicit FEC-disable setting was found in the
inspected defaults/schema/host and client binary strings. Baseline FEC is not
proven to mean no FEC; timed retry concerns retransmission, not disabling
parity coding. Both remain unchanged for this single-path test.

The user subsequently reported that dongle-only video was clearly worse than
dual-path: stutters and chunky/blocky quality adjustments, but fewer frequent
small hitches than WiVRn. This supports residual recovery benefits but does not
isolate FEC from retransmission, bitrate adaptation, or buffering.

### Regular Wi-Fi-only comparison prepared

Reconnected Frame `porchetta` / `wlan0`, then disconnected host
`wlp116s0f4u1` with `nmcli device disconnect`, preserving Frame AP configuration.
Frame LAN SSH remains available at 192.168.1.16. Before capture, Wi-Fi signal
was -67 dBm, 5 GHz channel 161, RX negotiated 432.3 Mbit/s (80 MHz), TX
137.6 Mbit/s (40 MHz). No encoder/recovery settings changed. Captures prepared
at `paired-steamvr-lan-20261001`; subjective outcome pending.

The initial `paired-steamvr-lan-20261001` capture was invalid as a Wi-Fi-only
comparison: Steam reactivated the dongle after a plain NM disconnect. The user
noticed both UIs still indicated multipath. Live host state and the capture
confirmed both paths (approximately 129 Mbit/s each). Retained with an
`INVALID_WIFI_ONLY.txt` marker, and excluded from single-path conclusions.

The corrected test temporarily used `nmcli device set wlp116s0f4u1 managed no`.
The dongle was verified unmanaged/down before and during capture.
`paired-steamvr-lanonly-20261001` confirms only LAN UDP/10400 streaming.
Host: 559383 captured / 560264 filtered; Frame: 554326 / 555199. Zero kernel
capture drops at both ends. Forward traffic averaged 112.911 Mbit/s at host.
Across a 37.921-second host interior, 7412 of 509342 unique length/64-byte
payload-prefix keys were absent at Frame (1.4552%), with 16 sender repeats.
This is comparable observed absence percentage to the dongle-only trial but
at a different automatic stream rate, so it is not a fixed-load A/B.

The approximate 40-second Frame log window had 101 substantive retries, zero
entirely dropped-frame messages, one unrecoverable error, one late metadata
report, and no explicit FEC decode-fail message. Subjective result pending.
After capture, restored host dongle `managed yes` and its connection UUID;
NetworkManager confirms it connected. Frame regular Wi-Fi stays connected,
returning to the dual-path baseline. No encoder/recovery settings were changed.

### Dongle extension placement trial blocked by USB instability

A passive extension initially enumerated at USB 2 / 480 Mbit/s on a different
port. Moving it to the prior USB 3 port briefly negotiated SuperSpeed, followed
by a scan timeout, USB reset, descriptor read timeouts (-110), and a port power
cycle. After reseating, the dongle briefly appeared on 8-10 at USB 2 speed,
then failed repeated efuse reads and chip setup; driver probe returned -16 and
USB disconnected. Current inventory has no dongle/network interface. No
streaming capture was run with this extension, and these failures do not
establish that earlier direct-USB streaming losses were USB faults. Placement
testing is deferred until a stable physical connection is available. Kernel
evidence is saved under `diagnostics/dongle-extension-20261001`.

### Session checkpoint and next experiment

The shorter extender stayed connected during a 30-second observation with no
new resets, but `/sys/bus/usb/devices/5-1/speed` reported 480: USB 2, not USB 3.
No streaming placement comparison was performed through it. At checkpoint,
WiVRn, WayVR-WiVRn, isolated SteamVR and its VRChat transient services are all
inactive. Host dongle is connected and Frame regular Wi-Fi was restored.

A new tracker project lives at `/home/s/org/projects/wivrn-steam-frame.md`.
Research found actual adaptive interleaved XOR FEC and packet pacing in the
third-party [WiVRn NX atlas-live fork](https://github.com/nerdrx/wivrn-nx/blob/atlas-live/README.md):
`common/fec.h`, server encoder integration and client shard reconstruction were
inspected. This fork has substantial additional changes and is not yet built or
verified on this Frame. Its [multipath implementation](https://github.com/nerdrx/wivrn-nx/blob/atlas-live/docs/multipath.md)
uses primary UDP and a secondary TCP path, originally Wi-Fi plus USB tunneling;
failover and striping are not the same as Valve's observed duplicate wireless
datagrams. Adaptation would be needed for the two wireless paths here.

[Upstream issue #626](https://github.com/WiVRn/WiVRn/issues/626) remains open:
a maintainer would consider a tested packet pacing prototype, but noted latency
and network-dependent tuning. [Issue #609](https://github.com/WiVRn/WiVRn/issues/609)
was closed without a clear benefit; its `feat/multiple-udp` branch remains but
was 761 commits behind master at inspection. It distributes traffic across
multiple sockets rather than implementing independent-path redundancy.
[PR #26](https://github.com/WiVRn/WiVRn/pull/26) removed a Reed-Solomon dependency
in 2023; inspected prior code showed an unused include, so this is not evidence
of a formerly working FEC transport.

Next session: review/isolate NX transport changes, build a separate normal-HEVC
client/server, and compare baseline, pacing only, FEC only and both at fixed
bitrate/resolution/90 Hz. Use recovered shards, incomplete frames, display gaps
and audio glitches as outcomes. Hardware/driver tuning is not proven exhausted.
The existing diagnostics patches are optional; they are applied in the local
WiVRn source override, not automatically to the pinned upstream package.
