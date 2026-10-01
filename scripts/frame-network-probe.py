#!/usr/bin/env python3
"""Bounded IP transport probe. Run receiver on Frame, sender on host.

Uses WiVRn's already-open port after stopping WiVRn. No codec or XR runtime.
Results characterize this Python workload, not VR readiness.
"""
import argparse
import json
import math
import socket
import struct
import sys
import time

HEADER = struct.Struct("!II")


def percentile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, math.ceil(len(values) * fraction) - 1)] if values else None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=["send", "receive"])
    p.add_argument("--transport", choices=["udp", "tcp"], default="udp")
    p.add_argument("--pattern", choices=["burst", "smooth"], default="burst")
    p.add_argument("--address", required=True)
    p.add_argument("--bind", default="")
    p.add_argument("--port", type=int, default=9757)
    p.add_argument("--seconds", type=float, default=8)
    p.add_argument("--mbps", type=float, default=157)
    p.add_argument("--hz", type=float, default=90)
    p.add_argument("--output")
    a = p.parse_args()
    udp = a.transport == "udp"
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2 * 1024 * 1024)
    if not udp:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if a.mode == "send":
        if a.bind:
            s.bind((a.bind, 0))
        s.connect((a.address, a.port))
        start = time.monotonic()
        failures = packets = sent_bytes = 0
        max_send_ms = 0
        payload = bytes(1400 - HEADER.size)
        frames = int(a.seconds * a.hz)
        per_frame = a.mbps * 1e6 / 8 / a.hz
        for frame in range(frames):
            chunks = max(1, round(per_frame / 1400)) if udp else 1
            frame_payload = payload if udp else bytes(round(per_frame))
            before = time.monotonic()
            for chunk in range(chunks):
                deadline = start + frame / a.hz
                if a.pattern == "smooth":
                    # Batches of eight UDP packets keep Python scheduling cost bounded.
                    deadline += (chunk // 8 * 8) / chunks / a.hz
                delay = deadline - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                data = HEADER.pack(packets, frame if udp else len(frame_payload)) + frame_payload
                try:
                    if udp:
                        s.send(data)
                    else:
                        s.sendall(data)
                    sent_bytes += len(data)
                except OSError:
                    failures += 1
                packets += 1
            max_send_ms = max(max_send_ms, (time.monotonic() - max(before, start + frame / a.hz)) * 1000)
        result = dict(packets=packets, bytes=sent_bytes, failures=failures,
                      elapsed_s=time.monotonic() - start, max_send_ms=max_send_ms)
    else:
        s.bind((a.address, a.port))
        s.settimeout(15)
        if not udp:
            s.listen(1)
        print("READY", file=sys.stderr, flush=True)
        if not udp:
            s, _ = s.accept()
            s.settimeout(2)
        seen = set()
        byte_count = reorder = 0
        max_seq = -1
        last_frame = -1
        previous_frame_time = None
        gaps = []
        buffer = bytearray()
        start = None
        while True:
            try:
                data = s.recv(65536)
            except socket.timeout:
                break
            if not data:
                break
            now = time.monotonic()
            if start is None:
                start = now
                s.settimeout(2)
            if now - start > a.seconds + 5:
                break
            byte_count += len(data)
            records = []
            if udp:
                records.append(HEADER.unpack_from(data))
            else:
                buffer.extend(data)
                while len(buffer) >= HEADER.size:
                    seq, length = HEADER.unpack_from(buffer)
                    if length > 16 * 1024 * 1024:
                        raise ValueError("invalid frame length")
                    if len(buffer) < HEADER.size + length:
                        break
                    del buffer[:HEADER.size + length]
                    records.append((seq, seq))
            for seq, frame in records:
                if seq < max_seq and seq not in seen:
                    reorder += 1
                max_seq = max(max_seq, seq)
                seen.add(seq)
                if frame > last_frame:
                    if previous_frame_time is not None:
                        gaps.append((now - previous_frame_time) * 1000)
                    previous_frame_time, last_frame = now, frame
        result = dict(received=len(seen), missing=max_seq + 1 - len(seen), reordered=reorder,
                      bytes=byte_count, receive_buffer=s.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF),
                      frame_gap_ms=dict(p50=percentile(gaps, .5), p99=percentile(gaps, .99),
                                        maximum=max(gaps, default=0)))
    s.close()
    result.update(transport=a.transport, pattern=a.pattern, target_mbps=a.mbps, hz=a.hz)
    output = json.dumps(result, indent=2) + "\n"
    if a.output:
        with open(a.output, "w") as f:
            f.write(output)
    print(output, end="")


if __name__ == "__main__":
    main()
