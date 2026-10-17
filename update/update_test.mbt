///|
fn make_image(pieces : Array[(UInt64, Bytes)]) -> @image.FirmwareImage {
  let chunks = pieces.map(p => @image.FirmwareChunk::create(p.0, p.1).unwrap())
  @image.FirmwareImage::from_chunks(chunks).unwrap()
}

///|
fn profile() -> @update.TargetProfile {
  {
    name: "synthetic-NOR",
    program_unit: 4,
    sectors: [
      { name: "small", start: 0x1000UL, size: 16, },
      { name: "large", start: 0x1010UL, size: 32, },
    ],
    writable: [
      { name: "application", start: 0x1000UL, end_exclusive: 0x1030UL, },
    ],
    protected_ranges: [],
    max_plan_bytes: 1024,
  }
}

///|
fn baseline() -> @image.FirmwareImage {
  make_image([(0x1000UL, Bytes::from_array(Array::make(48, b'\xA5')))])
}

///|
fn plan_error(
  old : @image.FirmwareImage,
  delta : @image.FirmwareImage,
  target : @update.TargetProfile,
) -> String raise {
  try @update.plan_update(old, delta, target) catch {
    @update.UpdateError(code, _, _) => code
  } noraise {
    _ => fail("expected planning refusal")
  }
}

///|
fn profile_error(target : @update.TargetProfile) -> String raise {
  try @update.validate_profile(target) catch {
    @update.UpdateError(code, _, _) => code
  } noraise {
    _ => fail("expected invalid target")
  }
}

///|
test "zero-to-one update erases and restores every omitted baseline byte" {
  let old = baseline()
  let delta = make_image([(0x1018UL, b"\xFF")])
  let plan = @update.plan_update(old, delta, profile())
  assert_eq(plan.erase_count(), 1)
  assert_eq(plan.sector_count(), 1)
  assert_eq(plan.changed_bytes(), 1)
  assert_eq(plan.program_bytes(), 32)
  let resultImage = @update.simulate_update(plan, old)
  for offset = 0; offset < 48; offset = offset + 1 {
    assert_eq(
      resultImage.byte_at(0x1000UL + offset.to_uint64()),
      Some(if offset == 24 { b'\xFF' } else { b'\xA5' }),
    )
  }
  assert_eq(old.byte_at(0x1018UL), Some(b'\xA5'))
}

///|
test "one-to-zero update uses one aligned program unit with no erase" {
  let old = baseline()
  let plan = @update.plan_update(
    old,
    make_image([(0x1019UL, b"\xA4")]),
    profile(),
  )
  assert_eq(plan.erase_count(), 0)
  assert_eq(plan.program_bytes(), 4)
  assert_eq(@update.simulate_update(plan, old).byte_at(0x1019UL), Some(b'\xA4'))
}

///|
test "fully erased target needs erase and verification but no program units" {
  let old = baseline()
  let plan = @update.plan_update(
    old,
    make_image([(0x1000UL, Bytes::from_array(Array::make(16, b'\xFF')))]),
    profile(),
  )
  assert_eq(plan.erase_count(), 1)
  assert_eq(plan.program_bytes(), 0)
  assert_eq(
    @update.simulate_update(plan, old)
    .read_range(0x1000UL, 16, RejectMissing, 16)
    .unwrap(),
    Bytes::from_array(Array::make(16, b'\xFF')),
  )
}

///|
test "different erase geometries are planned independently" {
  let plan = @update.plan_update(
    baseline(),
    make_image([(0x1001UL, b"\xFF"), (0x1020UL, b"\xFF")]),
    profile(),
  )
  assert_eq(plan.sector_count(), 2)
  assert_eq(plan.erase_count(), 2)
  assert_eq(plan.program_bytes(), 48)
}

///|
test "unchanged overlay produces no erase or program operations" {
  let plan = @update.plan_update(
    baseline(),
    make_image([(0x1000UL, b"\xA5")]),
    profile(),
  )
  assert_eq(plan.sector_count(), 0)
  assert_eq(plan.program_bytes(), 0)
}

