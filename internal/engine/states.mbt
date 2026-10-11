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
fn tagged_assertion(a : Assertion, prev : Category, next : Category) -> Bool {
  match a {
    StartOfInput => prev.intersects(Category::inexistant())
    EndOfInput => next.intersects(Category::inexistant())
    StartOfLine => prev.intersects(Category::inexistant_or_newline())
    EndOfLine => next.intersects(Category::inexistant_or_newline())
    StartOfWord =>
      prev.intersects(Category::inexistant_or_non_word_end()) &&
      next.intersects(Category::word())
    EndOfWord =>
      prev.intersects(Category::word()) &&
      next.intersects(Category::inexistant_or_non_word_start())
    NotWordBoundary =>
      (prev.intersects(Category::word()) && next.intersects(Category::word())) ||
      (
        prev.intersects(Category::inexistant_or_non_word_end()) &&
        next.intersects(Category::inexistant_or_non_word_start())
      )
  }
}

///|
fn Regex::width(self : Regex) -> Int {
  self.repr.length() + 1
}

///|
// Clearing the DFA must preserve registers: the transition being built may
// still refer to values written before the flush. State IDs and start rows,
// unlike register IDs, become invalid and must all be discarded together.
fn Regex::flush_cache(self : Regex) -> Unit {
  self.cache.clear()
  self.states.clear()
  self.starts.fill(-1)
  self.next.fill(-1)
  self.actions.fill(0)
  self.cache_words = 0
}

///|
fn Regex::insert_state(self : Regex, key : FixedArray[Int]) -> Int {
  let index = self.states.length()
  self.states.push(key)
  let width = self.width()
  let required = (index + 1) * width
  if required > self.next.length() {
    let size = Int::max(self.next.length() * 2, Int::max(required, width * 4))
    self.next = FixedArray::make_and_blit(
      self.next,
      allocate_len=size,
      init=-1,
      len=self.next.length(),
    )
    self.actions = FixedArray::make_and_blit(
      self.actions,
      allocate_len=size,
      init=0,
      len=self.actions.length(),
    )
  }
  let state = if key.length() == 1 || key[1] == 0 {
    -index - 2
  } else {
    index * width
  }
  self.cache.set(key, state)
  self.cache_words += key.length() + 2 * width
  state
}

///|
fn Regex::start_state(self : Regex, context : Int) -> Int {
  let cached = self.starts[context]
  if cached != -1 {
    return cached
  }
  let key = FixedArray::make(2 + self.groups.length() * 2, -1)
  key[0] = context
  key[1] = self.start
  let state = match self.cache.get(key) {
    Some(state) => state
    None => {
      if self.cache_words + key.length() + 2 * self.width() > self.cache_budget {
        self.flush_cache()
      }
      self.insert_state(key)
    }
  }
  self.starts[context] = state
  state
}

///|
// Ordered DFS closure and target deduplication keep the first path to each
// PC. Surviving tags retain their register identities across transitions.
fn Regex::build_edge(self : Regex, base : Int, symbol : Int) -> Int {
  let width = self.width()
  let key = self.states[base / width]
  let ntags = self.groups.length() * 2
  let stride = ntags + 1
  let count = (key.length() - 1) / stride
  let at_end = symbol == self.repr.length()
  let next_cat = if at_end {
    Category::inexistant()
  } else {
    self.categories[symbol]
  }
  let prev_cat = self.contexts[key[0]]
  self.generation += 1
  if self.generation == 0 {
    self.seen.fill(0)
    self.targeted.fill(0)
    self.generation = 1
  }
  let generation = self.generation
  let nodes = self.nodes
  let seen = self.seen
  let targeted = self.targeted
  let stack : Array[(Int, FixedArray[Int])] = []
  let pcs : Array[Int] = []
  let histories : Array[FixedArray[Int]] = []
  for i = count - 1; i >= 0; i = i - 1 {
    let row = 1 + i * stride
    let tags = FixedArray::make(ntags, -1)
    key.blit_to(tags, len=ntags, src_offset=row + 1)
    stack.push((key[row], tags))
  }
  while stack.pop() is Some((pc, tags)) {
    if seen[pc] == generation {
      continue
    }
    seen[pc] = generation
    match nodes[pc] {
      Accept => {
        pcs.push(pc)
        histories.push(tags)
        // An accepted candidate remains the lowest-priority surviving row.
        break
      }
      Chr(chars, next) =>
        if !at_end && targeted[next] != generation && chars.contains(symbol) {
          targeted[next] = generation
          pcs.push(next)
          histories.push(tags)
        }
      Split(alts) =>
        for i = alts.length() - 1; i >= 0; i = i - 1 {
          stack.push((alts[i], tags))
        }
      Assert(a, next) =>
        if tagged_assertion(a, prev_cat, next_cat) {
          stack.push((next, tags))
        }
      Tag(tag, next) => {
        let tags = tags.copy()
        tags[tag] = -2 // SET to current cursor on this edge.
        stack.push((next, tags))
      }
    }
  }
  // All tags set by this closure name the same cursor. Allocate the lowest
  // register not read by any surviving row, including an accepted candidate.
  let used = FixedArray::make(self.max_registers + 1, false)
  let mut needs_write = false
  for tags in histories {
    for source in tags {
      if source == -2 {
        needs_write = true
      } else if source >= 0 {
        used[source] = true
      }
    }
  }
  let mut slot = 0
  if needs_write {
    while used[slot] {
      slot += 1
    }
    self.max_registers = Int::max(self.max_registers, slot + 1)
  }
  self.built_action = if needs_write { slot + 1 } else { 0 }
  let dest = FixedArray::make(1 + pcs.length() * stride, -1)
  dest[0] = if at_end { 0 } else { self.symbol_contexts[symbol] }
  for i, pc in pcs {
    let row = 1 + i * stride
    dest[row] = pc
    for tag, source in histories[i] {
      dest[row + 1 + tag] = if source == -2 { slot } else { source }
    }
  }
  let mut flushed = false
  let target = match self.cache.get(dest) {
    Some(state) => state
    None => {
      if self.cache_words + dest.length() + 2 * width > self.cache_budget &&
        !self.states.is_empty() {
        self.flush_cache()
        flushed = true
      }
      self.insert_state(dest)
    }
  }
  if !flushed {
    let edge = base + symbol
    self.next[edge] = target
    self.actions[edge] = self.built_action
  }
  target
}
