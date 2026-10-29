"""Launch a game through Proton and an explicit XR runtime, bypassing saved Steam options."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys


def fix_forefront_render_scale(prefix, proton):
    """Update the existing PlayerPrefs value only while its Wine server is idle."""
    registry = prefix / "pfx/user.reg"
    data = registry.read_bytes()
    pattern = rb'(?m)^"ResolutionScale_h998708403"=hex\(4\):([^\r\n]+)'
    matches = list(re.finditer(pattern, data))
    if len(matches) != 1:
        sys.exit("Cannot locate Forefront's render scale; launch it normally once and set its in-game render scale to 1.0.")
    old_value = matches[0].group(1).decode("ascii")
    desired = struct.pack("<d", 1.0).hex(",")
    if old_value == desired:
        return
    # Writing user.reg while wineserver owns the registry can be overwritten.
    # Wait for this prefix only; do not stop another game's Wine processes.
    try:
        subprocess.run([
            "steam-run", str(proton.parent / "files/bin/wineserver"), "-w",
        ], env=dict(os.environ, WINEPREFIX=str(prefix / "pfx")),
            timeout=5, check=True, stdout=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        sys.exit("Close Forefront completely before applying its Frame render-scale workaround.")
    # Wine can flush the old setting as it exits, so re-read after waiting.
    data = registry.read_bytes()
    matches = list(re.finditer(pattern, data))
    if len(matches) != 1:
        sys.exit("Forefront's render-scale registry value changed unexpectedly; no edit made.")
    state = Path.home() / ".local/state/forefront-frame"
    state.mkdir(parents=True, exist_ok=True)
    backup = state / "render-scale-before-workaround.json"
    if not backup.exists():
        backup.write_text(json.dumps({
            "registry": str(registry),
            "original_line": matches[0].group(0).decode("ascii"),
        }, indent=2) + "\n")
    replacement = b'"ResolutionScale_h998708403"=hex(4):' + desired.encode("ascii")
    registry.write_bytes(re.sub(pattern, lambda _: replacement, data))
    print("Forefront Frame workaround: in-game render scale set to 1.0.", flush=True)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--game", choices=("vrchat", "forefront"), default="vrchat")
parser.add_argument("--dry-run", action="store_true")
parser.add_argument("--backend", choices=("steamvr", "wivrn"), default="steamvr")
parser.add_argument("--xr-runtime", type=Path)
parser.add_argument("--openvr-runtime", type=Path)
args, game_args = parser.parse_known_args()
appid, title, executable, default_args = {
    "vrchat": ("438100", "VRChat", "launch.exe", []),
    "forefront": ("2981220", "Forefront", "Forefront.exe", ["-controlscheme", "openxr"]),
}[args.game]
steam = Path.home() / ".local/share/Steam"
game = steam / "steamapps/common" / title
runtime = Path(os.environ.get("STEAMVR_RUNTIME_DIR", str(steam / "steamapps/common/SteamVR"))).expanduser().resolve()
if args.backend == "wivrn":
    if args.xr_runtime is None or args.openvr_runtime is None:
        parser.error("WiVRn requires --xr-runtime and --openvr-runtime")
    runtime = args.openvr_runtime
    xr_manifest = args.xr_runtime
else:
    xr_manifest = runtime / "steamxr_linux64.json"
env = os.environ.copy()
steam_env = None
for proc in Path("/proc").iterdir():
    try:
        if proc.stat().st_uid == os.getuid() and (proc / "comm").read_text().strip() == "steam":
            steam_env = dict(x.decode().split("=", 1) for x in (proc / "environ").read_bytes().split(b"\0") if b"=" in x)
            steam_pid = proc.name
            break
    except (OSError, UnicodeError):
        pass
if steam_env is None:
    sys.exit(f"Start Steam before launching {title}.")
# Steam sets this codec authorization on child processes, not on its own
# environment. External Proton launches need it too. Read it from a helper
# belonging to this Steam instance, without saving or displaying the token.
video_token = steam_env.get("STEAMVIDEOTOKEN")
if not video_token:
    for helper in Path("/proc").iterdir():
        try:
            if helper.stat().st_uid != os.getuid() or (helper / "exe").resolve() != steam / "ubuntu12_64/steamwebhelper":
                continue
            helper_env = dict(x.decode().split("=", 1) for x in (helper / "environ").read_bytes().split(b"\0") if b"=" in x)
            token = helper_env.get("STEAMVIDEOTOKEN", "")
            if token.startswith(steam_pid + "\n"):
                video_token = token
                break
        except (OSError, UnicodeError):
            pass
if video_token:
    env["STEAMVIDEOTOKEN"] = video_token
else:
    print("Warning: Steam has not supplied a video token; H.264 playback may fail. Run steam steam://unlockh264/ and retry.", file=sys.stderr)
tools = steam_env.get("STEAM_EXTRA_COMPAT_TOOLS_PATHS", "").split(":")
proton = None
for tool in tools:
    if not tool:
        continue
    manifest = Path(tool) / "compatibilitytool.vdf"
    if manifest.is_file() and re.search(r'"GE-Proton-rtsp"\s*(?://[^\n]*)?\s*\{', manifest.read_text()):
        proton = Path(tool) / "proton"
        break
if proton is None:
    sys.exit("Cannot find the configured GE-Proton-rtsp tool in the running Steam environment.")
entry = steam / "steamapps/common/SteamLinuxRuntime_4/_v2-entry-point"
for path in (proton, entry, game / executable, xr_manifest):
    if not path.is_file():
        sys.exit(f"Missing required file: {path}")
prefix = steam / "steamapps/compatdata" / appid
if not (prefix / "pfx").is_dir():
    sys.exit(f"Missing existing {title} Proton prefix; launch/install {title} normally first.")
for key in list(env):
    if key.startswith("XRIZER_") or key in ("XR_RUNTIME_JSON", "VR_OVERRIDE", "VR_PATHREG_OVERRIDE", "OXR_PARALLEL_VIEWS", "RUST_LOG", "PRESSURE_VESSEL_FILESYSTEMS_RW"):
        env.pop(key)
# Retain Steam's anti-cheat runtime paths without importing its runtime overrides.
for key in ("PROTON_EAC_RUNTIME", "PROTON_BATTLEYE_RUNTIME"):
    if key in steam_env:
        env[key] = steam_env[key]
env.update({
    "SteamAppId": appid, "SteamGameId": appid, "SteamOverlayGameId": appid,
    "STEAM_COMPAT_APP_ID": appid,
    "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam),
    "STEAM_COMPAT_DATA_PATH": str(prefix),
    "STEAM_COMPAT_INSTALL_PATH": str(game),
    "STEAM_COMPAT_LIBRARY_PATHS": str(steam),
    "STEAM_COMPAT_TOOL_PATHS": str(proton.parent) + ":" + str(entry.parent),
    "PRESSURE_VESSEL_FILESYSTEMS_RO": "/nix:/run/current-system",
    "VR_OVERRIDE": str(runtime),
    "XR_RUNTIME_JSON": str(xr_manifest),
    "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES": "1",
    "PROTON_LOG": "1",
})
if args.backend == "wivrn":
    env["PULSE_SINK"] = "wivrn.sink"
    env["PULSE_SOURCE"] = "wivrn.source"
    env["PRESSURE_VESSEL_FILESYSTEMS_RW"] = str(Path(os.environ["XDG_RUNTIME_DIR"]) / "wivrn")
command = ["steam-run", str(entry), "--verb=waitforexitandrun", "--", str(proton), "waitforexitandrun", str(game / executable), *default_args, *game_args]
if args.dry_run:
    print(shlex.join(command))
    print("OpenVR:", env["VR_OVERRIDE"])
    print("OpenXR:", env["XR_RUNTIME_JSON"])
    print("Prefix:", prefix)
    print("Steam video token:", "available" if video_token else "missing")
    if args.game == "forefront" and args.backend == "steamvr":
        print("Workaround: in-game render scale 1.0 (applied on launch)")
    sys.exit(0)
if args.backend == "wivrn":
    ipc = Path(os.environ["XDG_RUNTIME_DIR"]) / "wivrn/comp_ipc"
    if not ipc.is_socket():
        sys.exit("Start WiVRn and connect the Frame first (WiVRn compositor socket is missing).")
    registry = Path.home() / ".config/openvr/openvrpaths.vrpath"
    selection = json.loads(registry.read_text())
    if selection.get("runtime") != [str(runtime)]:
        sys.exit("The host OpenVR registry is not set to XRizer; stop SteamVR and restore the normal registry before launching.")
else:
    if not any((p / "comm").read_text().strip() == "vrserver" for p in Path("/proc").iterdir() if p.name.isdigit() and (p / "comm").exists()):
        sys.exit("Start the Frame SteamVR session and connect the headset first.")
    if args.game == "forefront":
        fix_forefront_render_scale(prefix, proton)
    # Proton's native OpenVR bridge also consults the host registry. A Home
    # Manager activation can replace our session's temporary selection with the
    # default XRizer symlink while SteamVR remains running. Reassert the session
    # selection by replacing the link, retaining its original restoration backup.
    registry = Path.home() / ".config/openvr/openvrpaths.vrpath"
    selection = json.loads(registry.read_text())
    if selection.get("runtime") != [str(runtime)]:
        backup = registry.with_name("openvrpaths.vrpath.before-steamvr")
        if not (backup.exists() or backup.is_symlink()):
            sys.exit("SteamVR session registry backup is missing; restart the Frame SteamVR session.")
        selection["runtime"] = [str(runtime)]
        temporary = registry.with_name("openvrpaths.vrpath.frame-new")
        temporary.write_text(json.dumps(selection, indent=2) + "\n")
        os.replace(temporary, registry)
os.chdir(game)
os.execvpe(command[0], command, env)
