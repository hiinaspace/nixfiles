#!/usr/bin/env python3
"""Summarize WIVRN_FRAME_TIMINGS feedback, merging progress reports per frame.

Zero timestamps are unavailable stages, not zero latency. Display feedback is
not a visual-quality measurement. Repeated presentations are reported separately.
"""
import argparse
import csv
import json
import math
from collections import defaultdict


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    def q(f):
        return round(values[min(len(values) - 1, math.ceil(f * len(values)) - 1)], 3)
    return dict(n=len(values), p50=q(.5), p95=q(.95), p99=q(.99), maximum=q(1))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("csv")
    a = p.parse_args()
    frames = defaultdict(dict)
    with open(a.csv) as f:
        for row in csv.DictReader(f):
            if None in row or any(v is None for v in row.values()):
                continue  # may be a trailing row in a live buffered export
            r = {k: int(v) for k, v in row.items()}
            old = frames[(r["stream"], r["frame"])]
            for k, v in r.items():
                old[k] = max(old.get(k, 0), v)
    streams = defaultdict(list)
    for (stream, frame), row in frames.items():
        streams[stream].append(row)
    result = {}
    stages = dict(encode=("encode_begin", "encode_end"),
                  send_to_arrival=("send_begin", "receive_end"),
                  packet_assembly=("receive_begin", "receive_end"),
                  decode=("decode_begin", "decode_end"),
                  decode_to_blit=("decode_end", "blit"),
                  blit_to_display=("blit", "display"),
                  encode_to_display=("encode_begin", "display"))
    for stream, rows in sorted(streams.items()):
        out = dict(frames=len(rows), decoded=sum(r["decode_end"] > 0 for r in rows),
                   displayed=sum(r["display"] > 0 for r in rows),
                   repeat_presentations=sum(max(0, r["times_displayed"] - 1) for r in rows))
        out["milliseconds"] = {
            name: distribution([(r[end] - r[start]) / 1e6 for r in rows
                                if r[start] and r[end] and r[end] >= r[start]])
            for name, (start, end) in stages.items()}
        displays = sorted(set(r["display"] for r in rows if r["display"]))
        out["milliseconds"]["distinct_frame_display_gap"] = distribution(
            [(b - a) / 1e6 for a, b in zip(displays, displays[1:])])
        result[stream] = out
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
