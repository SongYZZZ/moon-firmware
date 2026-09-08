///|
// Park-Miller generator: multiplication stays within Int64 on every backend.
// Fixed seeds make every failing trial reproducible without an external library.
priv struct PropertyRandom {
  mut state : Int64
}

///|
fn PropertyRandom::below(self : PropertyRandom, bound : Int) -> Int {
  self.state = self.state * 16807L % 2147483647L
  (self.state % bound.to_int64()).to_int()
}

///|
fn generated_image(
  random : PropertyRandom,
  trial : Int,
) -> @model.FirmwareImage raise @model.FirmwareError {
  let bases = [0L, 0xFF80L, 0xFFFF80L, 0x08000000L, 0xFFFFE000L]
  let base = bases[trial % bases.length()]
  let memory = @model.MemoryMap::new()
  let pieces : Array[(@model.AddressRange, Bytes)] = []
  let mut address = base
  for _ in 0..<random.below(12) {
    address += random.below(129).to_int64()
    let length = 1 + random.below(257)
    let data = Bytes::makei(length, _ => random.below(256).to_byte())
    let range = @model.data_range(address, length)
    pieces.push((range, data))
    address = range.end
  }
  // Reverse insertion alternates with forward insertion to exercise normalization.
  if trial % 2 == 0 {
    for i = pieces.length() - 1; i >= 0; i = i - 1 {
      memory.insert(pieces[i].0.start, pieces[i].1)
    }
  } else {
    for piece in pieces {
      let (range, data) = piece
      memory.insert(range.start, data)
    }
  }
  {
    memory,
    entry: Some(@model.EntryPoint::Linear(base + random.below(512).to_int64())),
    metadata: {
      ..@model.Metadata::new(Unknown),
      header: Some(
        Bytes::makei(random.below(24), _ => random.below(256).to_byte()),
      ),
    },
    warnings: [],
  }
}

///|
test "512 fixed-seed sparse images round-trip through HEX SREC and both conversions" {
  let random = PropertyRandom::{ state: 20260907L, }
  for trial in 0..<512 {
    let original = generated_image(random, trial)
    let hex_options = {
      ..@ihex.WriterOptions::default(),
      data_length: 1 + random.below(255),
      uppercase: trial % 2 == 0,
      line_ending: if trial % 3 == 0 {
        @codec.LineEnding::CRLF
      } else {
        LF
      },
    }
    let srec_options = {
      ..@srec.WriterOptions::default(),
      data_length: 1 + random.below(250),
      uppercase: trial % 2 != 0,
      line_ending: if trial % 3 == 1 {
        @codec.LineEnding::CRLF
      } else {
        LF
      },
      emit_count: trial % 4 != 0,
    }
    let hex_text = @ihex.encode(original, options=hex_options)
    let srec_text = @srec.encode(original, options=srec_options)
    let from_hex = @ihex.parse_document(hex_text)
    let from_srec = @srec.parse_document(srec_text)
    assert_true(original.semantic_equal(from_hex), msg="HEX trial \{trial}")
    assert_true(original.semantic_equal(from_srec), msg="SREC trial \{trial}")
    assert_eq(from_srec.metadata.header, original.metadata.header)
    assert_eq(@ihex.encode(original, options=hex_options), hex_text)
    assert_eq(@srec.encode(original, options=srec_options), srec_text)
    let hex_to_srec = convert(from_hex, {
      ..ConvertOptions::new(SRecord),
      srecord: srec_options,
    })
    let srec_to_hex = convert(from_srec, {
      ..ConvertOptions::new(IntelHex),
      intel_hex: hex_options,
    })
    assert_true(
      original.semantic_equal(load_firmware(hex_to_srec.bytes)),
      msg="HEX to SREC trial \{trial}",
    )
    assert_true(
      original.semantic_equal(load_firmware(srec_to_hex.bytes)),
      msg="SREC to HEX trial \{trial}",
    )
  }
}

