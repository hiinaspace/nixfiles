#!/usr/bin/env python3
"""Match UDP payload prefixes between bounded host/Frame packet captures.

Requires TSV columns: epoch, src, dst, ip.len, udp.length, udp.payload,
ip.flags.mf, ip.frag_offset. Compare only interior capture packets. The
encrypted payload prefix includes WiVRn's per-packet IV; no decryption needed.
"""
import argparse
import collections
import json
from pathlib import Path


def stats(values):
    v = sorted(values)
    return {k: v[round((len(v)-1)*q)] if v else None for k, q in
            (("minimum", 0), ("p50", .5), ("p95", .95), ("p99", .99), ("maximum", 1))}


def read(path):
    rows = []
    for line in path.open():
        f = line.rstrip("\n").split("\t")
        if len(f) != 8 or not f[4] or not f[5]:
            continue
        rows.append(dict(t=float(f[0]), src=f[1], iplen=int(f[3]), length=int(f[4]),
                         key=(f[1], f[4], f[5].replace(":", "")[:64]),
                         fragmented=f[6] == "1" or int(f[7] or 0) != 0))
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("directory", type=Path)
    p.add_argument("--clock-offset", required=True, type=float,
                   help="Frame minus host clock in seconds, from paired TCP")
    a = p.parse_args()
    h, f = [read(a.directory/(s+'-udp.tsv')) for s in ('host', 'frame')]
    for r in f:
        r['t'] -= a.clock_offset
    begin, end = max(h[0]['t'], f[0]['t'])+1, min(h[-1]['t'], f[-1]['t'])-1
    report = dict(interior_overlap_seconds=end-begin,
                  cautions=['Absent means absent at receiver capture point, not proven on-air loss',
                            'Check capture drop counts and fragmentation separately'])
    for name, source, sent, received in [('host_to_frame','10.35.78.26',h,f),
                                        ('frame_to_host','10.35.78.1',f,h)]:
        lookup = collections.defaultdict(list)
        for r in received:
            lookup[r['key']].append(r['t'])
        selected = [r for r in sent if r['src']==source and begin<=r['t']<=end]
        missing = [r for r in selected if r['key'] not in lookup]
        matched = [r for r in selected if r['key'] in lookup]
        delays = [(min(lookup[r['key']])-r['t'])*1000 for r in matched]
        keys = [r['key'] for r in selected]
        report[name] = dict(sent=len(selected), absent_at_receiver=len(missing),
                            absent_percent=100*len(missing)/len(selected) if selected else None,
                            duplicate_sender_keys=len(keys)-len(set(keys)),
                            kernel_capture_delay_ms=stats(delays),
                            max_ip_length=max((r['iplen'] for r in selected),default=0),
                            fragmented_packets=sum(r['fragmented'] for r in selected))
        (a.directory/(name+'-missing.json')).write_text(json.dumps(missing,indent=2))
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
