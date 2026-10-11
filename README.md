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
