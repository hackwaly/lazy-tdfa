# Optimized lazy-tdfa: 2026-10-11 benchmark

These measurements describe commit 9dce342, before the later switch to Go's
nullable repetition priority. The old capture compatibility statements below
apply to that measured commit. They do not describe current nullable captures
or establish performance numbers for the subsequent semantic change.

This compares the optimized standalone engine with its pre-optimization core engine, current core main, and bobzhang/tdfa. All four implementations run the same public-API driver on the same machine, interleaved sequentially in three independent rounds. These are freshly measured results, not ratios copied from an earlier run.

- main: `398e080a313ec0e94ba9964d5b1c054321c44516`
- before: `b7625ab222e59307f225350b13c76540f3447a11`
- after: `9dce342ee4cececd7861c458434a8d290fe8517f` (engine optimization commit in this repository)
- Claude: `48302f3272c93f2a6aa9a67c55eff249472e6bbc` from https://github.com/bobzhang/tdfa
- Apple M2 Max, 64 GiB; release builds; moonc `v0.10.14+122871fce-dev`, Node `v24.18.1`, moonrun `0.1.20260920 (914d7da)`.
- The standalone build uses core main rebuilt by the same compiler as its bundled standard library, through an isolated MOON_TOOLCHAIN_ROOT. Original comparison snapshots use the same core/builtin/runtime sources. The installed older compiler's prebuilt core files must not be linked by the newer development compiler.

## Results

Values below are time relative to core main: less than 1 is faster. Per-process batch medians produce paired round ratios; the table uses the median of three round ratios. Each process warms up and calibrates its iteration count to at least approximately 100 ms (up to 1,048,576 iterations), then measures three batches. Raw samples and per-round ranges are stored alongside this report. No fastest-run selection.

| Equal-weight hot-case geometric mean | native | wasm-gc | JS |
|---|---:|---:|---:|
| Before | 0.837 | 0.927 | 0.870 |
| After | 0.688 | 0.850 | 0.812 |
| Claude | 0.692 | 0.851 | 0.800 |

The aggregate gives equal weight to 18 semantically comparable hot cases, not production workload frequency. It does not imply every regex improves. Nullable repetition is excluded from the four-way aggregate because Claude has different capture semantics.

| Case | before native | after native | Claude native | before wasm-gc | after wasm-gc | Claude wasm-gc | before JS | after JS | Claude JS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| phone_lines / hot | 0.684 | 0.574 | 0.572 | 0.831 | 0.774 | 0.755 | 0.782 | 0.729 | 0.721 |
| large_pattern / hot | 0.778 | 0.630 | 0.640 | 0.850 | 0.772 | 0.747 | 0.874 | 0.822 | 0.818 |
| find_emails / hot | 0.690 | 0.621 | 0.635 | 0.916 | 0.842 | 0.857 | 0.759 | 0.760 | 0.745 |
| split / hot | 0.580 | 0.512 | 0.511 | 0.791 | 0.751 | 0.769 | 0.728 | 0.640 | 0.631 |
| dense_long / hot | 1.204 | 0.755 | 0.754 | 1.074 | 0.901 | 0.905 | 0.990 | 0.964 | 0.964 |
| no_capture_long / hot | 1.148 | 0.710 | 0.715 | 1.070 | 0.893 | 0.891 | 0.957 | 0.932 | 0.930 |
| literal_miss / hot | 1.215 | 0.796 | 0.760 | 1.084 | 0.898 | 0.898 | 1.070 | 0.766 | 0.768 |
| scan_1mb / hot | 0.995 | 0.975 | 0.984 | 1.002 | 0.995 | 1.002 | 0.972 | 0.945 | 0.918 |
| cold_email / cold | 0.690 | 0.655 | 0.689 | 0.745 | 0.731 | 0.784 | 0.898 | 0.847 | 0.868 |
| cold_large / cold | 0.633 | 0.617 | 0.652 | 0.591 | 0.600 | 0.616 | 0.605 | 0.616 | 0.657 |

The full absolute per-workload times are in summary.json: phone_lines includes 24 strings, large_pattern includes 20,000 filenames. Cold means a fresh Regex constructor and first match in an already warmed process; parse means only Regex construction/parsing, as the automaton is lazy. The benchmark does not measure process startup, nor compiler application-build time.

## Memory and correctness

Native peak RSS is measured from macOS wait4 child ru_maxrss in a fresh process, one construction and one match. Three-run medians include process/input/runtime memory, with no baseline subtraction. The pressure workload is `(a)(?:a{256}){9}` on 2400 a characters. It is not representative of ordinary short patterns.

| Peak RSS, MiB | main | before | after | Claude |
|---|---:|---:|---:|---:|
| cold_email | 2.06 | 2.11 | 2.06 | 2.05 |
| cold_large | 2.91 | 2.92 | 2.88 | 2.89 |
| slot_stress | 850.91 | 109.33 | 44.67 | 43.98 |

All 22 workload outputs (full match/capture endpoints, split segment endpoints, and replace strings) agree exactly with the pre-optimization engine. Historical capture digests remain unchanged. `^(a?)*b$` preserves the final empty capture in this engine, while Claude retains the last nonempty a; that difference is deliberately not optimized away.

Validated with 230 tests per target on native, JS and wasm-gc, both debug and release, with --deny-warn. The core integration branch separately passes 121 regex tests per target in release mode. New tests cover cache flushes during scanning and at EOF, saved result ownership, accepted candidates, sliced views, first-history priority and final empty captures; the generation-wrap test also resets the target-dedup stamps. No existing snapshots were changed.

The two optimization families are the EOF-free character loop and flat state keys/target deduplication/cache budgeting. They were measured together here; this run does not isolate each family's contribution. The cache budget counts Int cells in keys and transition rows and is not a whole-process RSS cap.

## Reproduction

Build benchmarks with the same compiler and matching standard library in all implementations. The three baseline snapshots use the engine_eval package from the previous public-API evaluation; this repository uses benchmarks with the same driver. Then run:

```sh
python3 scripts/compare.py --main-root /path/to/main-snapshot --before-root /path/to/before-snapshot --claude-root /path/to/claude-snapshot --out /tmp/lazy-tdfa-results
```

Use scripts/measure_memory.py with the same three snapshot roots and an output JSON path to reproduce the fresh-process native RSS measurements.

Run no builds or tests concurrently with the timing benchmark. The runner refuses to overwrite an existing result directory. See metadata.json for exact versions and measurement phases. The evidence is from one machine and three rounds; numerical precision is not a statistical confidence interval.
