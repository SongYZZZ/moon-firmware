///|
fn image_at(address : Int64, bytes : Bytes) -> @model.FirmwareImage raise {
  @model.FirmwareImage::from_binary(bytes, address)
}

///|
fn caught(
  erroring : () -> Unit raise @model.FirmwareError,
) -> @model.Diagnostic raise {
  try erroring() catch {
    @model.FirmwareError(d) => d
  } noraise {
    _ => fail("expected structured error")
  }
}

///|
test "standard CRC vectors identify firmware-level algorithm variants" {
  let image = image_at(0x1000L, b"123456789")
  let range = @model.AddressRange::new(0x1000L, 0x1009L)
  let crc32 = checksum_image(image, range)
  let crc16 = checksum_image(image, range, algorithm=Crc16Ccitt)
  assert_eq(crc32.value, 0xCBF43926L)
  assert_eq(crc32.hex(), "0xCBF43926")
  assert_eq(crc16.value, 0x29B1L)
  assert_eq(crc16.hex(), "0x29B1")
}

///|
test "additive checksums wrap at selected width" {
  let image = image_at(0L, Bytes::make(300, 0xFF))
  let range = @model.AddressRange::new(0L, 300L)
  assert_eq(
    checksum_image(image, range, algorithm=Sum8).value,
    (300L * 255L) & 255L,
  )
  assert_eq(
    checksum_image(image, range, algorithm=Sum16).value,
    (300L * 255L) & 65535L,
  )
  assert_eq(checksum_image(image, range, algorithm=Sum32).value, 300L * 255L)
}

///|
test "checksum gaps require and account for explicit fill" {
  let memory = @model.MemoryMap::new()
  memory.insert(0x10L, b"A")
  memory.insert(0x13L, b"B")
  let image = { ..@model.FirmwareImage::new(), memory, }
  let range = @model.AddressRange::new(0x10L, 0x14L)
  let diagnostic = caught(() => ignore(checksum_image(image, range)))
  assert_eq(diagnostic.code, GapRequiresFill)
  assert_eq(diagnostic.address, Some(0x11L))
  let result = checksum_image(image, range, algorithm=Sum8, fill=0xFF)
  assert_eq(result.value, (65L + 255L + 255L + 66L) & 255L)
  assert_eq(result.filled_bytes, 2)
}

///|
test "checksum window budget is checked before address iteration" {
  let image = image_at(0L, b"x")
  let diagnostic = caught(() => {
    ignore(
      checksum_image(
        image,
        @model.AddressRange::new(0L, 1000000L),
        fill=0,
        max_bytes=16,
      ),
    )
  })
  assert_eq(diagnostic.code, ResourceLimit)
}

///|
test "exact search returns overlapping matches in address order" {
  let image = image_at(0x2000L, b"ABABA")
  let matches = find_pattern(image, MaskedPattern::exact(b"ABA"))
  assert_eq(matches, [0x2000L, 0x2002L])
}

///|
test "masked search compares only selected bits" {
  let image = image_at(0L, b"\xA1\xB2\xAF\xBF")
  let pattern = MaskedPattern::new(b"\xA0\xB0", b"\xF0\xF0")
  assert_eq(find_pattern(image, pattern), [0L, 2L])
}

///|
test "search window clips candidates and no match crosses a gap" {
  let memory = @model.MemoryMap::new()
  memory.insert(10L, b"AB")
  memory.insert(13L, b"ABAB")
  let image = { ..@model.FirmwareImage::new(), memory, }
  assert_eq(find_pattern(image, MaskedPattern::exact(b"BA")), [14L])
  assert_eq(
    find_pattern(
      image,
      MaskedPattern::exact(b"AB"),
      within=@model.AddressRange::new(14L, 17L),
    ),
    [15L],
  )
}

///|
test "pattern constructors and result budget reject ambiguous work" {
  let empty = caught(() => ignore(MaskedPattern::exact(b"")))
  assert_eq(empty.code, InvalidOption)
  let mismatch = caught(() => ignore(MaskedPattern::new(b"ab", b"\xFF")))
  assert_eq(mismatch.code, InvalidOption)
  let image = image_at(0L, b"aaaa")
  assert_eq(
    caught(() => {
      ignore(find_pattern(image, MaskedPattern::exact(b"a"), max_matches=2))
    }).code,
    ResourceLimit,
  )
}

