///|
fn rejected(
  text : String,
  options? : @model.ParseOptions = @model.ParseOptions::default(),
) -> @model.Diagnostic raise {
  try parse_document(text, options~) catch {
    @model.FirmwareError(d) => d
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "S1 manually calculated count checksum" {
  let image = parse_document("S107001001020304DE\nS5030001FB\nS9030010EC\n")
  assert_eq(image.memory.lowest_address(), Some(16L))
  assert_eq(image.memory.segments()[0].data, b"\x01\x02\x03\x04")
  assert_eq(image.entry, Some(@model.EntryPoint::Linear(16L)))
}

///|
test "S0 header byte preservation" {
  let header = Record::new(0, 0L, b"MoonFirmware\x00\xFF").encode()
  let image = parse_document(header + "\nS9030000FC")
  assert_eq(image.metadata.header, Some(b"MoonFirmware\x00\xFF"))
  assert_eq(
    parse_document(encode(image)).metadata.header,
    image.metadata.header,
  )
}

///|
test "S2 and S8 24-bit address" {
  let text = Record::new(2, 0xABCDEFL, b"x").encode() +
    "\n" +
    Record::new(8, 0xABCDEFL, b"").encode()
  assert_eq(parse_document(text).memory.lowest_address(), Some(0xABCDEFL))
}

///|
test "S3 and S7 32-bit address" {
  let text = Record::new(3, 0xFFFFFFFFL, b"x").encode() +
    "\n" +
    Record::new(7, 0xFFFFFFFFL, b"").encode()
  assert_eq(parse_document(text).memory.read(0xFFFFFFFFL), Some(b'x'))
}

///|
test "S6 count accepted" {
  let image = parse_document("S104000041BA\nS604000001FA\nS9030000FC")
  assert_eq(image.metadata.record_counts[6], 1)
}

///|
test "checksum bit corruption" {
  assert_eq(rejected("S107001001020304DF\nS9030000FC").code, ChecksumMismatch)
}

///|
test "data corruption" {
  assert_eq(rejected("S107001001020305DE\nS9030000FC").code, ChecksumMismatch)
}

///|
test "count corruption" {
  assert_eq(rejected("S108001001020304DE\nS9030000FC").code, InvalidLength)
}

///|
test "address corruption" {
  assert_eq(rejected("S107001101020304DE\nS9030000FC").code, ChecksumMismatch)
}

///|
test "reserved S4 diagnosed" {
  assert_eq(rejected("S4030000FC").code, UnsupportedRecord)
}

///|
test "non digit record kind" {
  assert_eq(rejected("SX030000FC").code, UnsupportedRecord)
}

///|
test "invalid hex digit" {
  let d = rejected("S903000GFC")
  assert_eq(d.code, InvalidDigit)
  assert_eq(d.column, 8)
}

///|
test "too small count" {
  assert_eq(rejected("S901FE").code, InvalidLength)
}

///|
test "odd hex digits" {
  assert_eq(rejected("S9030000F").code, InvalidLength)
}

///|
test "missing termination strict" {
  assert_eq(rejected("S104000041BA").code, MissingTerminator)
}

///|
test "missing termination permissive warns" {
  let image = parse_document("S104000041BA", options={
    ..@model.ParseOptions::default(),
    mode: Permissive,
  })
  assert_eq(image.warnings[0].code, MissingTerminator)
}

///|
test "permissive checksum still mandatory" {
  assert_eq(
    rejected("S104000041BB", options={
      ..@model.ParseOptions::default(),
      mode: Permissive,
    }).code,
    ChecksumMismatch,
  )
}

///|
test "S5 count mismatch fails" {
  assert_eq(
    rejected("S104000041BA\nS5030002FA\nS9030000FC").code,
    CountMismatch,
  )
}

///|
test "duplicate count fails" {
  assert_eq(
    rejected("S5030000FC\nS604000000FB\nS9030000FC").code,
    DuplicateRecord,
  )
}

///|
test "termination width mismatch" {
  assert_eq(rejected("S104000041BA\nS804000000FB").code, InvalidRecord)
}

///|
test "data after count fails" {
  assert_eq(
    rejected("S5030000FC\nS104000041BA\nS9030000FC").code,
    InvalidRecord,
  )
}

///|
test "data after termination fails" {
  assert_eq(rejected("S9030000FC\nS104000041BA").code, AfterTerminator)
}

///|
test "mixed widths strict fails" {
  let text = "S104000041BA\n" +
    Record::new(2, 100L, b"b").encode() +
    "\nS804000000FB"
  assert_eq(rejected(text).code, InvalidRecord)
  assert_eq(
    parse_document(text, options={
      ..@model.ParseOptions::default(),
      mode: Permissive,
    }).warnings.length(),
    1,
  )
}

///|
test "S0 cannot appear after data" {
  assert_eq(
    rejected("S104000041BA\nS0030000FC\nS9030000FC").code,
    DuplicateRecord,
  )
}

///|
test "S0 nonzero address rejected" {
  assert_eq(rejected("S0030001FB\nS9030000FC").code, InvalidRecord)
}

///|
test "termination must not contain data" {
  assert_eq(rejected("S904000041BA").code, InvalidLength)
}

///|
test "empty document fails" {
  assert_eq(rejected("").code, MissingTerminator)
}

///|
test "lowercase hex and CRLF accepted" {
  assert_eq(
    parse_document("S1040000ab50\r\nS9030000fc").memory.payload_size(),
    1,
  )
}

///|
test "writer chooses width from highest byte" {
  for pair in [(65535L, 1), (65536L, 2), (0x1000000L, 3)] {
    let (address, kind) = pair
    let image = @model.FirmwareImage::from_binary(b"x", address)
    let text = encode(image)
    assert_true(text.has_prefix("S\{kind}"))
    assert_true(parse_document(text).memory.same_memory(image.memory))
  }
}

///|
test "writer chooses width from entry even without data" {
  let image = {
    ..@model.FirmwareImage::new(),
    entry: Some(@model.EntryPoint::Linear(0x08000000L)),
  }
  assert_true(encode(image).contains("S7"))
}

///|
test "writer forced width refuses truncation" {
  let image = @model.FirmwareImage::from_binary(b"x", 65536L)
  try
    encode(image, options={ ..WriterOptions::default(), address_width: Bits16 })
  catch {
    @model.FirmwareError(d) => assert_eq(d.code, AddressOverflow)
  } noraise {
    _ => fail("expected width failure")
  }
}

///|
test "writer S6 selected beyond 65535 records" {
  let image = @model.FirmwareImage::from_binary(Bytes::make(65536, b'x'), 0L)
  let text = encode(image, options={
    ..WriterOptions::default(),
    data_length: 1,
  })
  assert_true(text.contains("S604010000FA"))
  assert_true(parse_document(text).memory.same_memory(image.memory))
}

///|
test "writer rejects invalid data length" {
  try
    encode(@model.FirmwareImage::new(), options={
      ..WriterOptions::default(),
      data_length: 253,
    })
  catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidOption)
  } noraise {
    _ => fail("expected length failure")
  }
}

