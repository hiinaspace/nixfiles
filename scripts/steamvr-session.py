"""Session-scoped SteamVR selection; preserve the Home Manager XRizer link."""
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

home = Path.home()
steam = home / ".local/share/Steam"
runtime = Path(os.environ.get("STEAMVR_RUNTIME_DIR", str(steam / "steamapps/common/SteamVR"))).expanduser().resolve()
if not (runtime / "bin/linux64/vrstartup").is_file():
    sys.exit(f"SteamVR startup executable missing: {runtime}")
registry = home / ".config/openvr/openvrpaths.vrpath"
state = Path(os.environ["XDG_RUNTIME_DIR"]) / "steamvr-native"
state.mkdir(mode=0o700, exist_ok=True)
lock = (state / "lock").open("w")
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

def processes(name):
    found = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid == os.getuid() and (proc / "comm").read_text().strip() == name:
                # An unreaped zombie no longer owns devices or runtime sockets.
                if (proc / "stat").read_text().rsplit(")", 1)[1].split()[0] != "Z":
                    found.append(int(proc.name))
        except (OSError, ProcessLookupError):
            pass
    return found

if processes("monado-service") or processes("vrserver"):
    sys.exit("Stop the existing Monado/SteamVR session before starting native SteamVR.")
backup = registry.with_name("openvrpaths.vrpath.before-steamvr")
if backup.exists() or backup.is_symlink():
    sys.exit(f"Unrestored registry backup exists: {backup}. Inspect it before retrying.")
if not registry.exists():
    sys.exit(f"Missing OpenVR registry: {registry}")
if not os.environ.get("WAYLAND_DISPLAY"):
    sys.exit("WAYLAND_DISPLAY missing; launch from the graphical session.")
original = json.loads(registry.read_text())
selected = dict(original, runtime=[str(runtime)])
frame_session = os.environ.get("STEAMVR_FRAME_SESSION") == "1"
if not frame_session:
    subprocess.run(["systemctl", "--user", "start", "vr-lighthouses.service"], check=True)
settings = steam / "config/steamvr.vrsettings"
original_driver = None
had_driver = False
if frame_session:
    config = json.loads(settings.read_text()) if settings.exists() else {}
    section = config.setdefault("steamvr", {})
    had_driver = "forcedDriver" in section
    original_driver = section.get("forcedDriver")
    section["forcedDriver"] = "vrlink"
    settings.write_text(json.dumps(config, indent=2) + "\n")
# Same-directory rename retains the exact original symlink or regular file.
temp = registry.with_name("openvrpaths.vrpath.steamvr-new")
temp.write_text(json.dumps(selected, indent=2) + "\n")
os.replace(registry, backup)
os.replace(temp, registry)
stopping = False

def request_stop(_sig, _frame):
    global stopping
    stopping = True

signal.signal(signal.SIGTERM, request_stop)
signal.signal(signal.SIGINT, request_stop)
child = None
owned_server = []
try:
    env = os.environ.copy()
    if not env.get("WAYLAND_DISPLAY"):
        raise RuntimeError("WAYLAND_DISPLAY missing; launch from the graphical session.")
    env["VR_OVERRIDE"] = str(runtime)
    env["XR_RUNTIME_JSON"] = str(runtime / "steamxr_linux64.json")
    child = subprocess.Popen([
        "steam-run",
        str(steam / "steamapps/common/SteamLinuxRuntime_sniper/run-in-sniper"),
        "--filesystem=" + str(runtime),
        str(runtime / "bin/vrenv.sh"),
        str(runtime / "bin/linux64/vrstartup"),
    ], env=env)
    deadline = time.monotonic() + 30
    while not stopping and time.monotonic() < deadline:
        owned_server = processes("vrserver")
        if owned_server:
            break
        time.sleep(0.2)
    if not owned_server:
        raise RuntimeError("SteamVR server did not start; inspect steamvr-native journal.")
    print("Native SteamVR running. Tests: steamvr-run COMMAND. Stop: stop-steamvr.", flush=True)
    while not stopping and set(owned_server).intersection(processes("vrserver")):
        time.sleep(0.5)
finally:
    # No VR server existed on entry; stop this runtime, not the Steam client.
    for name in ("vrmonitor", "vrserver"):
        for pid in processes(name):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    if child and child.poll() is None:
        child.terminate()
    deadline = time.monotonic() + 10
    while (processes("vrserver") or processes("vrcompositor")) and time.monotonic() < deadline:
        time.sleep(0.2)
    if frame_session:
        config = json.loads(settings.read_text())
        section = config.setdefault("steamvr", {})
        if section.get("forcedDriver") == "vrlink":
            if had_driver:
                section["forcedDriver"] = original_driver
            else:
                section.pop("forcedDriver", None)
            settings.write_text(json.dumps(config, indent=2) + "\n")
    try:
        current = json.loads(registry.read_text())
    except (OSError, ValueError):
        current = {}
    if processes("vrserver") or processes("vrcompositor"):
        print(f"SteamVR has not stopped; retain native selection and backup at {backup}.", file=sys.stderr)
    elif current.get("runtime") == [str(runtime)]:
        os.replace(backup, registry)
        print("Restored previous OpenVR selection.", flush=True)
    elif current == original:
        # Home Manager may have installed a new generation's symlink with the
        # same contents. Keep its current link, retiring only our redundant one.
        backup.unlink()
        print("Previous OpenVR selection already restored externally.", flush=True)
    else:
        print(f"OpenVR selection changed externally; original retained at {backup}.", file=sys.stderr)
