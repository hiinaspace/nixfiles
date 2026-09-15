"""Wait for the login display before starting the D-Bus keyring prompter.

A lingering user manager can activate this before login. Its initial environment
does not contain the display that niri-session later imports into the manager.
Never shell-evaluate that environment or print its potentially sensitive values.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time


def display_ready(env):
    wayland = env.get("WAYLAND_DISPLAY")
    if wayland:
        path = Path(wayland)
        if not path.is_absolute():
            runtime = env.get("XDG_RUNTIME_DIR")
            if not runtime:
                return False
            path = Path(runtime) / path
        try:
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(1)
                connection.connect(str(path))
            return True
        except OSError:
            return False
    display = env.get("DISPLAY", "")
    if display.startswith(":"):
        number = display[1:].split(".", 1)[0]
        return number.isdigit() and Path(f"/tmp/.X11-unix/X{number}").is_socket()
    return False


def main():
    systemctl, prompter = sys.argv[1:]
    print("Waiting for the graphical login environment before keyring prompting", flush=True)
    while True:
        try:
            result = subprocess.run(
                [systemctl, "--user", "show-environment", "--output=json"],
                check=True, capture_output=True, text=True, timeout=5,
            )
            manager_env = json.loads(result.stdout)
            if display_ready(manager_env):
                env = os.environ.copy()
                # Do not retain a previous session's display if it was removed.
                for key in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "GDK_BACKEND"):
                    env.pop(key, None)
                env.update(manager_env)
                print("Graphical display ready; starting keyring prompter", flush=True)
                os.execve(prompter, [prompter], env)
        except (subprocess.SubprocessError, json.JSONDecodeError):
            pass
        time.sleep(0.5)


if __name__ == "__main__":
    main()
