///|
fn codec_location() -> Location {
  { format: IntelHex, line: 7, column_offset: 3, record_type: Some(4), }
}

///|
fn[T] codec_result(
  action : () -> T raise @model.FirmwareError,
) -> Result[T, @model.FirmwareError] {
  Ok(action()) catch {
    error => Err(error)
  }
}

///|
test "all byte values encode in both alphabets and decode without data loss" {
  let values = Bytes::makei(256, i => i.to_byte())
  let upper = encode_hex(values)
  let lower = encode_hex(values, uppercase=false)
  assert_eq(upper.length(), 512)
  assert_eq(upper.to_lower(), lower)
  assert_eq(decode_hex(upper, 0, codec_location()), values)
  assert_eq(decode_hex(lower, 0, codec_location()), values)
}

///|
test "hex digit decoder rejects ASCII punctuation and Unicode lookalikes" {
  for text in ["/", ":", "@", "G", "`", "g", "Ｆ", "１", "é", " ", "\t"] {
    assert_eq(hex_digit(text[0]), None)
  }
  assert_eq(hex_digit("0"[0]), Some(0))
  assert_eq(hex_digit("9"[0]), Some(9))
  assert_eq(hex_digit("A"[0]), Some(10))
  assert_eq(hex_digit("f"[0]), Some(15))
}

///|
test "decoder reports first malformed high and low nibble with source offset" {
  for sample in [("12G4", 6), ("123G", 7)] {
    let (text, column) = sample
    assert_true(
      codec_result(() => decode_hex(text, 0, codec_location()))
      is Err(
        @model.FirmwareError(
          { code: InvalidDigit, line: 7, column: c, record_type: Some(4), .. }
        )
      ) &&
      c == column,
    )
  }
}

///|
test "decoder validates odd lengths and indices before reading any byte" {
  for start in [-1, 1, 5] {
    assert_true(
      codec_result(() => decode_hex("1234", start, codec_location()))
      is Err(@model.FirmwareError({ code: InvalidLength, .. })),
    )
  }
  assert_eq(decode_hex("1234", 4, codec_location()), b"")
  assert_eq(decode_hex("prefix12", 6, codec_location()), b"\x12")
}

///|
test "big endian address codecs preserve each width and its maximum value" {
  for width in 1..<5 {
    let maximum = (1L << (width * 8)) - 1L
    for value in [0L, 1L, maximum / 2L, maximum] {
      let encoded = address_bytes(value, width)
      assert_eq(encoded.length(), width)
      assert_eq(read_address(encoded, 0, width), value)
    }
    assert_true(
      codec_result(() => address_bytes(maximum + 1L, width))
      is Err(@model.FirmwareError({ code: AddressOverflow, .. })),
    )
  }
  assert_eq(address_bytes(0x12345678L, 4), b"\x12\x34\x56\x78")
  assert_eq(read_address(b"\xAA\x12\x34\xBB", 1, 2), 0x1234L)
}

///|
test "address codecs reject unsupported widths negative addresses and truncation" {
  for width in [-1, 0, 5, 2147483647] {
    assert_true(codec_result(() => address_bytes(0L, width)) is Err(_))
    assert_true(codec_result(() => read_address(b"abcd", 0, width)) is Err(_))
  }
  assert_true(codec_result(() => address_bytes(-1L, 4)) is Err(_))
  for offset in [-1, 1, 2147483647] {
    assert_true(
      codec_result(() => read_address(b"abcd", offset, 4))
      is Err(@model.FirmwareError({ code: InvalidLength, .. })),
    )
  }
}

///|
test "number parser accepts unsigned decimal and prefixed hexadecimal limits" {
  assert_eq(parse_number("4294967295"), 0xFFFFFFFFL)
  assert_eq(parse_number("0xFFFFFFFF"), 0xFFFFFFFFL)
  assert_eq(parse_number("0Xabcdef"), 0xABCDEFL)
  assert_eq(parse_number("000123"), 123L)
  assert_eq(parse_number("0", max_value=0L), 0L)
  assert_eq(
    parse_number("9223372036854775807", max_value=9223372036854775807L),
    9223372036854775807L,
  )
}

///|
test "number parser rejects signs spaces fractional and nondecimal plain digits" {
  for
    text in [
      "", "0x", "-1", "+1", " 1", "1 ", "1.0", "1e2", "0b10", "１２", "0xＧ1",
      "1_000",
    ] {
    assert_true(
      codec_result(() => parse_number(text))
      is Err(@model.FirmwareError({ code: InvalidOption, .. })),
      msg=text,
    )
  }
}

///|
test "number overflow is detected before multiplying including Int64 boundary" {
  for
    text in [
      "4294967296", "0x100000000", "999999999999999999999999999999999999",
    ] {
    assert_true(
      codec_result(() => parse_number(text))
      is Err(@model.FirmwareError({ code: AddressOverflow, .. })),
    )
  }
  assert_true(
    codec_result(() => {
      parse_number("9223372036854775808", max_value=9223372036854775807L)
    })
    is Err(@model.FirmwareError({ code: AddressOverflow, .. })),
  )
  assert_true(codec_result(() => parse_number("1", max_value=0L)) is Err(_))
  assert_true(codec_result(() => parse_number("0", max_value=-1L)) is Err(_))
}

///|
test "line scanner handles mixed LF CRLF and no final newline exactly once" {
  let lines = []
  let numbers = []
  let warnings = []
  for_each_line(
    "first\r\nsecond\nthird",
    IntelHex,
    @model.ParseOptions::default(),
    warnings,
    source => {
      lines.push(source.text)
      numbers.push(source.location.line)
    },
  )
  assert_eq(lines, ["first", "second", "third"])
  assert_eq(numbers, [1, 2, 3])
  assert_true(warnings.is_empty())
}