///|
test "empty overlay leaves observed image unchanged" {
  let old = baseline()
  let plan = @update.plan_update(old, make_image([]), profile())
  assert_true(@update.simulate_update(plan, old) == old)
}

///|
test "incomplete baseline is unknown rather than erased FF" {
  assert_eq(
    plan_error(
      make_image([(0x1000UL, b"\xA5")]),
      make_image([(0x1000UL, b"\xFF")]),
      profile(),
    ),
    "MissingBaseline",
  )
}

///|
test "missing baseline at the changed byte cannot be invented" {
  assert_eq(
    plan_error(make_image([]), make_image([(0x1000UL, b"\xFF")]), profile()),
    "MissingBaseline",
  )
}

///|
test "direct protected byte modification is refused" {
  let target = {
    ..profile(),
    protected_ranges: [
      { name: "serial", start: 0x1000UL, end_exclusive: 0x1001UL, },
    ],
  }
  assert_eq(
    plan_error(baseline(), make_image([(0x1000UL, b"\xA4")]), target),
    "ProtectedWrite",
  )
}

///|
test "erase collateral on unchanged calibration bytes is refused" {
  let target = {
    ..profile(),
    protected_ranges: [
      { name: "calibration", start: 0x102CUL, end_exclusive: 0x1030UL, },
    ],
  }
  assert_eq(
    plan_error(baseline(), make_image([(0x1010UL, b"\xFF")]), target),
    "ProtectedErase",
  )
}

///|
test "read-modify-write cannot legalize a protected program unit" {
  let target = {
    ..profile(),
    protected_ranges: [
      { name: "serial", start: 0x1003UL, end_exclusive: 0x1004UL, },
    ],
  }
  assert_eq(
    plan_error(baseline(), make_image([(0x1000UL, b"\xA4")]), target),
    "ProtectedProgramUnit",
  )
}

///|
test "direct program can avoid protected bytes in a different unit" {
  let target = {
    ..profile(),
    protected_ranges: [
      { name: "serial", start: 0x1004UL, end_exclusive: 0x1008UL, },
    ],
  }
  let plan = @update.plan_update(
    baseline(),
    make_image([(0x1000UL, b"\xA4")]),
    target,
  )
  assert_eq(plan.erase_count(), 0)
  assert_eq(plan.program_bytes(), 4)
}

///|
test "erase may not cross outside the writable partition" {
  let target = {
    ..profile(),
    writable: [
      { name: "application", start: 0x1000UL, end_exclusive: 0x1008UL, },
    ],
  }
  assert_eq(
    plan_error(baseline(), make_image([(0x1000UL, b"\xFF")]), target),
    "EraseOutsideWritable",
  )
}

///|
test "program granularity may not cross the writable partition" {
  let target = {
    ..profile(),
    writable: [
      { name: "application", start: 0x1000UL, end_exclusive: 0x1001UL, },
    ],
  }
  assert_eq(
    plan_error(baseline(), make_image([(0x1000UL, b"\xA4")]), target),
    "ProtectedProgramUnit",
  )
}

///|
test "byte outside erase geometry is refused even when unchanged" {
  assert_eq(
    plan_error(baseline(), make_image([(0x2000UL, b"\x00")]), profile()),
    "OutsideGeometry",
  )
}

///|
test "affected sector budget is checked before baseline reconstruction" {
  let target = { ..profile(), max_plan_bytes: 16, }
  assert_eq(
    plan_error(baseline(), make_image([(0x1010UL, b"\xFF")]), target),
    "ResourceLimit",
  )
}

///|
test "sum of affected sectors is bounded" {
  let target = { ..profile(), max_plan_bytes: 32, }
  assert_eq(
    plan_error(
      baseline(),
      make_image([(0x1000UL, b"\xFF"), (0x1010UL, b"\xFF")]),
      target,
    ),
    "ResourceLimit",
  )
}

