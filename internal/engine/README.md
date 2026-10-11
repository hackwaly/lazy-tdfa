# Lazy Tagged Regex Engine

The standalone Regex API compiles Unicode patterns to UTF-16 and uses this
engine for matching. The parser, AST, character sets and symbol partition are
local packages. No derivative engine is included.

## Matching Semantics

Alternatives use ordered First semantics. Greedy repetitions visit the body
before their exit; non-greedy repetitions visit the exit first. Search attempts
are ordered from the earliest input position. The engine supports captures,
bounded and unbounded repetitions, and input, line and word assertions.

Scoped Longest and Shortest preferences are absent from the internal AST.
They were not exposed by the public regex parser or combinators. UTF-16
character-class lowering uses disjoint alternatives, so it does not require
a scoped preference.

## Construction and Execution

Compilation builds an ordered Thompson NFA with explicit capture tags. DFA
states and transitions are constructed only when execution encounters them.
Character classes and assertion categories share the existing symbol partition
implementation. EOF has a separate transition column.

A state key is one flat Int array: the previous character category ID, then
ordered rows of NFA node and tag register identities. Categories are interned
during compilation. Duplicate consuming targets retain their first history.
Ordered epsilon closure retains the first visit to each node. When it reaches
an accepted candidate, lower-priority threads are discarded; higher-priority
consuming threads remain so greedy continuations can supersede that candidate.

Unbounded repetitions share one body graph across loop iterations. A nullable
star uses a plus inside an optional choice, with the written greediness on
both choices, following Go's ordered-automaton priority. Ordered closure keeps
the first arrival at each PC and input position, suppressing empty cycles
without a separate final empty-capture projection. Earlier mandatory copies
and finite optional copies have distinct PCs and can still capture empty text.

Tag histories contain register identities, not input offsets. All tags written
on one transition refer to the same cursor, so they share one register. That
register is chosen from identities unused by the destination's surviving tags.
Existing identities are retained, avoiding runtime COPY programs. Register zero
is a disposable sink for transitions without tag writes.

Cached transitions contain an encoded destination and one register action.
Running destinations are transition-row bases; terminal destinations encode a
state index as `-index - 2`; `-1` is reserved for an uncomputed transition.
The hot loop scans with `while pos < end`; EOF is handled once afterwards.
Execution refreshes table references after constructing an edge, since edge
construction can grow both tables and the register buffer.

A soft cache budget of `1 << 22` Int cells counts keys and both transition
rows. On a new state exceeding that budget, the DFA cache is discarded while
live registers are preserved. The current transition returns its new target
and action directly: its source row may no longer exist after the flush.
All cached start IDs are invalidated together. Table allocations are reused;
NFA memory, temporary closure work, allocator overhead, and a single state
larger than the budget are outside this accounting. It is not an RSS limit.

Match results copy endpoints out of the register buffer and subtract the
StringView's backing-string offset. Subsequent executions cannot alter earlier
results. Cache and register storage is mutable; executions on one compiled
regex must remain synchronous.

## Validation

The public API runs the inherited core regex tests. Before removal, 217 fixed
and generated patterns were checked against the derivative engine over all
short inputs and search offsets, including capture endpoints, nullable
repetitions, assertions and repeated cache use. Two independent rolling
digests per pattern record those results as regression baselines; nullable
entries are updated for the deliberate switch to Go's capture priority.
Unicode lowering on sliced StringViews has a separate regression baseline.
nullable_go_test.mbt is generated from Go's independent regexp implementation
and checks complete match and capture endpoints, including UTF-16 offsets.
Direct engine tests check lazy cache reuse and large live-register counts.

Use `Regex(pattern)` for this standalone package. A compiler regex literal
constructs core's Regex and does not select this engine.
