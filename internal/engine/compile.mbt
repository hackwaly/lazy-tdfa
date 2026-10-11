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
/// Compile a pattern into the lazy tagged automaton.
///
/// Uses ordered First semantics for alternatives and search attempts.
pub fn compile(profile~ : Profile, ast : Pattern) -> Regex {
  compile_with_cache_budget(profile~, ast, DEFAULT_CACHE_WORDS)
}

///|
fn compile_with_cache_budget(
  profile~ : Profile,
  ast : Pattern,
  cache_budget : Int,
) -> Regex {
  guard cache_budget > 0 else { panic() }
  let groups : Array[String?] = [None]
  fn number(ast : Pattern) -> TaggedPattern {
    match ast.desc {
      Char(chars) => Chr(chars)
      Sequence(parts) =>
        Seq(Array::makei(parts.length(), i => number(parts[i])))
      Alternation(parts) =>
        Alt(Array::makei(parts.length(), i => number(parts[i])))
      Quantifier(q, body) => Rep(q, number(body))
      Capture(name~, body) => {
        let group = groups.length()
        groups.push(name)
        Cap(group, number(body))
      }
      Assertion(a) => Assert(a)
    }
  }
  let pattern = number(ast)
  let symbol_map = @symbol_map.new()
  // Refine character classes and assertion categories into disjoint symbols.
  symbolize(profile~, symbol_map~, ast)
  // The search loop consumes any valid character before trying a new start.
  if !ast.is_anchored() {
    symbolize(profile~, symbol_map~, char(profile.valid))
  }
  let (symbols, repr) = symbol_map.finalize(profile.lb, profile.ub)
  let nodes : Array[TaggedNode] = [Accept]
  fn add(node : TaggedNode) -> Int {
    let pc = nodes.length()
    nodes.push(node)
    pc
  }
  fn nullable(pat : TaggedPattern) -> Bool {
    match pat {
      Chr(_) => false
      Seq(parts) => parts.all(nullable)
      Alt(parts) => parts.any(nullable)
      Cap(_, body) => nullable(body)
      Assert(_) => true
      Rep(q, body) => q.min == 0 || nullable(body)
    }
  }
  fn build(pat : TaggedPattern, next : Int) -> Int {
    match pat {
      Chr(chars) => add(Chr(symbols.map_set(chars), next))
      Seq(parts) => {
        let mut entry = next
        for i = parts.length() - 1; i >= 0; i = i - 1 {
          entry = build(parts[i], entry)
        }
        entry
      }
      Alt(parts) => add(Split(parts.map(p => build(p, next))))
      Cap(group, body) => {
        let close = add(Tag(group * 2 + 1, next))
        let inner = build(body, close)
        add(Tag(group * 2, inner))
      }
      Assert(a) => add(Assert(a, next))
      Rep(q, body) => {
        let mut entry = next
        match q.max {
          None => {
            let repeat_entry = add(Split([]))
            let inner = build(body, repeat_entry)
            let choices = if q.mode is Greedy {
              [inner, next]
            } else {
              [next, inner]
            }
            nodes[repeat_entry] = Split(choices)
            // All loop iterations share the same body PCs. Ordered closure
            // keeps their first arrival at each input position, bounding empty
            // cycles without adding a separate final empty capture.
            if q.min == 0 {
              // A nullable star is (body+)? with matching modes on both
              // choices. Its initial choice must be distinct from the loop
              // choice, so the first empty iteration can reach the suffix.
              entry = if nullable(body) {
                add(Split(choices))
              } else {
                repeat_entry
              }
            } else {
              entry = inner
              // The final mandatory copy is the shared loop body. Earlier
              // mandatory copies have distinct PCs, even for empty matches.
              for _ in 1..<q.min {
                entry = build(body, entry)
              }
            }
          }
          Some(max) => {
            for _ in 0..<(max - q.min) {
              let inner = build(body, entry)
              entry = add(
                Split(
                  if q.mode is Greedy {
                    [inner, entry]
                  } else {
                    [entry, inner]
                  },
                ),
              )
            }
            for _ in 0..<q.min {
              entry = build(body, entry)
            }
          }
        }
        entry
      }
    }
  }
  let end = add(Tag(1, 0))
  let body = build(pattern, end)
  let captured = add(Tag(0, body))
  let start = if ast.is_anchored() {
    captured
  } else {
    let search = add(Split([]))
    let advance = add(Chr(symbols.map_set(profile.valid), search))
    nodes[search] = Split([captured, advance])
    search
  }
  let categories = repr.map(profile.category)
  let contexts : Array[Category] = [Category::inexistant()]
  let symbol_contexts = categories.map(cat => {
    match contexts.search(cat) {
      Some(index) => index
      None => {
        let index = contexts.length()
        contexts.push(cat)
        index
      }
    }
  })
  {
    groups: ReadOnlyArray::from_array(groups),
    nodes: ReadOnlyArray::from_array(nodes),
    start,
    symbols,
    repr,
    categories,
    contexts: ReadOnlyArray::from_array(contexts),
    symbol_contexts,
    starts: FixedArray::make(contexts.length(), -1),
    cache: HashMap([]),
    states: [],
    next: [],
    actions: [],
    registers: FixedArray::make(8, -1),
    max_registers: 0,
    built_action: 0,
    cache_words: 0,
    cache_budget,
    seen: FixedArray::make(nodes.length(), 0),
    targeted: FixedArray::make(nodes.length(), 0),
    generation: 0,
  }
}
