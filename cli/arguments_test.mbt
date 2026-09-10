///|
fn rejected(args : Array[String]) -> @model.Diagnostic raise {
  try parse_arguments(args) catch {
    @model.FirmwareError(d) => d
  } noraise {
    _ => fail("expected argument rejection")
  }
}

///|
test "help requires no files" {
  assert_true(parse_arguments([]) is Help(""))
  assert_true(parse_arguments(["inspect", "--help"]) is Help("inspect"))
}

///|
test "version is explicit request" {
  assert_true(parse_arguments(["--version"]) is Version)
}

///|
test "unknown command is error" {
  assert_eq(rejected(["wat"]).code, InvalidOption)
}

///|
test "missing input is error" {
  assert_eq(rejected(["inspect"]).code, InvalidOption)
}

///|
test "missing output is error" {
  assert_eq(rejected(["convert", "a.hex"]).code, InvalidOption)
}

///|
test "convert positional output" {
  assert_true(
    parse_arguments(["convert", "a.hex", "b.srec"])
    is Run({ output: Some("b.srec"), .. }),
  )
}

///|
test "convert binary base option" {
  assert_true(
    parse_arguments([
      "convert", "a.bin", "b.hex", "--base-address", "0x08000000",
    ])
    is Run({ base_address: Some(0x08000000L), .. }),
  )
}

///|
test "duplicate option aliases rejected" {
  assert_eq(
    rejected(["convert", "a.hex", "-o", "b.hex", "--output", "c.hex"]).code,
    InvalidOption,
  )
}

///|
test "flag does not swallow assigned value" {
  assert_eq(rejected(["inspect", "a.hex", "--json=yes"]).code, InvalidOption)
}

///|
test "equal syntax parses numeric fill" {
  assert_true(
    parse_arguments(["convert", "a.hex", "b.bin", "--fill=0xFF"])
    is Run({ convert_options: { fill: Some(b'\xFF'), .. }, .. }),
  )
}

///|
test "double dash allows dash-prefixed paths" {
  assert_true(
    parse_arguments(["inspect", "--", "-file.hex"])
    is Run({ inputs: ["-file.hex"], .. }),
  )
}

///|
test "extract end is inclusive" {
  assert_true(
    parse_arguments([
      "extract", "a.hex", "--start", "16", "--end", "19", "-o", "b.hex",
    ])
    is Run({ range: Some({ start: 16L, end: 20L, }), .. }),
  )
}

///|
test "extract missing bound rejected" {
  assert_eq(
    rejected(["extract", "a.hex", "--start", "16", "-o", "b.hex"]).code,
    InvalidOption,
  )
}

///|
test "BIN fill larger than byte rejected" {
  assert_eq(
    rejected(["convert", "a.hex", "b.bin", "--fill", "256"]).code,
    AddressOverflow,
  )
}

///|
test "irrelevant flags fail instead of being ignored" {
  assert_eq(rejected(["inspect", "a.hex", "--force"]).code, InvalidOption)
}

///|
test "unknown output extension requires explicit format" {
  assert_eq(rejected(["convert", "a.hex", "b.out"]).code, InvalidOption)
}

///|
test "explicit output format accepted" {
  assert_true(
    parse_arguments(["convert", "a.hex", "b.out", "--output-format", "srec"])
    is Run({ convert_options: { format: SRecord, .. }, .. }),
  )
}

///|
test "merge requires at least two paths" {
  assert_eq(rejected(["merge", "a.hex", "-o", "b.hex"]).code, InvalidOption)
}

///|
test "SREC options invalid for HEX" {
  assert_eq(
    rejected(["convert", "a.hex", "b.hex", "--no-count"]).code,
    InvalidOption,
  )
}

///|
test "text convert range cannot be silently ignored" {
  assert_eq(
    rejected(["convert", "a.hex", "b.hex", "--start", "0", "--end", "1"]).code,
    InvalidOption,
  )
}

///|
test "gate parses explicit Cortex-M target ranges" {
  assert_true(
    parse_arguments([
      "gate", "release.hex", "--flash-start", "0x08000000", "--flash-end", "0x080FFFFF",
      "--ram-start", "0x20000000", "--ram-end", "0x2001FFFF", "--page-size", "0x400",
      "--vector-address", "0x08008000",
    ])
    is Run(
      {
        release_options: Some(
          {
            flash: { start: 0x08000000L, end: 0x08100000L, },
            ram: [{ start: 0x20000000L, end: 0x20020000L, }],
            vector_address: 0x08008000L,
            page_size: 1024,
            ..
          }
        ),
        ..
      }
    ),
  )
}

///|
test "gate requires every target boundary and a page size" {
  assert_eq(
    rejected([
      "gate", "release.hex", "--flash-start", "0x08000000", "--flash-end", "0x080FFFFF",
      "--ram-start", "0x20000000", "--ram-end", "0x2001FFFF",
    ]).code,
    InvalidOption,
  )
}

///|
test "gate-only options cannot be silently ignored by inspect" {
  assert_eq(
    rejected(["inspect", "a.hex", "--page-size", "1024"]).code,
    InvalidOption,
  )
}
