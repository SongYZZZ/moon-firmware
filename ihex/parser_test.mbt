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
/// Independent test construction permits deliberately malformed control fields.
fn wire(kind : Int, address : Int, data : Bytes) -> String {
  let body = [
    data.length().to_byte(),
    (address / 256).to_byte(),
    (address % 256).to_byte(),
    kind.to_byte(),
  ]
  for b in data {
    body.push(b)
  }
  let mut sum = 0
  for b in body {
    sum += b.to_int()
  }
  body.push(((0 - sum) & 255).to_byte())
  ":" + @codec.encode_hex(Bytes::from_array(body)) + "\n"
}

///|
test "empty document fails" {
  assert_eq(rejected("").code, MissingTerminator)
}

///|
test "EOF-only image" {
  let image = parse_document(":00000001FF\n")
  assert_eq(image.memory.payload_size(), 0)
  assert_eq(image.metadata.record_counts[1], 1)
}

///|
test "basic manually calculated checksum" {
  let image = parse_document(":0400100001020304E2\n:00000001FF\n")
  assert_eq(image.memory.segments()[0].data, b"\x01\x02\x03\x04")
  assert_eq(image.memory.lowest_address(), Some(16L))
}

///|
test "checksum single bit mutation" {
  assert_eq(rejected(":0400100001020304E3\n:00000001FF").code, ChecksumMismatch)
}

///|
test "data mutation without checksum update" {
  assert_eq(rejected(":0400100001020305E2\n:00000001FF").code, ChecksumMismatch)
}

///|
test "count mutation" {
  assert_eq(rejected(":0500100001020304E2\n:00000001FF").code, InvalidLength)
}

///|
test "address mutation without checksum update" {
  assert_eq(rejected(":0400110001020304E2\n:00000001FF").code, ChecksumMismatch)
}

///|
test "type mutation without checksum update" {
  assert_eq(rejected(":0400100101020304E2\n:00000001FF").code, ChecksumMismatch)
}

///|
test "hex letter cases are equivalent" {
  assert_true(
    parse_document(":01000000ab54\n:00000001ff").memory.same_memory(
      parse_document(":01000000AB54\n:00000001FF").memory,
    ),
  )
}

///|
test "CRLF and LF equivalent" {
  assert_true(
    parse_document(":00000001FF\r\n").semantic_equal(
      parse_document(":00000001FF\n"),
    ),
  )
}

///|
test "invalid digit reports original location" {
  let d = rejected(":010000000GFF\n:00000001FF")
  assert_eq(d.code, InvalidDigit)
  assert_eq(d.line, 1)
  assert_eq(d.column, 11)
}

///|
test "odd digit count" {
  assert_eq(rejected(":00000001F").code, InvalidLength)
}

///|
test "truncated record" {
  assert_eq(rejected(":00").code, InvalidLength)
}

///|
test "malformed address digit" {
  assert_eq(rejected(":000G0001FF").code, InvalidDigit)
}

///|
test "missing EOF strict" {
  assert_eq(rejected(wire(0, 0, b"a")).code, MissingTerminator)
}

///|
test "missing EOF permissive warns" {
  let image = parse_document(wire(0, 0, b"a"), options={
    ..@model.ParseOptions::default(),
    mode: Permissive,
  })
  assert_eq(image.warnings[0].code, MissingTerminator)
}

///|
test "duplicate EOF strict" {
  assert_eq(rejected(":00000001FF\n:00000001FF").code, AfterTerminator)
}

///|
test "duplicate EOF permissive warns" {
  assert_eq(
    parse_document(":00000001FF\n:00000001FF", options={
      ..@model.ParseOptions::default(),
      mode: Permissive,
    }).warnings.length(),
    1,
  )
}

///|
test "data after EOF never accepted" {
  assert_eq(
    rejected(":00000001FF\n" + wire(0, 0, b"a"), options={
      ..@model.ParseOptions::default(),
      mode: Permissive,
    }).code,
    AfterTerminator,
  )
}

///|
test "EOF data forbidden" {
  assert_eq(rejected(wire(1, 0, b"a")).code, InvalidLength)
}

///|
test "control address must be zero" {
  assert_eq(rejected(wire(1, 1, b"")).code, InvalidRecord)
}

