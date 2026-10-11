///|
priv struct Case {
  name : String
  pattern : String
  inputs : Array[String]
  groups : Int
  op : String
}

///|
fn large_pattern() -> String {
  let parts : Array[String] = []
  for i in 0..<38 {
    let index = "\{i}".pad_start(3, '0')
    parts.push(
      ".*(?:src_\{index}|tmp_\{index}|cache_\{index})\\.(?:log|tmp|cache)$",
    )
  }
  parts.join("|")
}

///|
fn make_case(name : String) -> Case {
  let n = if name.has_suffix("_short") { 256 } else { 4096 }
  let (pattern, inputs, groups, op) = match name {
    "scan_1mb" => ("aa?b", ["a".repeat(1024 * 1024 - 1) + "b"], 0, "execute")
    "literal_miss" => ("needle", ["x".repeat(300 * 1024)], 0, "execute")
    "phone_lines" =>
      (
        "([(][0-9]{3}[)]|[0-9]{3}) [0-9]{3}[ \\-][0-9]{4}",
        [
          "datafile for phone numbers", "", "(111) 111 1111", "111 222-2222", "(111) 333-3333",
          "111 444 4444", "foo (111) 555 5555", "foo 111 666-6666", "foo (111) 777-7777",
          "foo 111 888 8888", "foo (111) 999 9999 bar", "foo 111 000-0000 bar", "2(212) 222 2222",
          "2232 222-2222", "(242) 222-22222", "2252 222 2222", "foo (262) 2222222",
          "foo 272 2222222", "foo (282) 222-22227", "foo 292 222 22222", "foo (202).222 2222 bar",
          "foo 211@22222222 bar", "foo (213 222-2222 bar", "foo 214) 222 2222 bar",
        ],
        1,
        "execute",
      )
    "large_pattern" => {
      let inputs : Array[String] = []
      for i in 0..<20000 {
        if i % 5 == 0 {
          let index = "\{i % 38}".pad_start(3, '0')
          let stem = if i % 3 == 0 {
            "src"
          } else if i % 3 == 1 {
            "tmp"
          } else {
            "cache"
          }
          let ext = if i % 3 == 0 {
            "log"
          } else if i % 3 == 1 {
            "tmp"
          } else {
            "cache"
          }
          inputs.push("repo/subdir/\{stem}_\{index}.\{ext}")
        } else {
          inputs.push("repo/subdir/other_\{i}.txt")
        }
      }
      (large_pattern(), inputs, 0, "execute")
    }
    "find_digits" =>
      ("[[:digit:]]+", ["abc123 def456 ghi789 ".repeat(256)], 0, "find")
    "find_emails" =>
      (
        "([a-z]+)@([a-z]+)\\.com",
        ["noise alice@example.com bob@test.com ! ".repeat(128)],
        2,
        "find",
      )
    "find_words" =>
      ("\\b([a-z]+)\\b", ["alpha beta gamma delta! ".repeat(128)], 1, "find")
    "lazy_search" =>
      (".*?(a+)b", ["x".repeat(128) + "a".repeat(128) + "b"], 1, "execute")
    "anchored_short" =>
      (
        "^([a-z]+)-([0-9]+)$",
        ["abc-123", "xyz-4567", "not a match"],
        2,
        "execute",
      )
    "split" => ("[,; ]+", ["alpha,beta;gamma delta ".repeat(128)], 0, "split")
    "replace" => ("[[:digit:]]+", ["abc123 def456 ".repeat(256)], 0, "replace")
    "unicode_class" =>
      ("([α-ω😀-🙏]+)", ["xαβγ😀🙏 y ".repeat(256)], 1, "find")
    "cold_email" =>
      ("^([a-z]+)@([a-z]+)\\.com$", ["alice@example.com"], 2, "execute")
    "cold_large" =>
      (large_pattern(), ["repo/subdir/cache_037.cache"], 0, "execute")
    "dense_short" | "dense_long" =>
      (
        "^(a+)(b+)(c+)$",
        ["a".repeat(n) + "b".repeat(n) + "c".repeat(n)],
        3,
        "execute",
      )
    "no_capture_short" | "no_capture_long" =>
      ("^a+b$", ["a".repeat(n) + "b"], 0, "execute")
    "many_captures" =>
      (
        "^" + "(a?)".repeat(32) + "b*$",
        ["a".repeat(32) + "b".repeat(4096)],
        32,
        "execute",
      )
    "nullable" => ("^(a?)*b$", ["a".repeat(4096) + "b"], 1, "execute")
    "delayed_capture" => ("^(a+)a{32}$", ["a".repeat(4096)], 1, "execute")
    "slot_stress" => ("(a)(?:a{256}){9}", ["a".repeat(2400)], 1, "execute")
    _ => abort("Unknown case")
  }
  { name, pattern, inputs, groups, op, }
}

///|
fn observe(m : @string.MatchResult, groups : Int) -> Int {
  let mut result = m.before().length() * 3 +
    m.content().length() * 7 +
    m.after().length()
  for i in 1..<=groups {
    result += match m.group(i) {
      Some(g) => g.start_offset() * 3 + g.length() * 7
      None => -1
    }
  }
  result
}

///|
fn execute(c : Case, re : @string.Regex) -> Int {
  let mut checksum = 0
  for input in c.inputs {
    match c.op {
      "execute" =>
        checksum += match re.execute(input) {
          Some(m) => observe(m, c.groups)
          None => -1
        }
      "find" =>
        for m in re.find(input) {
          checksum += observe(m, c.groups)
        }
      "split" =>
        for s in re.split(input) {
          checksum += s.length()
        }
      "replace" => checksum += re.replace_by(input, _ => "#").length()
      _ => abort("Unknown operation")
    }
  }
  checksum
}

///|
fn main {
  let args = @env.args()
  let c = make_case(args[args.length() - 2])
  let phase = args[args.length() - 1]
  let re = @string.Regex::unsafe_from_string(c.pattern)
  let expected = execute(c, re)
  if phase == "memory" {
    println("MEMORY,\{c.name},\{expected}")
    return
  }
  let keeper = @bench.Bench()
  let run = fn() {
    let value = match phase {
      "hot" => execute(c, re)
      "cold" => execute(c, @string.Regex::unsafe_from_string(c.pattern))
      "parse" => {
        let candidate = @string.Regex::unsafe_from_string(c.pattern)
        keeper.keep(candidate)
        expected
      }
      _ => abort("Unknown phase")
    }
    guard value == expected else { abort("Inconsistent match checksum") }
    value
  }
  // Warm up JIT code and lazy transitions before hot measurements.
  for _ in 0..<5 {
    ignore(run())
  }
  let count = for count = 1 {
    let start = @bench.monotonic_clock_start()
    for _ in 0..<count {
      ignore(run())
    }
    let elapsed = @bench.monotonic_clock_end(start)
    if elapsed >= 100000.0 || count >= 1048576 {
      break count
    }
    continue count * 2
  }
  for sample in 0..<3 {
    let mut sink = 0
    let start = @bench.monotonic_clock_start()
    for _ in 0..<count {
      sink += run()
    }
    let us = @bench.monotonic_clock_end(start) / count.to_double()
    println(
      "ROW,\{c.name},\{phase},\{sample},\{count},\{us},\{expected},\{sink}",
    )
  }
}
