#!/usr/bin/env python3
"""Capture a bounded, already-connected WiVRn session without headset UI steps."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--label", required=True)
    p.add_argument("--seconds", type=int, default=30)
    p.add_argument("--root", type=Path, default=Path.home()/".cache/wivrn-frame/diagnostics")
    p.add_argument("--ssh", default="steamos@192.168.1.16")
    p.add_argument("--ssh-control", default="/run/user/1000/frame-ssh")
    a = p.parse_args()
    if not 1 <= a.seconds <= 120 or Path(a.label).name != a.label or a.label in (".", ".."):
        p.error("use a simple label and 1–120 seconds")
    destination = a.root / (time.strftime("%Y%m%d-%H%M%S-") + a.label)
    destination.mkdir(parents=True)
    start = time.time()
    live = a.root/"feedback-current.csv"
    # Read only rows appended during this capture. Keep header for CSV parsing.
    with live.open() as f:
        header = f.readline()
        f.seek(0, 2)
        offset = f.tell()
    with (destination/"socket.txt").open("w") as f:
        for _ in range(a.seconds):
            lines = subprocess.check_output(["ss", "-tunip"], text=True).splitlines()
            for i, line in enumerate(lines[:-1]):
                if "]:9757 " in line:
                    f.write(f"{time.time():.3f} {line}\n{lines[i+1]}\n")
            f.flush()
            time.sleep(1)
    with live.open() as f:
        f.seek(offset)
        data = f.read()
    # Skip a partially written first row and trailing row in a live buffered file.
    data = data.split("\n", 1)[1] if "\n" in data else ""
    data = data.rsplit("\n", 1)[0] + "\n" if "\n" in data else ""
    csv_path = destination/"feedback.csv"
    csv_path.write_text(header + data)
    summary = subprocess.check_output(["python3", str(Path(__file__).with_name("wivrn-timing-summary.py")),
                                       str(csv_path)], text=True)
    (destination/"summary.json").write_text(summary)
    since = "@" + str(int(start))
    (destination/"server.log").write_text(subprocess.check_output(
        ["journalctl", "--user", "-u", "wivrn.service", "--since", since, "--no-pager"], text=True))
    (destination/"client.log").write_text(subprocess.check_output(
        ["ssh", "-S", a.ssh_control, "-o", "BatchMode=yes", a.ssh,
         "journalctl", "--user", "-u", "wivrn-frame-client", "--since", since, "--no-pager"], text=True))
    parsed = json.loads(summary)
    print(json.dumps(dict(path=str(destination), stages=parsed), indent=2))
    if not any(s["displayed"] for s in parsed.values()):
        print("No displayed frames: capture is not a rendering-performance test.")


if __name__ == "__main__":
    main()
