#!/usr/bin/env python3
"""Run bounded probes after stopping the Frame WiVRn client (port 9757).

SSH authentication must already work; uses an existing multiplex socket.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ssh", default="steamos@192.168.1.16")
    p.add_argument("--ssh-control", default="/run/user/1000/frame-ssh")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--seconds", type=float, default=8)
    p.add_argument("--mbps", type=float, default=157)
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    probe = Path(__file__).with_name("frame-network-probe.py")
    paths = [("dongle", "10.35.78.26", "10.35.78.1"),
             ("wifi", "192.168.1.26", "192.168.1.16")]
    results = []
    for name, source, target in paths:
        for transport, pattern in [("udp", "burst"), ("udp", "smooth"), ("tcp", "burst")]:
            shared = ["--transport", transport, "--pattern", pattern,
                      "--seconds", str(a.seconds), "--mbps", str(a.mbps)]
            remote = ["python3", "/home/steamos/Applications/wivrn/network-probe.py",
                      "receive", "--address", target, *shared]
            with subprocess.Popen(["ssh", "-S", a.ssh_control, "-o", "BatchMode=yes", a.ssh, *remote],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as receiver:
                ready = receiver.stderr.readline().strip()
                if ready != "READY":
                    raise RuntimeError(f"receiver did not start: {ready}")
                sender = subprocess.run([sys.executable, str(probe), "send", "--address", target,
                                         "--bind", source, *shared], capture_output=True, text=True,
                                        check=True, timeout=a.seconds + 20)
                stdout, stderr = receiver.communicate(timeout=10)
                if receiver.returncode:
                    raise RuntimeError(stderr)
            tx, rx = json.loads(sender.stdout), json.loads(stdout)
            row = dict(path=name, transport=transport, pattern=pattern, sender=tx, receiver=rx,
                       lost_packets=tx["packets"] - rx["received"])
            results.append(row)
            (a.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()
