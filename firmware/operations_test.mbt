///|
test "content signature wins over binary extension" {
  assert_eq(detect_format(b":00000001FF\n"), IntelHex)
  assert_eq(
    load_firmware(b":00000001FF\n", hint=RawBinary).metadata.source_format,
    IntelHex,
  )
}

///|
test "SREC content signature and comments" {
  assert_eq(detect_format(b"; header\n S9030000FC"), SRecord)
}

///|
test "printable bytes remain unknown" {
  assert_eq(detect_format(b"hello"), Unknown)
}

///|
test "nonprintable bytes identify raw input" {
  assert_eq(detect_format(b"\x00\xFF"), RawBinary)
}

///|
test "raw input requires placement" {
  try load_firmware(b"\x00") catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidOption)
  } noraise {
    _ => fail("expected base requirement")
  }
}

///|
test "raw input hint permits printable firmware bytes" {
  assert_eq(
    load_firmware(b"abc", hint=RawBinary, base_address=0x08000000L).memory.lowest_address(),
    Some(0x08000000L),
  )
}

///|
test "invalid text byte never replaced" {
  try load_firmware(b":\xFF", hint=IntelHex) catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidDigit)
  } noraise {
    _ => fail("expected ASCII failure")
  }
}

///|
test "all conversion directions preserve payload" {
  let raw = @model.FirmwareImage::from_binary(b"firmware\x00\xFF", 0x08000000L)
  for format in [@model.Format::IntelHex, SRecord] {
    let first = convert(raw, ConvertOptions::new(format))
    let parsed = load_firmware(first.bytes)
    assert_true(parsed.memory.same_memory(raw.memory))
    for next in [@model.Format::IntelHex, SRecord, RawBinary] {
      let result = convert(parsed, ConvertOptions::new(next))
      let restored = if next == RawBinary {
        load_firmware(result.bytes, hint=RawBinary, base_address=0x08000000L)
      } else {
        load_firmware(result.bytes)
      }
      assert_true(restored.memory.same_memory(raw.memory))
    }
  }
}

///|
test "BIN gap expansion is explicit" {
  let image = @model.FirmwareImage::new()
  image.memory.insert(0L, b"a")
  image.memory.insert(3L, b"d")
  let output = convert(image, {
    ..ConvertOptions::new(RawBinary),
    fill: Some(b'\xFF'),
  })
  assert_eq(output.bytes, b"a\xFF\xFFd")
  assert_eq(output.binary_base, Some(0L))
}

///|
test "merge disjoint images" {
  let merged = merge_images([
    @model.FirmwareImage::from_binary(b"ab", 10L),
    @model.FirmwareImage::from_binary(b"cd", 20L),
  ])
  assert_eq(merged.memory.payload_size(), 4)
  assert_eq(merged.memory.segment_count(), 2)
}

///|
test "merge adjacent images" {
  let merged = merge_images([
    @model.FirmwareImage::from_binary(b"ab", 10L),
    @model.FirmwareImage::from_binary(b"cd", 12L),
  ])
  assert_eq(merged.memory.segments()[0].data, b"abcd")
}

///|
test "merge overlap policies and input immutability" {
  let a = @model.FirmwareImage::from_binary(b"ab", 10L)
  let b = @model.FirmwareImage::from_binary(b"bc", 11L)
  try merge_images([a, b]) catch {
    @model.FirmwareError(d) => assert_eq(d.address, Some(11L))
  } noraise {
    _ => fail("expected overlap")
  }
  assert_eq(
    merge_images([a, b], policy=AllowIdentical).memory.segments()[0].data,
    b"abc",
  )
  assert_eq(a.memory.segments()[0].data, b"ab")
}

///|
test "merge conflicting overlap rejected or overwritten" {
  let a = @model.FirmwareImage::from_binary(b"ab", 10L)
  let b = @model.FirmwareImage::from_binary(b"XY", 11L)
  try merge_images([a, b], policy=AllowIdentical) catch {
    @model.FirmwareError(d) => assert_eq(d.code, AddressConflict)
  } noraise {
    _ => fail("expected conflict")
  }
  assert_eq(
    merge_images([a, b], policy=Overwrite).memory.segments()[0].data,
    b"aXY",
  )
}

///|
test "entry conflicts use independent policy" {
  let a = {
    ..@model.FirmwareImage::new(),
    entry: Some(@model.EntryPoint::Linear(10L)),
  }
  let b = {
    ..@model.FirmwareImage::new(),
    entry: Some(@model.EntryPoint::Linear(20L)),
  }
  try merge_images([a, b]) catch {
    @model.FirmwareError(d) => assert_eq(d.code, EntryConflict)
  } noraise {
    _ => fail("expected entry conflict")
  }
  assert_eq(merge_images([a, b], entry_policy=PreferLast).entry, b.entry)
}