///|
test "stale device snapshot is rejected byte-exactly before simulation" {
  let old = baseline()
  let plan = @update.plan_update(
    old,
    make_image([(0x1000UL, b"\xFF")]),
    profile(),
  )
  let device = old.write(0x1008UL, b"\xA4").unwrap()
  try @update.simulate_update(plan, device) catch {
    @update.UpdateError(code, _, address) => {
      assert_eq(code, "StaleBaseline")
      assert_eq(address, Some(0x1000UL))
    }
  } noraise {
    _ => fail("expected stale baseline refusal")
  }
  assert_eq(device.byte_at(0x1000UL), Some(b'\xA5'))
}

///|
test "stale second sector is checked before all operations" {
  let old = baseline()
  let plan = @update.plan_update(
    old,
    make_image([(0x1000UL, b"\xFF"), (0x1010UL, b"\xFF")]),
    profile(),
  )
  let device = old.write(0x102FUL, b"\xA4").unwrap()
  try @update.simulate_update(plan, device) catch {
    @update.UpdateError(code, _, _) => assert_eq(code, "StaleBaseline")
  } noraise {
    _ => fail("expected stale second sector refusal")
  }
}

///|
test "simulation preserves outside sectors and entry metadata" {
  let old = baseline().write(0x3000UL, b"keep").unwrap()
  let plan = @update.plan_update(
    old,
    make_image([(0x1000UL, b"\x00")]),
    profile(),
  )
  let resultImage = @update.simulate_update(plan, old)
  assert_eq(
    resultImage.read_range(0x3000UL, 4, RejectMissing, 4).unwrap(),
    b"keep",
  )
}

///|
test "manifest is deterministic and places preconditions before all writes" {
  let plan = @update.plan_update(
    baseline(),
    make_image([(0x1000UL, b"\xFF"), (0x1010UL, b"\xFF")]),
    profile(),
  )
  let json = plan.to_json()
  assert_eq(json.stringify(), plan.to_json().stringify())
  guard json is Object(fields) else { fail("expected object") }
  guard fields.get("operations") is Some(Array(operations)) else {
    fail("expected operations")
  }
  for index = 0; index < 2; index = index + 1 {
    guard operations[index] is Object(op) else { fail("expected operation") }
    assert_eq(op.get("op"), Some("check_preimage".to_json()))
  }
}

///|
test "result evidence comes from actual replay bytes and rejects an incorrect image" {
  let old = baseline()
  let plan = @update.plan_update(
    old,
    make_image([(0x1000UL, b"\x00")]),
    profile(),
  )
  let replayed = @update.simulate_update(plan, old)
  guard plan.verify_result(replayed) is Array(items) else {
    fail("expected evidence array")
  }
  assert_eq(items.length(), 1)
  guard items[0] is Object(fields) else { fail("expected evidence object") }
  assert_eq(
    fields.get("actual_hex"),
    Some(
      @image.encode_hex_bytes(
        replayed.read_range(0x1000UL, 16, RejectMissing, 16).unwrap(),
      ).to_json(),
    ),
  )
  try plan.verify_result(old) catch {
    @update.UpdateError(code, _, _) => assert_eq(code, "VerifyFailed")
  } noraise {
    _ => fail("incorrect result cannot be marked verified")
  }
}

///|
test "target rejects overlapping erase sectors" {
  assert_eq(
    profile_error({
      ..profile(),
      sectors: [
        { name: "a", start: 0x1000UL, size: 16, },
        { name: "b", start: 0x1008UL, size: 16, },
      ],
    }),
    "InvalidProfile",
  )
}

///|
test "target rejects unaligned and non-power-of-two program units" {
  for unit in [0, 3, 512] {
    assert_eq(
      profile_error({ ..profile(), program_unit: unit, }),
      "InvalidProfile",
    )
  }
  assert_eq(
    profile_error({
      ..profile(),
      sectors: [{ name: "a", start: 0x1001UL, size: 16, }],
    }),
    "InvalidProfile",
  )
}

