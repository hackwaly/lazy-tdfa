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
/// Capture endpoints relative to the matched StringView, independent of the
/// mutable register buffer owned by the compiled regex.
struct MatchResult(Array[Int]) derive(@debug.Debug)

///|
/// Access capture `group` information.
pub fn MatchResult::group(self : MatchResult, index : Int) -> (Int, Int)? {
  guard index >= 0 && index < self.0.length() / 2 else { None }
  let start_pos = self.0.get(index * 2)
  guard start_pos is Some(start_pos) && start_pos >= 0 else { None }
  let end_pos = self.0[index * 2 + 1]
  guard end_pos >= 0 else { panic() }
  Some((start_pos, end_pos))
}

///|
fn Regex::ensure_registers(self : Regex) -> Unit {
  let required = self.max_registers + 1
  if required > self.registers.length() {
    let size = Int::max(self.registers.length() * 2, required + 8)
    let registers = FixedArray::make(size, -1)
    self.registers.blit_to(registers, len=self.registers.length())
    self.registers = registers
  }
}

///|
/// Executes this compiled regex and returns the first match from `last_index`.
pub fn Regex::execute(
  self : Regex,
  input : StringView,
  last_index : Int,
) -> MatchResult? {
  guard last_index >= 0 && last_index <= input.length() else { panic() }
  let symbols = self.symbols
  let context = if last_index == 0 {
    0
  } else {
    self.symbol_contexts[symbols.map(input.unsafe_get(last_index - 1).to_int())]
  }
  let mut base = self.start_state(context)
  let mut next = self.next
  let mut actions = self.actions
  let mut registers = self.registers
  let data = input.data()
  let shift = input.start_offset()
  let mut pos = shift + last_index
  let end = shift + input.length()
  let mut stop = -1
  while pos < end {
    let symbol = symbols.map(data.unsafe_get(pos).to_int())
    let edge = base + symbol
    let mut target = next.unsafe_get(edge)
    if target < 0 {
      if target == -1 {
        target = self.build_edge(base, symbol)
        self.ensure_registers()
        next = self.next
        actions = self.actions
        registers = self.registers
        registers.unsafe_set(self.built_action, pos)
        if target >= 0 {
          base = target
          pos += 1
          continue
        }
      } else {
        registers.unsafe_set(actions.unsafe_get(edge), pos)
      }
      stop = target
      break
    }
    registers.unsafe_set(actions.unsafe_get(edge), pos)
    base = target
    pos += 1
  }
  if stop == -1 {
    let edge = base + self.repr.length()
    stop = next.unsafe_get(edge)
    if stop == -1 {
      stop = self.build_edge(base, self.repr.length())
      self.ensure_registers()
      registers = self.registers
      registers.unsafe_set(self.built_action, pos)
    } else {
      registers.unsafe_set(actions.unsafe_get(edge), pos)
    }
  }
  // The EOF closure has no consuming rows and always returns a terminal ID.
  let key = self.states[-stop - 2]
  if key.length() == 1 {
    None
  } else {
    let ntags = self.groups.length() * 2
    let result = Array::make(ntags, -1)
    for tag in 0..<ntags {
      let reg = key[2 + tag]
      if reg >= 0 {
        result[tag] = registers[reg + 1] - shift
      }
    }
    Some(MatchResult(result))
  }
}
