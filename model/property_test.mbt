///|
// This reference model is deliberately dense and restricted to 256 addresses.
// Production maps remain sparse; the oracle is independent of segment merging.
priv struct MemoryRandom {
  mut state : Int64
}

///|
fn MemoryRandom::below(self : MemoryRandom, bound : Int) -> Int {
  self.state = self.state * 16807L % 2147483647L
  (self.state % bound.to_int64()).to_int()
}

///|
test "96 deterministic sparse mutation sequences match a dense overlap oracle" {
  let random = MemoryRandom::{ state: 632714L, }
  for trial in 0..<96 {
    let base = if trial % 2 == 0 { 0L } else { 0xFFFFFF00L }
    let memory = MemoryMap::new()
    let expected : Array[Byte?] = Array::make(256, None)
    for step in 0..<128 {
      let start = random.below(256)
      let length = random.below((256 - start).min(32) + 1)
      let policy = match step % 3 {
        0 => OverlapPolicy::Reject
        1 => AllowIdentical
        _ => Overwrite
      }
      let bytes = Bytes::makei(length, i => {
        if random.below(2) == 0 {
          expected[start + i].unwrap_or(random.below(256).to_byte())
        } else {
          random.below(256).to_byte()
        }
      })
      let mut conflict : Int? = None
      let mut conflict_end = start
      for i in 0..<length {
        let bad = match expected[start + i] {
          None => false
          Some(old) =>
            policy == Reject || (policy == AllowIdentical && old != bytes[i])
        }
        if bad {
          if conflict == None {
            conflict = Some(start + i)
          }
          conflict_end = start + i
        } else if conflict != None {
          break
        }
      }
      let result = capture(() => {
        memory.insert(base + start.to_int64(), bytes, policy~)
      })
      match conflict {
        Some(first) =>
          match result {
            Err(FirmwareError(d)) => {
              assert_eq(d.code, AddressConflict)
              assert_eq(d.address, Some(base + first.to_int64()))
              assert_eq(d.end_address, Some(base + conflict_end.to_int64()))
            }
            _ => fail("accepted conflict in trial \{trial}, step \{step}")
          }
        None => {
          assert_true(
            result is Ok(_),
            msg="unexpected conflict in trial \{trial}, step \{step}",
          )
          for i in 0..<length {
            expected[start + i] = Some(bytes[i])
          }
        }
      }
      let mut payload = 0
      let mut runs = 0
      let mut occupied_before = false
      for i in 0..<256 {
        assert_eq(memory.read(base + i.to_int64()), expected[i])
        let occupied = expected[i] != None
        assert_eq(memory.contains(base + i.to_int64()), occupied)
        if occupied {
          payload += 1
          if !occupied_before {
            runs += 1
          }
        }
        occupied_before = occupied
      }
      assert_eq(memory.payload_size(), payload)
      assert_eq(memory.segment_count(), runs)
      let segments = memory.segments()
      for i in 1..<segments.length() {
        assert_true(segments[i - 1].range().end < segments[i].start)
      }
    }
    let window = AddressRange::new(base, base + 256L)
    let binary = memory.to_binary(window, fill=b'\xA5')
    for i in 0..<256 {
      assert_eq(binary[i], expected[i].unwrap_or(b'\xA5'))
    }
    let holes = memory.holes_in(window)
    for i in 0..<256 {
      let mut memberships = 0
      for hole in holes {
        if hole.contains(base + i.to_int64()) {
          memberships += 1
        }
      }
      assert_eq(memberships, if expected[i] == None { 1 } else { 0 })
    }
  }
}

///|
test "512 deterministic interval intersections and differences match set membership" {
  let random = MemoryRandom::{ state: 911L, }
  for trial in 0..<512 {
    let base = if trial % 2 == 0 { 0L } else { 0xFFFFFFC0L }
    let a = random.below(65).to_int64()
    let b = random.below(65).to_int64()
    let c = random.below(65).to_int64()
    let d = random.below(65).to_int64()
    let left = AddressRange::new(base + a.min(b), base + a.max(b))
    let right = AddressRange::new(base + c.min(d), base + c.max(d))
    let intersection = left.intersection(right)
    let differences = left.subtract(right)
    assert_eq(intersection, right.intersection(left))
    for offset in 0L..<64L {
      let address = base + offset
      let common = match intersection {
        None => false
        Some(range) => range.contains(address)
      }
      assert_eq(common, left.contains(address) && right.contains(address))
      let mut retained = 0
      for range in differences {
        assert_true(!range.is_empty())
        if range.contains(address) {
          retained += 1
        }
      }
      assert_eq(
        retained,
        if left.contains(address) && !right.contains(address) {
          1
        } else {
          0
        },
      )
    }
    let retained_size = differences.fold(init=0L, (n, range) => {
      n + range.length()
    })
    assert_eq(
      retained_size + intersection.map(r => r.length()).unwrap_or(0L),
      left.length(),
    )
  }
}

///|
test "immutable segment snapshots survive overwrite normalization and append" {
  let memory = MemoryMap::new()
  memory.insert(8L, b"before")
  let snapshot = memory.segments()
  memory.insert(9L, b"XX", policy=Overwrite)
  memory.insert(14L, b"after")
  assert_eq(snapshot.length(), 1)
  assert_eq(snapshot[0].start, 8L)
  assert_eq(snapshot[0].data, b"before")
  assert_eq(memory.segments()[0].data, b"bXXoreafter")
}

///|
test "segment cap rejects the next sparse insertion without changing existing data" {
  let memory = MemoryMap::new()
  for i in 0..<65536 {
    memory.insert(i.to_int64() * 2L, b"x")
  }
  assert_eq(memory.segment_count(), 65536)
  assert_true(
    capture(() => memory.insert(131072L, b"y"))
    is Err(FirmwareError({ code: ResourceLimit, .. })),
  )
  assert_eq(memory.payload_size(), 65536)
  assert_eq(memory.read(131070L), Some(b'x'))
  assert_eq(memory.read(131072L), None)
  // Filling a gap reduces segment count and remains legal at the cap.
  memory.insert(1L, b"b")
  assert_eq(memory.segment_count(), 65535)
  assert_eq(memory.segments()[0].data, b"xbx")
}

///|
test "zero byte binary budget permits only an empty address window" {
  let memory = MemoryMap::new()
  assert_eq(memory.to_binary(AddressRange::new(0L, 0L), max_size=0), b"")
  assert_true(
    capture(() => {
      memory.to_binary(AddressRange::new(0L, 1L), fill=b'\x00', max_size=0)
    })
    is Err(FirmwareError({ code: ResourceLimit, .. })),
  )
}

///|
test "invalid parse limits fail independently before consuming text" {
  let defaults = ParseOptions::default()
  for
    options in [
      { ..defaults, max_records: 0, },
      { ..defaults, max_records: 10000001, },
      { ..defaults, max_line_length: 10, },
      { ..defaults, max_line_length: 65537, },
      { ..defaults, max_payload: -1, },
      { ..defaults, max_payload: 64 * 1024 * 1024 + 1, },
      { ..defaults, max_text_length: -1, },
      { ..defaults, max_text_length: 256 * 1024 * 1024 + 1, },
      { ..defaults, max_warnings: -1, },
      { ..defaults, max_warnings: 65537, },
    ] {
    assert_true(
      capture(() => options.validate())
      is Err(FirmwareError({ code: InvalidOption, .. })),
    )
  }
}