///|
test "extract drops out of range entry and warns" {
  let image = {
    ..@model.FirmwareImage::from_binary(b"abcd", 0L),
    entry: Some(@model.EntryPoint::Linear(0L)),
  }
  let sliced = extract_range(image, @model.AddressRange::new(1L, 3L))
  assert_eq(sliced.memory.segments()[0].data, b"bc")
  assert_eq(sliced.entry, None)
  assert_eq(sliced.warnings.length(), 1)
}

///|
test "extract empty window" {
  assert_eq(
    extract_range(
      @model.FirmwareImage::from_binary(b"x", 0L),
      @model.AddressRange::new(0L, 0L),
    ).memory.payload_size(),
    0,
  )
}

///|
test "diff identical images" {
  let image = @model.FirmwareImage::from_binary(b"abc", 10L)
  let diff = diff_images(image, image.copy())
  assert_true(diff.is_equal())
  assert_eq(diff.identical_bytes, 3L)
}

///|
test "diff changed runs split at identical bytes" {
  let diff = diff_images(
    @model.FirmwareImage::from_binary(b"abcdef", 10L),
    @model.FirmwareImage::from_binary(b"aXYdeZ", 10L),
  )
  assert_eq(diff.changed_bytes, 3L)
  assert_eq(diff.changed.length(), 2)
  assert_eq(diff.changed[0].start, 11L)
  assert_eq(diff.changed[0].end, 13L)
}

///|
test "diff missing and added ranges" {
  let diff = diff_images(
    @model.FirmwareImage::from_binary(b"abc", 10L),
    @model.FirmwareImage::from_binary(b"cde", 12L),
  )
  assert_eq(diff.removed_bytes, 2L)
  assert_eq(diff.added_bytes, 2L)
  assert_eq(diff.identical_bytes, 1L)
}

///|
test "diff sparse extremes does not iterate holes" {
  let diff = diff_images(
    @model.FirmwareImage::from_binary(b"a", 0L),
    @model.FirmwareImage::from_binary(b"z", 0xFFFFFFFFL),
  )
  assert_eq(diff.only_left[0].start, 0L)
  assert_eq(diff.only_right[0].end, 0x100000000L)
}

///|
test "diff empty versus occupied" {
  let diff = diff_images(
    @model.FirmwareImage::new(),
    @model.FirmwareImage::from_binary(b"abc", 42L),
  )
  assert_eq(diff.added_bytes, 3L)
}

///|
test "diff empty versus empty" {
  assert_true(
    diff_images(@model.FirmwareImage::new(), @model.FirmwareImage::new()).is_equal(),
  )
}

///|
test "relocation retains sparse payload" {
  let image = @model.FirmwareImage::from_binary(b"abc", 16L)
  let shifted = relocate(image, 0x08000000L)
  assert_eq(shifted.memory.lowest_address(), Some(0x08000010L))
  assert_true(relocate(shifted, -0x08000000L).memory.same_memory(image.memory))
}

///|
test "relocation refuses wrapping" {
  try relocate(@model.FirmwareImage::from_binary(b"a", 0L), -1L) catch {
    @model.FirmwareError(d) => assert_eq(d.code, AddressOverflow)
  } noraise {
    _ => fail("expected relocation failure")
  }
}

///|
test "remove window leaves sparse outer pieces" {
  let image = remove_range(
    @model.FirmwareImage::from_binary(b"abcdef", 10L),
    @model.AddressRange::new(12L, 14L),
  )
  assert_eq(image.memory.segment_count(), 2)
  assert_eq(image.memory.payload_size(), 4)
}

///|
test "fill window preserves occupied bytes" {
  let image = fill_range(
    @model.FirmwareImage::from_binary(b"abc", 10L),
    @model.AddressRange::new(9L, 14L),
    b'\xFF',
  )
  assert_eq(image.memory.segments()[0].data, b"\xFFabc\xFF")
}

///|
test "fill huge sparse range refuses allocation" {
  try
    fill_range(
      @model.FirmwareImage::new(),
      @model.AddressRange::new(0L, 0x100000000L),
      b'\xFF',
    )
  catch {
    @model.FirmwareError(d) => assert_eq(d.code, ResourceLimit)
  } noraise {
    _ => fail("expected fill budget")
  }
}
