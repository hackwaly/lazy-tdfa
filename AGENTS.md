# Development

Preserve core first-match behavior, including the final empty capture in greedy nullable repetitions. Keep public API compatible with core string/regex. Internal compiler hooks are not public stability promises.

Run `moon check`, `moon info`, `moon fmt`, and `moon test --target native,js,wasm-gc` before committing. Match results must own endpoints; cache flushes must preserve live registers and invalidate every start/transition state ID. Add regression coverage when changing cache handling or capture priority. Do not update existing snapshots to hide behavior changes.

Benchmarks must use the same compiler, release mode, inputs and result observations for all implementations. Separate Regex parsing, construction plus first match, and warmed matching. Keep non-equivalent capture cases out of cross-engine aggregate rankings.
