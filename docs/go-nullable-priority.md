# Go nullable repetition priority

The engine now uses Go's ordered-automaton policy for nullable repetition.
This deliberately changes some match ends and capture endpoints from the
core implementation used for extraction. It does not change the public API
or adopt unrelated Go regex syntax.

| Pattern | Input | Group 1 |
| --- | --- | --- |
| `^(a?)*b$` | `aab` | `a`, `[1,2)` |
| `^(a?)*b$` | `b` | empty, `[0,0)` |
| `^(a?)*?b$` | `b` | absent |
| `^(a?){0,3}b$` | `aab` | empty, `[2,2)` |
| `(a*)*` | `aa` | `aa`, `[0,2)` |

The implementation follows Go's Thompson construction: nullable `R*` is
`(R+)?`, with the written greediness on both choices. Every loop iteration
returns to the same body PCs. Ordered closure retains the first arrival at a
PC and input position, so another empty traversal cannot replace its capture
history. Mandatory prefix copies and finite optional copies have separate
PCs. This is not a blanket rule to discard empty captures.

`scripts/nullable_oracle.go` independently computes 714 full-match and capture
expectations with Go 1.26.2. The generated MoonBit test checks all endpoints,
converts byte offsets to UTF-16 offsets, and repeats each execution to exercise
cached transitions. Coverage includes greedy/lazy stars and pluses, minimum
counts, finite copies, ordered empty alternatives, suffix retries, nesting,
missing groups and non-BMP text. A separate whitebox test forces cache flushes
for greedy/lazy repetitions with minimum counts 0 through 3.

The historical digest changes are restricted to three of the 217 AST patterns
and three of the 13 UTF-16 patterns. The AST entries are `(a*)*`,
`(?:b*?|b+)*`, and `(?:(?:a*?){1,3}?)+`; the UTF-16 entries are `^(.?)*$`,
`(a|(😀)?)*`, and `((a?)*)*`. Each is also covered by the independent Go
oracle. The snapshot update follows the reproduction and implementation
commits. Historical benchmark samples remain unchanged and describe their
original measured revision, before this semantics change.

Validation: `moon check --deny-warn`, `moon info`, `moon fmt --check`, and all
231 tests on native, JS and wasm-gc in debug and release pass. The public
generated interface is unchanged.