///|
test "ASCII extraction retains absolute ranges and splits on nonprintable data" {
  let image = image_at(0x4000L, b"\x00hello\x01world!\x7Fno")
  let spans = find_ascii_strings(image, min_length=5)
  assert_eq(spans.length(), 2)
  assert_eq(spans[0].address, 0x4001L)
  assert_eq(spans[0].bytes, b"hello")
  assert_eq(spans[1].address, 0x4007L)
  assert_eq(spans[1].bytes, b"world!")
}

///|
test "ASCII result limits count retained payload rather than address span" {
  let image = image_at(0L, b"first\x00second")
  assert_eq(
    caught(() => ignore(find_ascii_strings(image, max_strings=1))).code,
    ResourceLimit,
  )
  assert_eq(
    caught(() => ignore(find_ascii_strings(image, max_retained_bytes=9))).code,
    ResourceLimit,
  )
}

///|
test "integer codecs preserve both byte orders at every width" {
  for width in 1..<=4 {
    let max = (1L << (width * 8)) - 1L
    for order in [ByteOrder::LittleEndian, ByteOrder::BigEndian] {
      let bytes = encode_uint(max, width, order~)
      let image = image_at(0x100L, bytes)
      assert_eq(read_uint(image, 0x100L, width, order~), max)
    }
  }
  assert_eq(encode_uint(0x12345678L, 4), b"\x78\x56\x34\x12")
  assert_eq(encode_uint(0x12345678L, 4, order=BigEndian), b"\x12\x34\x56\x78")
}

///|
test "integer reads report the first unmapped byte" {
  let memory = @model.MemoryMap::new()
  memory.insert(0L, b"\x01")
  memory.insert(2L, b"\x03")
  let image = { ..@model.FirmwareImage::new(), memory, }
  let diagnostic = caught(() => ignore(read_uint(image, 0L, 3)))
  assert_eq(diagnostic.code, InvalidRange)
  assert_eq(diagnostic.address, Some(1L))
}

///|
test "word writes are immutable and use explicit overlap policy" {
  let source = image_at(0x10L, b"abcd")
  let changed = write_uint(source, 0x11L, 0x1234L, 2)
  assert_eq(source.memory.read(0x11L), Some(b'b'))
  assert_eq(changed.memory.read(0x11L), Some(0x34))
  assert_eq(changed.memory.read(0x12L), Some(0x12))
  assert_eq(changed.metadata.source_format, Unknown)
  assert_eq(
    caught(() => ignore(write_uint(source, 0x11L, 0x1234L, 2, policy=Reject))).code,
    AddressConflict,
  )
}

///|
test "word search honors absolute power-of-two alignment" {
  let image = image_at(1L, b"\x34\x12\x34\x12\x34\x12")
  assert_eq(find_uint(image, 0x1234L, 2), [1L, 3L, 5L])
  assert_eq(find_uint(image, 0x1234L, 2, alignment=2), [])
  assert_eq(
    caught(() => ignore(find_uint(image, 0x1234L, 2, alignment=3))).code,
    InvalidOption,
  )
}

///|
test "Cortex-M vector inspection normalizes Thumb reset address" {
  let memory = @model.MemoryMap::new()
  memory.insert(0x08000000L, b"\x00\x20\x00\x20\x09\x00\x00\x08")
  memory.insert(0x08000008L, b"code")
  let image = { ..@model.FirmwareImage::new(), memory, }
  let table = inspect_cortex_m_vectors(image, 0x08000000L)
  assert_eq(table.initial_stack_pointer, 0x20002000L)
  assert_eq(table.reset_vector, 0x08000009L)
  assert_eq(table.reset_address, 0x08000008L)
  assert_true(table.thumb)
  assert_true(table.stack_aligned)
  assert_true(table.reset_mapped)
}

///|
test "Cortex-M vector validation exposes structural problems" {
  let image = image_at(0L, b"\x01\x00\x00\x20\x00\x10\x00\x08")
  let table = inspect_cortex_m_vectors(image, 0L)
  assert_false(table.thumb)
  assert_false(table.stack_aligned)
  assert_false(table.reset_mapped)
  assert_eq(
    caught(() => ignore(inspect_cortex_m_vectors(image, 0L, stack_alignment=3))).code,
    InvalidOption,
  )
}
