// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
priv enum TaggedPattern {
  Chr(RecharSet)
  Seq(Array[TaggedPattern])
  Alt(Array[TaggedPattern])
  Rep(Quantifier, TaggedPattern)
  Cap(Int, TaggedPattern)
  Assert(Assertion)
}

///|
priv enum TaggedNode {
  Chr(RecharSet, Int)
  Split(Array[Int])
  Tag(Int, Int)
  Assert(Assertion, Int)
  Accept
}

///|
// The lazy cache budget counts Int cells in state keys and transition rows.
// It excludes the NFA, transient closure work and allocator overhead.
const DEFAULT_CACHE_WORDS : Int = 1 << 22

///|
struct Regex {
  groups : ReadOnlyArray[String?]
  nodes : ReadOnlyArray[TaggedNode]
  start : Int
  symbols : @symbol_map.Table
  repr : ReadOnlyArray[Rechar]
  categories : ReadOnlyArray[Category]
  // Context IDs make the complete state key a flat Int array. Context zero
  // denotes outside the input; all other IDs name character categories.
  contexts : ReadOnlyArray[Category]
  symbol_contexts : ReadOnlyArray[Int]
  starts : FixedArray[Int]
  // key[0] is the context ID, followed by rows of [pc, tag0, tag1, ...].
  // Tags name logical registers (-1 is absent), never concrete input offsets.
  cache : @hashmap.HashMap[FixedArray[Int], Int]
  states : Array[FixedArray[Int]]
  // State rows include one EOF column. -1 means an uncomputed edge;
  // nonnegative targets are row bases, and -index-2 denotes a terminal state.
  mut next : FixedArray[Int]
  // Each edge writes the cursor to this physical register (zero is a sink).
  mut actions : FixedArray[Int]
  mut registers : FixedArray[Int]
  mut max_registers : Int
  // A cache flush invalidates the source row during build_edge. Return its
  // destination directly and keep its action here instead of reloading it.
  mut built_action : Int
  mut cache_words : Int
  cache_budget : Int
  seen : FixedArray[Int]
  targeted : FixedArray[Int]
  mut generation : Int
}

///|
/// Return the capture names for this compiled regex.
pub fn Regex::group_names(self : Regex) -> ReadOnlyArray[String?] {
  self.groups
}