///|
test "128 fixed-seed segmented entries preserve exact CS IP or explicitly flatten" {
  let random = PropertyRandom::{ state: 8051L, }
  for trial in 0..<128 {
    let original = {
      ..generated_image(random, trial),
      entry: Some(
        @model.EntryPoint::Segment(random.below(65536), random.below(65536)),
      ),
    }
    let from_hex = @ihex.parse_document(@ihex.encode(original))
    assert_true(original.semantic_equal(from_hex))
    let converted = convert(original, {
      ..ConvertOptions::new(SRecord),
      srecord: {
        ..@srec.WriterOptions::default(),
        flatten_segment_entry: true,
      },
    })
    let flattened = load_firmware(converted.bytes)
    assert_true(original.memory.same_memory(flattened.memory))
    match (original.entry, flattened.entry) {
      (Some(before), Some(after)) =>
        assert_eq(before.address(), after.address())
      _ => fail("entry disappeared during explicit flattening")
    }
    assert_eq(converted.warnings.length(), 1)
  }
}

///|
test "absent entry round-trips through HEX and SREC reports its zero default" {
  let image = @model.FirmwareImage::from_binary(b"entryless", 0xFFFFFFFFL - 8L)
  assert_true(image.semantic_equal(@ihex.parse_document(@ihex.encode(image))))
  let output = convert(image, ConvertOptions::new(SRecord))
  let restored = load_firmware(output.bytes)
  assert_true(image.memory.same_memory(restored.memory))
  assert_eq(restored.entry, Some(@model.EntryPoint::Linear(0L)))
  assert_eq(output.warnings.length(), 1)
}

///|
fn reference_ranges(
  categories : Array[Int],
  wanted : Int,
  base : Int64,
) -> Array[@model.AddressRange] raise @model.FirmwareError {
  let output = []
  let mut start = 0
  while start < categories.length() {
    if categories[start] != wanted {
      start += 1
      continue
    }
    let mut end = start + 1
    while end < categories.length() && categories[end] == wanted {
      end += 1
    }
    output.push(
      @model.AddressRange::new(base + start.to_int64(), base + end.to_int64()),
    )
    start = end
  }
  output
}

///|
test "256 randomized address diffs match independent dense reference categories" {
  let random = PropertyRandom::{ state: 424242L, }
  for trial in 0..<256 {
    let base = if trial % 2 == 0 { 0L } else { 0xFFFFFF00L }
    let left = @model.FirmwareImage::new()
    let right = @model.FirmwareImage::new()
    let categories = Array::make(256, 0)
    let totals = Array::make(5, 0L)
    for offset in 0..<256 {
      let category = random.below(5)
      categories[offset] = category
      totals[category] += 1L
      let value = random.below(256).to_byte()
      if category == 1 || category == 3 || category == 4 {
        left.memory.insert(base + offset.to_int64(), Bytes::from_array([value]))
      }
      if category == 2 || category == 3 || category == 4 {
        let after = if category == 3 {
          (value.to_int() ^ 1).to_byte()
        } else {
          value
        }
        right.memory.insert(
          base + offset.to_int64(),
          Bytes::from_array([after]),
        )
      }
    }
    let actual = diff_images(left, right)
    assert_eq(actual.only_left, reference_ranges(categories, 1, base))
    assert_eq(actual.only_right, reference_ranges(categories, 2, base))
    assert_eq(actual.changed, reference_ranges(categories, 3, base))
    assert_eq(actual.removed_bytes, totals[1])
    assert_eq(actual.added_bytes, totals[2])
    assert_eq(actual.changed_bytes, totals[3])
    assert_eq(actual.identical_bytes, totals[4])
    let reverse = diff_images(right, left)
    assert_eq(reverse.only_left, actual.only_right)
    assert_eq(reverse.only_right, actual.only_left)
    assert_eq(reverse.changed, actual.changed)
  }
}

