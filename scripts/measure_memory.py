"""Measure fresh native child-process peak RSS without timing unrelated work."""
import argparse
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import time

from compare import command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--main-root', type=Path, required=True)
    parser.add_argument('--before-root', type=Path, required=True)
    parser.add_argument('--claude-root', type=Path, required=True)
    parser.add_argument('--after-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('refusing to overwrite an existing result file')
    args.out.parent.mkdir(parents=True, exist_ok=True)
    roots = {v: (getattr(args, v + '_root').resolve(), 'benchmarks' if v == 'after' else 'engine_eval')
             for v in ['main', 'before', 'after', 'claude']}
    rng = random.Random(20261012)
    rows = []
    for case in ['cold_email', 'cold_large', 'slot_stress']:
        for repeat in range(3):
            variants = list(roots)
            rng.shuffle(variants)
            for variant in variants:
                root, package = roots[variant]
                start = time.monotonic()
                child = subprocess.Popen(command(root, package, 'native', case, 'memory'),
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                # The native child emits only one short line: it cannot fill
                # its pipes while waiting. Reap it once and use its own RSS,
                # not RUSAGE_CHILDREN's cumulative maximum across variants.
                _, status, usage = os.wait4(child.pid, 0)
                child.returncode = os.waitstatus_to_exitcode(status)
                output = child.stdout.read()
                log = child.stderr.read()
                if child.returncode:
                    raise RuntimeError(log)
                rss = usage.ru_maxrss if sys.platform == 'darwin' else usage.ru_maxrss * 1024
                rows.append(dict(variant=variant, case=case, repeat=repeat,
                                 rss_bytes=rss, wall_s=time.monotonic() - start,
                                 output=output, log=log, method='os.wait4 child ru_maxrss'))
                args.out.write_text(json.dumps(rows, indent=2))
                print(variant, case, round(rss / 1048576, 2), 'MiB', flush=True)


if __name__ == '__main__':
    main()