///|
test "writer optional count and deterministic roundtrip" {
  let image = @model.FirmwareImage::from_binary(b"abc", 16L)
  let options = {
    ..WriterOptions::default(),
    emit_count: false,
    uppercase: false,
    line_ending: CRLF,
  }
  let text = encode(image, options~)
  assert_true(!text.contains("S5"))
  assert_eq(encode(parse_document(text), options~), text)
}

///|
test "writer segment flattening requires opt-in" {
  let image = {
    ..@model.FirmwareImage::new(),
    entry: Some(@model.EntryPoint::Segment(0x1000, 16)),
  }
  try encode(image) catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidOption)
  } noraise {
    _ => fail("expected entry representation failure")
  }
  let text = encode(image, options={
    ..WriterOptions::default(),
    flatten_segment_entry: true,
  })
  assert_eq(
    parse_document(text).entry,
    Some(@model.EntryPoint::Linear(0x10010L)),
  )
}

///|
test "SREC checksum differs from Intel rule" {
  assert_eq(compute_checksum(b"\x03\x00\x00"), b'\xFC')
  assert_true(verify_checksum(b"\x03\x00\x00\xFC"))
  assert_true(!verify_checksum(b"\x03\x00\x00\xFD"))
  assert_true(!verify_checksum(b""))
}
