# lazy-tdfa

Standalone MoonBit regex engine extracted from the core lazy tagged DFA implementation at b7625ab222e59307f225350b13c76540f3447a11. Its public Regex API follows core string/regex, with leftmost-first matching and preserved capture semantics, including the final empty iteration of greedy nullable repetitions.

This repository retains the upstream Apache-2.0 license and copyright notices. It contains the tagged engine, parser and public API, without the derivative engine or the rest of core.

Import `hackwaly/lazy-tdfa` with an alias such as `@regex`. Construct patterns with `@regex.Regex(pattern)` or `@regex.Regex::unsafe_from_string(pattern)`; use execute, find, split and replace_by as in core. Regex literals are compiler integrations and are not promised for this external package.

```sh
moon check
moon info
moon fmt
moon test --target native,js,wasm-gc
```

## Optimizations

The scanner processes EOF outside the hot character loop and caches invariant
lookups locally. Lazy DFA states use flat Int-array keys with interned category
IDs and first-priority target deduplication. A soft cache budget of `1 << 22`
Int cells counts state keys and transition rows. When a new state exceeds the
budget, the DFA cache is cleared, start IDs invalidated, and live register
values preserved so the current match can continue. The budget is internal,
not a promise about whole-process RSS; transient allocations and one oversized
state are not bounded by it.

Greedy nullable repeats still retain their final empty capture: `^(a?)*b$`
on `aab` captures the empty string in group 1. This deliberately preserves the
core baseline used for the extraction, rather than adopting the different
nullable capture behavior observed in bobzhang/tdfa.

See [engine design](internal/engine/README.md) for invariants and test history.