///|
test "strict scanner preserves blank and comment text for grammar rejection" {
  let lines = []
  for_each_line(
    "\n# note\n; note\n",
    IntelHex,
    @model.ParseOptions::default(),
    [],
    source => lines.push(source.text),
  )
  assert_eq(lines, ["", "# note", "; note"])
}

///|
test "permissive scanner trims ASCII BOM and comments while retaining original columns" {
  let lines = []
  let warnings = []
  let options = { ..@model.ParseOptions::default(), mode: Permissive, }
  for_each_line(
    "\u{FEFF}  first \t\r\n\t# note\n\n  second\n",
    SRecord,
    options,
    warnings,
    source => {
      lines.push(
        (source.text, source.location.line, source.location.column_offset),
      )
    },
  )
  assert_eq(lines, [("first", 1, 3), ("second", 4, 2)])
  assert_eq(warnings.length(), 4)
  assert_eq(warnings[0].format, SRecord)
}

///|
test "BOM is tolerated only on first line and Unicode whitespace is retained" {
  let lines = []
  let options = { ..@model.ParseOptions::default(), mode: Permissive, }
  for_each_line(
    "first\n\u{FEFF}second\n\u{00A0}third\n",
    IntelHex,
    options,
    [],
    source => lines.push(source.text),
  )
  assert_eq(lines, ["first", "\u{FEFF}second", "\u{00A0}third"])
}

///|
test "line size limit is enforced with and without a terminating newline" {
  let options = { ..@model.ParseOptions::default(), max_line_length: 11, }
  for text in ["123456789012", "123456789012\n", "short\n123456789012"] {
    assert_true(
      codec_result(() => for_each_line(text, IntelHex, options, [], _ => ()))
      is Err(@model.FirmwareError({ code: ResourceLimit, .. })),
    )
  }
  let lines = []
  for_each_line("12345678901\r\n", IntelHex, options, [], source => {
    lines.push(source.text)
  })
  assert_eq(lines, ["12345678901"])
}

///|
test "document budget is checked before visitor runs" {
  let options = { ..@model.ParseOptions::default(), max_text_length: 2, }
  let visited = []
  assert_true(
    codec_result(() => {
      for_each_line("abc", IntelHex, options, [], source => {
        visited.push(source.text)
      })
    })
    is Err(@model.FirmwareError({ code: ResourceLimit, .. })),
  )
  assert_true(visited.is_empty())
}

///|
test "zero warning budget permits clean records but rejects first tolerance" {
  let options = {
    ..@model.ParseOptions::default(),
    mode: Permissive,
    max_warnings: 0,
  }
  let clean = []
  for_each_line("clean\n", IntelHex, options, [], source => {
    clean.push(source.text)
  })
  assert_eq(clean, ["clean"])
  for text in ["# comment\n", "\n", " clean\n"] {
    assert_true(
      codec_result(() => for_each_line(text, IntelHex, options, [], _ => ()))
      is Err(@model.FirmwareError({ code: ResourceLimit, line: 1, .. })),
    )
  }
}

///|
test "comment flood consumes warning budget even though no record visitor runs" {
  let options = {
    ..@model.ParseOptions::default(),
    mode: Permissive,
    max_warnings: 3,
  }
  let warnings = []
  let visited = []
  let result = codec_result(() => {
    for_each_line("# a\n# b\n# c\n# d\n# e\n", IntelHex, options, warnings, source => {
      visited.push(source.text)
    })
  })
  assert_true(
    result is Err(@model.FirmwareError({ code: ResourceLimit, line: 4, .. })),
  )
  assert_eq(warnings.length(), 4)
  assert_true(visited.is_empty())
}

///|
test "visitor diagnostics share warning budget with scanner tolerances" {
  let options = { ..@model.ParseOptions::default(), max_warnings: 1, }
  let warnings = []
  let result = codec_result(() => {
    for_each_line("a\nb\n", IntelHex, options, warnings, _ => {
      warnings.push(@model.diagnostic(DuplicateRecord, "repeated record"))
    })
  })
  assert_true(
    result is Err(@model.FirmwareError({ code: ResourceLimit, line: 2, .. })),
  )
}

///|
test "relocalization preserves conflict addresses while updating source context" {
  let original = @model.FirmwareError(
    @model.diagnostic(AddressConflict, "conflict", address=16L, end_address=20L),
  )
  let @model.FirmwareError(relocated) = locate_error(original, codec_location())
  assert_eq(relocated.address, Some(16L))
  assert_eq(relocated.end_address, Some(20L))
  assert_eq(relocated.line, 7)
  assert_eq(relocated.column, 4)
  assert_eq(relocated.record_type, Some(4))
  assert_eq(relocated.format, IntelHex)
}

///|
test "bounded text output counts chosen newline bytes and refuses partial writes" {
  let output = TextOutput::new(CRLF, 7)
  output.write_line("abc")
  assert_true(
    codec_result(() => output.write_line("x"))
    is Err(@model.FirmwareError({ code: ResourceLimit, .. })),
  )
  assert_eq(output.finish(), "abc\r\n")
  output.write_line("")
  assert_eq(output.finish(), "abc\r\n\r\n")
}

///|
test "empty sink has no implicit newline and validates allocation budgets" {
  let output = TextOutput::new(LF, 0)
  assert_eq(output.finish(), "")
  assert_true(codec_result(() => output.write_line("")) is Err(_))
  for budget in [-1, 256 * 1024 * 1024 + 1] {
    assert_true(
      codec_result(() => TextOutput::new(LF, budget))
      is Err(@model.FirmwareError({ code: InvalidOption, .. })),
    )
  }
}
