"""Launch VRChat's normal protected launcher through Proton, bypassing saved Steam options."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dry-run", action="store_true")
args, game_args = parser.parse_known_args()
steam = Path.home() / ".local/share/Steam"
game = steam / "steamapps/common/VRChat"
runtime = steam / "steamapps/common/SteamVR"
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
    sys.exit("Start Steam before launching VRChat.")
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
for path in (proton, entry, game / "launch.exe", runtime / "steamxr_linux64.json"):
    if not path.is_file():
        sys.exit(f"Missing required file: {path}")
prefix = steam / "steamapps/compatdata/438100"
if not (prefix / "pfx").is_dir():
    sys.exit("Missing existing VRChat Proton prefix; launch/install VRChat normally first.")
for key in list(env):
    if key.startswith("XRIZER_") or key in ("XR_RUNTIME_JSON", "VR_OVERRIDE", "VR_PATHREG_OVERRIDE", "OXR_PARALLEL_VIEWS", "RUST_LOG", "PRESSURE_VESSEL_FILESYSTEMS_RW"):
        env.pop(key)
# Retain Steam's anti-cheat runtime paths without importing its runtime overrides.
for key in ("PROTON_EAC_RUNTIME", "PROTON_BATTLEYE_RUNTIME"):
    if key in steam_env:
        env[key] = steam_env[key]
env.update({
    "SteamAppId": "438100", "SteamGameId": "438100", "SteamOverlayGameId": "438100",
    "STEAM_COMPAT_APP_ID": "438100",
    "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam),
    "STEAM_COMPAT_DATA_PATH": str(prefix),
    "STEAM_COMPAT_INSTALL_PATH": str(game),
    "STEAM_COMPAT_LIBRARY_PATHS": str(steam),
    "STEAM_COMPAT_TOOL_PATHS": str(proton.parent) + ":" + str(entry.parent),
    "PRESSURE_VESSEL_FILESYSTEMS_RO": "/nix:/run/current-system",
    "VR_OVERRIDE": str(runtime),
    "XR_RUNTIME_JSON": str(runtime / "steamxr_linux64.json"),
    "PROTON_LOG": "1",
})
command = ["steam-run", str(entry), "--verb=waitforexitandrun", "--", str(proton), "waitforexitandrun", str(game / "launch.exe"), *game_args]
if args.dry_run:
    print(shlex.join(command))
    print("OpenVR:", env["VR_OVERRIDE"])
    print("OpenXR:", env["XR_RUNTIME_JSON"])
    print("Prefix:", prefix)
    print("Steam video token:", "available" if video_token else "missing")
    sys.exit(0)
if not any((p / "comm").read_text().strip() == "vrserver" for p in Path("/proc").iterdir() if p.name.isdigit() and (p / "comm").exists()):
    sys.exit("Start the Frame SteamVR session and connect the headset first.")
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