///|
test "extended segment shifts by four" {
  let image = parse_document(
    wire(2, 0, b"\x12\x34") + wire(0, 0x10, b"x") + ":00000001FF",
  )
  assert_eq(image.memory.lowest_address(), Some(0x12350L))
}

///|
test "extended linear shifts by sixteen" {
  let image = parse_document(
    wire(4, 0, b"\x08\x00") + wire(0, 0x10, b"x") + ":00000001FF",
  )
  assert_eq(image.memory.lowest_address(), Some(0x08000010L))
}

///|
test "segment and linear base replace each other" {
  let text = wire(4, 0, b"\x08\x00") +
    wire(2, 0, b"\x00\x10") +
    wire(0, 0, b"x") +
    ":00000001FF"
  assert_eq(parse_document(text).memory.lowest_address(), Some(0x100L))
}

///|
test "start segment preserves both registers" {
  let image = parse_document(wire(3, 0, b"\x12\x34\x56\x78") + ":00000001FF")
  assert_eq(image.entry, Some(@model.EntryPoint::Segment(0x1234, 0x5678)))
  assert_eq(image.memory.payload_size(), 0)
}

///|
test "start linear preserves thumb bit" {
  let image = parse_document(wire(5, 0, b"\x08\x00\x01\x91") + ":00000001FF")
  assert_eq(image.entry, Some(@model.EntryPoint::Linear(0x08000191L)))
}

///|
test "extended address invalid data size" {
  assert_eq(rejected(wire(4, 0, b"x")).code, InvalidLength)
}

///|
test "unsupported type is not data" {
  assert_eq(rejected(wire(6, 0, b"")).code, UnsupportedRecord)
}

///|
test "linear record carries over 64 KiB" {
  let image = parse_document(
    wire(4, 0, b"\x08\x00") + wire(0, 65535, b"ab") + ":00000001FF",
  )
  assert_eq(image.memory.read(0x08010000L), Some(b'b'))
}

///|
test "segment record wraps offset within segment" {
  let image = parse_document(
    wire(2, 0, b"\x10\x00") + wire(0, 65535, b"ab") + ":00000001FF",
  )
  assert_eq(image.memory.read(0x1FFFFL), Some(b'a'))
  assert_eq(image.memory.read(0x10000L), Some(b'b'))
}

///|
test "linear 32-bit overflow rejected" {
  assert_eq(
    rejected(wire(4, 0, b"\xFF\xFF") + wire(0, 65535, b"ab") + ":00000001FF").code,
    AddressOverflow,
  )
}

///|
test "sparse records retain gaps" {
  let image = parse_document(
    wire(0, 0x1000, b"ab") + wire(0, 0x2000, b"cd") + ":00000001FF",
  )
  assert_eq(image.memory.segment_count(), 2)
  assert_eq(image.memory.gaps()[0].start, 0x1002L)
}

///|
test "permissive mode never ignores corruption" {
  assert_eq(
    rejected(":01000000AB55\n:00000001FF", options={
      ..@model.ParseOptions::default(),
      mode: Permissive,
    }).code,
    ChecksumMismatch,
  )
}

///|
test "permissive BOM comments whitespace warning" {
  let image = parse_document("\uFEFF ; header\n\n  :00000001FF \n", options={
    ..@model.ParseOptions::default(),
    mode: Permissive,
  })
  assert_eq(image.warnings.length(), 3)
}

///|
test "strict blank line fails" {
  assert_eq(rejected("\n:00000001FF").code, InvalidRecord)
}

///|
test "record count resource cap" {
  assert_eq(
    rejected(wire(0, 0, b"a") + ":00000001FF", options={
      ..@model.ParseOptions::default(),
      max_records: 1,
    }).code,
    ResourceLimit,
  )
}

///|
test "payload resource cap" {
  assert_eq(
    rejected(wire(0, 0, b"ab") + ":00000001FF", options={
      ..@model.ParseOptions::default(),
      max_payload: 1,
    }).code,
    ResourceLimit,
  )
}

///|
test "overlap failure retains source line" {
  let d = rejected(wire(0, 0, b"ab") + wire(0, 1, b"c") + ":00000001FF")
  assert_eq(d.line, 2)
  assert_eq(d.address, Some(1L))
}

///|
test "checksum empty and known body" {
  assert_true(!verify_checksum(b""))
  assert_eq(compute_checksum(b"\x00\x00\x00\x01"), b'\xFF')
}
