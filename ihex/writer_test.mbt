///|
test "writer emits manually verified basic record" {
  let image = @model.FirmwareImage::from_binary(b"\x01\x02\x03\x04", 16L)
  assert_eq(encode(image), ":0400100001020304E2\n:00000001FF\n")
}

///|
test "writer empty image still ends with EOF" {
  assert_eq(encode(@model.FirmwareImage::new()), ":00000001FF\n")
}

///|
test "writer splits at bank boundary and switches high word" {
  let image = @model.FirmwareImage::from_binary(b"abcd", 0x0800FFFEL)
  let lines = []
  for_each_record(image, r => lines.push(r))
  assert_eq(lines[0].kind, 4)
  assert_eq(lines[1].address, 65534)
  assert_eq(lines[1].data.length(), 2)
  assert_eq(lines[2].data, b"\x08\x01")
  assert_eq(lines[3].address, 0)
  assert_true(parse_document(encode(image)).semantic_equal(image))
}

///|
test "writer final 32-bit byte is representable" {
  let image = @model.FirmwareImage::from_binary(b"x", 0xFFFFFFFFL)
  assert_true(parse_document(encode(image)).semantic_equal(image))
}

///|
test "writer configurable record size and lowercase CRLF" {
  let image = @model.FirmwareImage::from_binary(b"\xAB\xCD\xEF", 0L)
  let text = encode(image, options={
    ..WriterOptions::default(),
    data_length: 1,
    uppercase: false,
    line_ending: CRLF,
  })
  assert_true(text.contains("ab"))
  assert_true(text.contains("\r\n"))
  assert_true(parse_document(text).semantic_equal(image))
}

///|
test "writer preserves segment entry" {
  let image = {
    ..@model.FirmwareImage::new(),
    entry: Some(@model.EntryPoint::Segment(0x1000, 5)),
  }
  assert_true(parse_document(encode(image)).semantic_equal(image))
}

///|
test "writer preserves linear entry" {
  let image = {
    ..@model.FirmwareImage::new(),
    entry: Some(@model.EntryPoint::Linear(0x08000191L)),
  }
  assert_true(parse_document(encode(image)).semantic_equal(image))
}

///|
test "writer invalid size rejected" {
  try
    encode(@model.FirmwareImage::new(), options={
      ..WriterOptions::default(),
      data_length: 0,
    })
  catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidOption)
  } noraise {
    _ => fail("expected invalid size")
  }
}

///|
test "writer text budget is enforced" {
  try
    encode(@model.FirmwareImage::new(), options={
      ..WriterOptions::default(),
      max_output_length: 11,
    })
  catch {
    @model.FirmwareError(d) => assert_eq(d.code, ResourceLimit)
  } noraise {
    _ => fail("expected text budget")
  }
}

///|
test "writer deterministic after out of order insertion" {
  let image = @model.FirmwareImage::new()
  image.memory.insert(20L, b"cd")
  image.memory.insert(10L, b"ab")
  let normalized = parse_document(encode(image))
  assert_eq(encode(image), encode(normalized))
}