///|
test "target rejects overflow, invalid sizes and duplicate identities" {
  assert_eq(
    profile_error({
      ..profile(),
      sectors: [{ name: "a", start: 0xFFFFFFFCUL, size: 16, }],
    }),
    "InvalidProfile",
  )
  assert_eq(
    profile_error({
      ..profile(),
      sectors: [{ name: "a", start: 0UL, size: 0, }],
    }),
    "InvalidProfile",
  )
  assert_eq(
    profile_error({
      ..profile(),
      sectors: [
        { name: "a", start: 0x1000UL, size: 16, },
        { name: "a", start: 0x1010UL, size: 16, },
      ],
    }),
    "InvalidProfile",
  )
}

///|
test "target supports sectors ending exactly at the 32-bit limit" {
  let target = {
    ..profile(),
    sectors: [{ name: "last", start: 0xFFFFFFF0UL, size: 16, }],
    writable: [
      { name: "last", start: 0xFFFFFFF0UL, end_exclusive: 0x100000000UL, },
    ],
  }
  let old = make_image([
    (0xFFFFFFF0UL, Bytes::from_array(Array::make(16, b'\xFF'))),
  ])
  let plan = @update.plan_update(
    old,
    make_image([(0xFFFFFFFFUL, b"\x00")]),
    target,
  )
  assert_eq(
    @update.simulate_update(plan, old).byte_at(0xFFFFFFFFUL),
    Some(b'\x00'),
  )
}

///|
test "upstream parsing is actually used for both HEX and SREC" {
  let original = make_image([(0x1000UL, b"abcd")])
  for text in [original.to_intel_hex().unwrap(), original.to_srecord().unwrap()] {
    assert_eq(@update.parse_update_image(text).segments(), original.segments())
  }
}

///|
test "upstream parser refuses checksum corruption" {
  try @update.parse_update_image(":01100000AA00\n:00000001FF") catch {
    @update.UpdateError(code, _, _) => assert_eq(code, "InputFormat")
  } noraise {
    _ => fail("expected checksum refusal")
  }
}

///|
test "overlay entry metadata does not change the baseline execution entry" {
  let chunk = @image.FirmwareChunk::create(0x1000UL, b"\x00").unwrap()
  let overlay = @image.FirmwareImage::from_chunks(
    [chunk],
    entry_point=Some(0x1000UL),
  ).unwrap()
  let old = @image.FirmwareImage::from_chunks(
    [
      @image.FirmwareChunk::create(
        0x1000UL,
        Bytes::from_array(Array::make(48, b'\xA5')),
      ).unwrap(),
    ],
    entry_point=Some(0x1001UL),
  ).unwrap()
  let plan = @update.plan_update(old, overlay, profile())
  assert_eq(@update.simulate_update(plan, old).entry_point(), Some(0x1001UL))
}

///|
test "deterministic updates preserve every unmentioned byte under NOR replay" {
  let mut seed = 12345U
  for iteration = 0; iteration < 64; iteration = iteration + 1 {
    let old_values = Array::make(48, b'\xFF')
    for index = 0; index < 48; index = index + 1 {
      seed = seed * 1664525U + 1013904223U
      old_values[index] = (seed >> 24).to_byte()
    }
    let offset = iteration % 48
    let next = iteration.to_byte()
    let old = make_image([(0x1000UL, Bytes::from_array(old_values))])
    let plan = @update.plan_update(
      old,
      make_image([(0x1000UL + offset.to_uint64(), Bytes::from_array([next]))]),
      profile(),
    )
    let resultImage = @update.simulate_update(plan, old)
    for index = 0; index < 48; index = index + 1 {
      assert_eq(
        resultImage.byte_at(0x1000UL + index.to_uint64()),
        Some(if index == offset { next } else { old_values[index] }),
      )
    }
  }
}
