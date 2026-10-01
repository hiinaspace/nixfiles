#!/usr/bin/env python3
"""Export bounded paired captures for the Frame TCP/UDP comparison helpers."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess

FIELDS = {
    'tcp': ['frame.time_epoch', 'ip.src', 'ip.dst', 'ip.len', 'tcp.seq_raw',
            'tcp.ack_raw', 'tcp.len', 'tcp.analysis.retransmission',
            'tcp.analysis.fast_retransmission', 'tcp.analysis.duplicate_ack',
            'tcp.analysis.out_of_order', 'tcp.analysis.ack_rtt'],
    'udp': ['frame.time_epoch', 'ip.src', 'ip.dst', 'ip.len', 'udp.length',
            'udp.payload', 'ip.flags.mf', 'ip.frag_offset'],
}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory', type=Path)
    p.add_argument('--tshark', default='tshark')
    a = p.parse_args()

    def export(job):
        side, proto = job
        with (a.directory / (side + '-' + proto + '.tsv')).open('w') as f:
            subprocess.run([a.tshark, '-r', str(a.directory / (side + '.pcap')),
                            '-Y', proto + '.port == 9757', '-T', 'fields',
                            *[arg for field in FIELDS[proto] for arg in ['-e', field]]],
                           stdout=f, check=True)

    with ThreadPoolExecutor(4) as pool:
        list(pool.map(export, [(s, p) for s in ['host', 'frame'] for p in FIELDS]))


if __name__ == '__main__':
    main()
