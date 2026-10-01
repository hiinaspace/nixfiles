#!/usr/bin/env python3
"""Compare TCP capture timestamps using sequence numbers, including receiver GRO.

Capture timestamps bound delivery to kernel capture points, not air transmission
or userspace consumption. Clock offset is estimated from both directions.
"""
import argparse
import json
from pathlib import Path


def percentile(values, q):
    return sorted(values)[round((len(values) - 1) * q)] if values else None


def stats(values):
    return {k: percentile(values, q) for k, q in
            (("minimum", 0), ("p50", .5), ("p95", .95), ("p99", .99), ("maximum", 1))}


def read(path):
    rows = []
    for line in Path(path).open():
        f = line.rstrip("\n").split("\t")
        if len(f) != 12 or not f[4]:
            continue
        rows.append(dict(t=float(f[0]), src=f[1], seq=int(f[4]), ack=int(f[5]),
                         size=int(f[6]), retx=bool(f[7] or f[8]), dupack=bool(f[9]),
                         ooo=bool(f[10])))
    return rows


def match(sent, received, source):
    # GRO joins consecutive segments, but preserves the starting sequence number.
    # Match receiver starts to the first sender observation. Retransmitted bytes
    # therefore retain their original send time in the resulting delay.
    lookup = {}
    for r in sent:
        if r["src"] == source and r["size"]:
            key = (r["seq"],)
            lookup.setdefault(key, r)
    result = []
    for r in received:
        if r["src"] != source or not r["size"]:
            continue
        key = (r["seq"],)
        s = lookup.get(key)
        if s:
            result.append((s, r, r["t"] - s["t"]))
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("directory", type=Path)
    a = p.parse_args()
    host, frame = [read(a.directory / (s + "-tcp.tsv")) for s in ("host", "frame")]
    forward = match(host, frame, "10.35.78.26")
    reverse = match(frame, host, "10.35.78.1")
    if not forward or not reverse:
        p.error("no matched packets in one or both directions")
    # Nonnegative transit gives bounds: -min(reverse) <= offset <= min(forward).
    low, high = -min(x[2] for x in reverse), min(x[2] for x in forward)
    offset = (low + high) / 2
    begin = max(host[0]["t"], frame[0]["t"] - offset) + 1
    end = min(host[-1]["t"], frame[-1]["t"] - offset) - 1
    report = {"clock_offset_frame_minus_host_seconds_bounds": [low, high],
              "clock_offset_estimate_seconds": offset, "interior_overlap_seconds": end - begin,
              "cautions": ["GRO changes segment boundaries; matches sample receiver starts",
                           "No userspace or physical on-air timestamps",
                           "Validate tcpdump drop counts separately"]}
    for name, matches, adjustment in (("host_to_frame", forward, offset),
                                      ("frame_to_host", reverse, -offset)):
        values = [(d - adjustment) * 1000 for s, r, d in matches
                  if begin <= (s["t"] if name == "host_to_frame" else s["t"] - offset) <= end]
        report[name] = {"matched_samples": len(values), "kernel_capture_delay_ms": stats(values)}
    for name, rows, adjustment in (("host", host, 0), ("frame", frame, offset)):
        selected = [r for r in rows if begin <= r["t"] - adjustment <= end]
        report[name] = dict(packets=len(selected), retransmission_flags=sum(r["retx"] for r in selected),
                            duplicate_ack_flags=sum(r["dupack"] for r in selected),
                            out_of_order_flags=sum(r["ooo"] for r in selected),
                            max_tcp_payload=max((r["size"] for r in selected), default=0))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
