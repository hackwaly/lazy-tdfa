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
let test_profile : Profile = Profile(
  valid=RecharSet::char_range(0, 0xFFFF),
  word=RecharSet::char_range('a', 'z'),
  category=c => {
    match c {
      'a'..='z' => Category::word()
      '\n' => Category::newline() + Category::not_word()
      _ => Category::not_word()
    }
  },
)

///|
test "lazy states and transitions are reused" {
  let a = char(RecharSet::char('a'))
  let body = capture(quantifier(a, { min: 0, max: None, mode: Greedy, }))
  let re = compile(
    profile=test_profile,
    seq([start_of_input, body, end_of_input]),
  )
  inspect(re.states.length(), content="0")
  guard re.execute("aaaa", 0) is Some(saved) else { fail("missing match") }
  let state_count = re.states.length()
  let generation = re.generation
  let registers = re.max_registers
  for _ in 0..<20 {
    @test.assert_eq(
      re.execute("aaaa", 0).map(m => m.group(1)),
      Some(Some((0, 4))),
    )
  }
  @test.assert_eq(re.states.length(), state_count)
  @test.assert_eq(re.generation, generation)
  @test.assert_eq(re.max_registers, registers)
  ignore(re.execute("", 0))
  ignore(re.execute("aa", 0))
  // Results own endpoints rather than the mutable register buffer.
  @debug.debug_inspect(saved.group(1), content="Some((0, 4))")
  @debug.debug_inspect(saved.group(0x7FFF_FFFF), content="None")
  @debug.debug_inspect(saved.group(-1), content="None")
}

///|
test "closure generations reset before reusing the zero stamp" {
  let a = char(RecharSet::char('a'))
  let b = char(RecharSet::char('b'))
  let c = char(RecharSet::char('c'))
  let re = compile(profile=test_profile, seq([start_of_input, a, alt([b, c])]))
  ignore(re.execute("ab", 0))
  re.generation = -1
  re.seen.fill(1)
  re.targeted.fill(1)
  @debug.debug_inspect(
    re.execute("ac", 0).map(m => m.group(0)),
    content="Some(Some((0, 2)))",
  )
  @test.assert_eq(re.generation > 0, true)
}

///|
test "tiny cache survives flushes during scanning and at EOF" {
  let a = char(RecharSet::char('a'))
  let pattern = seq([
    start_of_input,
    capture(quantifier(a, { min: 1, max: None, mode: Greedy, })),
    char(RecharSet::char('b')),
    end_of_input,
  ])
  let re = compile_with_cache_budget(profile=test_profile, pattern, 1)
  for input in ["ab", "aaaaab", "b", "aa", "ab", ""] {
    let expected = compile(profile=test_profile, pattern).execute(input, 0)
    let actual = re.execute(input, 0)
    for group in 0..<2 {
      @test.assert_eq(
        actual.map(m => m.group(group)),
        expected.map(m => m.group(group)),
      )
    }
    // One key may itself exceed the soft budget. With a budget of one,
    // every newly inserted key replaces the previous one.
    @test.assert_eq(re.states.length(), 1)
  }
}

///|
test "cache flush preserves accepted candidates and view-relative captures" {
  let a = char(RecharSet::char('a'))
  let pattern = alt([capture(seq([a, char(RecharSet::char('b'))])), capture(a)])
  let re = compile_with_cache_budget(profile=test_profile, pattern, 1)
  let view = "--xa!++"[2:5]
  guard re.execute(view, 0) is Some(saved) else { fail("missing candidate") }
  @test.assert_eq(saved.group(0), Some((1, 2)))
  @test.assert_eq(saved.group(1), None)
  @test.assert_eq(saved.group(2), Some((1, 2)))
  ignore(re.execute("ab", 0))
  @test.assert_eq(saved.group(2), Some((1, 2)))
  @test.assert_eq(re.execute(view, 2).map(m => m.group(0)), None)
}

///|
test "flat kernels keep the first history for duplicate targets" {
  let a = char(RecharSet::char('a'))
  let pattern = seq([
    start_of_input,
    alt([capture(a), capture(a)]),
    end_of_input,
  ])
  let re = compile_with_cache_budget(profile=test_profile, pattern, 1)
  guard re.execute("a", 0) is Some(result) else { fail("missing match") }
  @test.assert_eq(result.group(1), Some((0, 1)))
  @test.assert_eq(result.group(2), None)
}

///|
test "cache flush preserves Go nullable capture priority" {
  let a = char(RecharSet::char('a'))
  let optional = quantifier(a, { min: 0, max: Some(1), mode: Greedy, })
  let pattern = seq([
    start_of_input,
    quantifier(capture(optional), { min: 0, max: None, mode: Greedy, }),
    char(RecharSet::char('b')),
    end_of_input,
  ])
  let re = compile_with_cache_budget(profile=test_profile, pattern, 1)
  for n in 0..<12 {
    guard re.execute("a".repeat(n) + "b", 0) is Some(result) else {
      fail("missing match")
    }
    let span = if n == 0 { (0, 0) } else { (n - 1, n) }
    @test.assert_eq(result.group(1), Some(span))
  }
}
