"""Compare identically built public-API benchmark executables sequentially."""
import argparse
import collections
import json
import math
from pathlib import Path
import random
import statistics
import subprocess
import time

CASES = ['scan_1mb', 'literal_miss', 'phone_lines', 'large_pattern',
         'find_digits', 'find_emails', 'find_words', 'lazy_search',
         'anchored_short', 'split', 'replace', 'unicode_class',
         'dense_short', 'dense_long', 'no_capture_short', 'no_capture_long',
         'many_captures', 'nullable', 'delayed_capture']
JOBS = [(case, 'hot') for case in CASES] + [
    (case, phase) for case in ['cold_email', 'cold_large']
    for phase in ['cold', 'parse']]
TARGETS = ['native', 'wasm-gc', 'js']


def command(root, package, target, case, phase):
    extension = {'native': 'exe', 'js': 'js', 'wasm-gc': 'wasm'}[target]
    executable = root / '_build' / target / 'release/build' / package / (package + '.' + extension)
    prefix = [] if target == 'native' else ['node' if target == 'js' else 'moonrun']
    return prefix + [str(executable), case, phase]


def summarize(rows):
    groups = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(list)))
    checks = collections.defaultdict(lambda: collections.defaultdict(set))
    for row in rows:
        key = row['target'], row['case'], row['phase']
        groups[key][row['variant']][row['repeat']].append(row['us'])
        checks[key][row['variant']].add(row['checksum'])
    result = []
    for key, variants in sorted(groups.items()):
        medians = {v: {i: statistics.median(samples) for i, samples in rounds.items()}
                   for v, rounds in variants.items()}
        entry = dict(target=key[0], case=key[1], phase=key[2],
                     checksum={v: sorted(s) for v, s in checks[key].items()},
                     us={v: statistics.median(list(rounds.values())) for v, rounds in medians.items()},
                     ratios={})
        entry['same_checksum'] = len({tuple(s) for s in entry['checksum'].values()}) == 1
        for variant in ['before', 'after', 'claude']:
            ratios = [medians[variant][i] / medians['main'][i] for i in medians['main']]
            entry['ratios'][variant] = dict(median=statistics.median(ratios),
                                            min=min(ratios), max=max(ratios), rounds=ratios)
        entry['after_before'] = statistics.median([
            medians['after'][i] / medians['before'][i] for i in medians['main']])
        result.append(entry)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--main-root', type=Path, required=True)
    parser.add_argument('--before-root', type=Path, required=True)
    parser.add_argument('--claude-root', type=Path, required=True)
    parser.add_argument('--after-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error('--rounds must be positive')
    roots = {v: (getattr(args, v + '_root').resolve(), 'benchmarks' if v == 'after' else 'engine_eval')
             for v in ['main', 'before', 'after', 'claude']}
    # Refuse to mix this run with existing evidence.
    args.out.mkdir(parents=True, exist_ok=False)
    rng = random.Random(20261012)
    rows = []
    begin = time.monotonic()
    last = begin
    with (args.out / 'rows.jsonl').open('w') as stream:
        for repeat in range(args.rounds):
            jobs = [(target, case, phase) for target in TARGETS for case, phase in JOBS]
            rng.shuffle(jobs)
            for index, (target, case, phase) in enumerate(jobs):
                variants = list(roots)
                rng.shuffle(variants)
                for variant in variants:
                    root, package = roots[variant]
                    process = subprocess.run(command(root, package, target, case, phase),
                                             capture_output=True, text=True, timeout=120)
                    if process.returncode:
                        raise RuntimeError((variant, target, case, phase, process.stderr))
                    samples = []
                    for line in process.stdout.splitlines():
                        if line.startswith('ROW,'):
                            _, c, p, sample, count, us, checksum, sink = line.split(',')
                            samples.append(dict(variant=variant, target=target, case=c, phase=p,
                                                repeat=repeat, sample=int(sample), count=int(count),
                                                us=float(us), checksum=int(checksum)))
                    if len(samples) != 3:
                        raise RuntimeError(process.stdout)
                    for row in samples:
                        stream.write(json.dumps(row) + '\n')
                    stream.flush()
                    rows.extend(samples)
                if time.monotonic() - last > 25:
                    print(f'round={repeat+1}/{args.rounds} jobs={index+1}/{len(jobs)} '
                          f'elapsed={time.monotonic()-begin:.0f}s latest={target}/{case}/{phase}', flush=True)
                    last = time.monotonic()
            print(f'round {repeat+1} complete', flush=True)
    summary = summarize(rows)
    (args.out / 'summary.json').write_text(json.dumps(summary, indent=2))
    for target in TARGETS:
        comparable = [r for r in summary if r['target'] == target and r['phase'] == 'hot' and r['same_checksum']]
        print(target, {v: math.exp(statistics.mean(math.log(r['ratios'][v]['median']) for r in comparable))
                       for v in ['before', 'after', 'claude']}, flush=True)
    print('done', len(rows), 'samples', flush=True)


if __name__ == '__main__':
    main()