///|
test "128 randomized extract erase and fill windows obey occupied-address semantics" {
  let random = PropertyRandom::{ state: 1979L, }
  for trial in 0..<128 {
    let image = generated_image(random, trial)
    let base = image.entry.unwrap().address()
    let start = base + random.below(256).to_int64()
    let end = start + random.below(256).to_int64()
    let range = @model.AddressRange::new(start, end)
    let extracted = extract_range(image, range)
    let erased = remove_range(image, range)
    let filled = fill_range(image, range, b'\xA5')
    for address in start..<end {
      assert_eq(extracted.memory.read(address), image.memory.read(address))
      assert_eq(erased.memory.read(address), None)
      assert_eq(
        filled.memory.read(address),
        Some(image.memory.read(address).unwrap_or(b'\xA5')),
      )
    }
    for segment in image.memory.segments() {
      for offset in 0..<segment.data.length() {
        let address = segment.start + offset.to_int64()
        if !range.contains(address) {
          assert_eq(erased.memory.read(address), Some(segment.data[offset]))
          assert_eq(extracted.memory.read(address), None)
          assert_eq(filled.memory.read(address), Some(segment.data[offset]))
        }
      }
    }
  }
}

///|
test "each encoded byte bit is checksum protected in both independent wire formats" {
  let hex = @ihex.Record::new(0, 0x1234, b"checksum").encode()
  let srec = @srec.Record::new(3, 0x08001234L, b"checksum").encode()
  let location : @codec.Location = {
    format: Unknown,
    line: 1,
    column_offset: 0,
    record_type: None,
  }
  for sample in [(hex, ":", 1), (srec, "S3", 2)] {
    let (record, prefix, start) = sample
    let body = @codec.decode_hex(record, start, location)
    for index in 0..<body.length() {
      for bit in 0..<8 {
        let damaged = Bytes::makei(body.length(), i => {
          if i == index {
            (body[i].to_int() ^ (1 << bit)).to_byte()
          } else {
            body[i]
          }
        })
        let wire = prefix + @codec.encode_hex(damaged)
        if prefix == ":" {
          try @ihex.parse_line(wire) catch {
            @model.FirmwareError(_) => ()
          } noraise {
            _ => fail("HEX corruption accepted at byte \{index}, bit \{bit}")
          }
        } else {
          try @srec.parse_line(wire) catch {
            @model.FirmwareError(_) => ()
          } noraise {
            _ => fail("SREC corruption accepted at byte \{index}, bit \{bit}")
          }
        }
      }
    }
  }
}

///|
test "512 deterministic malformed ASCII documents terminate with structured errors" {
  let random = PropertyRandom::{ state: 65993L, }
  for trial in 0..<512 {
    let data = Bytes::makei(random.below(40), _ => random.below(256).to_byte())
    let hex = @ihex.Record::new(0, random.below(65536), data).encode()
    let srec = @srec.Record::new(3, random.below(65536).to_int64(), data).encode()
    for mode in [@model.ParseMode::Strict, Permissive] {
      let options = { ..@model.ParseOptions::default(), mode, }
      // An ASCII invalid digit is planted in a valid-length record, while all
      // other fields remain writer-generated. Both modes must reject it.
      let hex_index = 1 + random.below(hex.length() - 1)
      let bad_hex = hex[:hex_index].to_owned() +
        "G" +
        hex[hex_index + 1:].to_owned() +
        "\n:00000001FF\n"
      try @ihex.parse_document(bad_hex, options~) catch {
        @model.FirmwareError(d) => {
          assert_eq(d.code, InvalidDigit)
          assert_eq(d.line, 1)
          assert_eq(d.column, hex_index + 1)
        }
      } noraise {
        _ => fail("invalid HEX digit accepted in trial \{trial}")
      }
      let srec_index = 2 + random.below(srec.length() - 2)
      let bad_srec = srec[:srec_index].to_owned() +
        "G" +
        srec[srec_index + 1:].to_owned() +
        "\nS70500000000FA\n"
      try @srec.parse_document(bad_srec, options~) catch {
        @model.FirmwareError(d) => {
          assert_eq(d.code, InvalidDigit)
          assert_eq(d.line, 1)
          assert_eq(d.column, srec_index + 1)
        }
      } noraise {
        _ => fail("invalid SREC digit accepted in trial \{trial}")
      }
    }
  }
}
