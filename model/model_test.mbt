///|
test "empty map has no invented bounds" {
  let m = MemoryMap::new()
  assert_eq(m.payload_size(), 0)
  assert_eq(m.segment_count(), 0)
  assert_eq(m.bounds(), None)
  assert_eq(m.read(0L), None)
}

///|
test "adjacent ascending records normalize" {
  let m = MemoryMap::new()
  m.insert(4096L, b"ab")
  m.insert(4098L, b"cd")
  assert_eq(m.segment_count(), 1)
  assert_eq(m.segments()[0].data, b"abcd")
}

///|
test "adjacent descending records normalize" {
  let m = MemoryMap::new()
  m.insert(4098L, b"cd")
  m.insert(4096L, b"ab")
  assert_eq(m.segments()[0].data, b"abcd")
}

///|
test "bridge joins both neighbors" {
  let m = MemoryMap::new()
  m.insert(10L, b"ab")
  m.insert(14L, b"ef")
  m.insert(12L, b"cd")
  assert_eq(m.segment_count(), 1)
  assert_eq(m.segments()[0].data, b"abcdef")
}

///|
test "rejected overlap is transactional" {
  let m = MemoryMap::new()
  m.insert(10L, b"abc")
  let before = m.copy()
  let error = capture(() => m.insert(11L, b"XYZ"))
  assert_true(
    error
    is Err(
      FirmwareError(
        {
          code: AddressConflict,
          address: Some(11L),
          end_address: Some(12L),
          ..
        }
      )
    ),
  )
  assert_true(m.same_memory(before))
}

///|
test "identical overlap extends a segment" {
  let m = MemoryMap::new()
  m.insert(10L, b"abc")
  m.insert(11L, b"bcde", policy=AllowIdentical)
  assert_eq(m.segments()[0].data, b"abcde")
}

///|
test "identical policy rejects first changed run" {
  let m = MemoryMap::new()
  m.insert(0L, b"abcdef")
  let r = capture(() => m.insert(0L, b"aXYdeZ", policy=AllowIdentical))
  assert_true(
    r is Err(FirmwareError({ address: Some(1L), end_address: Some(2L), .. })),
  )
}

///|
test "overwrite preserves outside bytes" {
  let m = MemoryMap::new()
  m.insert(0L, b"abcdef")
  m.insert(2L, b"XY", policy=Overwrite)
  assert_eq(m.segments()[0].data, b"abXYef")
  assert_eq(m.payload_size(), 6)
}

///|
test "overwrite crossing several segments" {
  let m = MemoryMap::new()
  m.insert(0L, b"ab")
  m.insert(4L, b"ef")
  m.insert(1L, b"1234", policy=Overwrite)
  assert_eq(m.segments()[0].data, b"a1234f")
}

///|
test "sparse highest address uses just payload memory" {
  let m = MemoryMap::new()
  m.insert(0L, b"a")
  m.insert(0xFFFFFFFFL, b"z")
  assert_eq(m.payload_size(), 2)
  assert_eq(m.highest_address(), Some(0xFFFFFFFFL))
  assert_eq(m.gaps()[0].length(), 0xFFFFFFFEL)
}

///|
test "data end overflow is diagnosed" {
  let m = MemoryMap::new()
  assert_true(
    capture(() => m.insert(0xFFFFFFFFL, b"ab"))
    is Err(FirmwareError({ code: AddressOverflow, .. })),
  )
}

///|
test "negative address is diagnosed" {
  assert_true(capture(() => data_range(-1L, 1)) is Err(_))
}

///|
test "empty insertion does not create segment" {
  let m = MemoryMap::new()
  m.insert(1234L, b"")
  assert_eq(m.segment_count(), 0)
}

///|
test "slice through segment interiors retains addresses" {
  let m = MemoryMap::new()
  m.insert(10L, b"abcdef")
  let cut = m.slice(AddressRange::new(12L, 15L))
  assert_eq(cut.lowest_address(), Some(12L))
  assert_eq(cut.segments()[0].data, b"cde")
}

///|
test "slice across gap retains sparsity" {
  let m = MemoryMap::new()
  m.insert(10L, b"abcd")
  m.insert(20L, b"efgh")
  let cut = m.slice(AddressRange::new(12L, 22L))
  assert_eq(cut.segment_count(), 2)
  assert_eq(cut.payload_size(), 4)
}

///|
test "slice outside map is empty" {
  let m = FirmwareImage::from_binary(b"abc", 0L).memory
  assert_eq(m.slice(AddressRange::new(10L, 20L)).payload_size(), 0)
}

///|
test "binary gaps require explicit fill" {
  let m = MemoryMap::new()
  m.insert(1L, b"x")
  let range = AddressRange::new(0L, 3L)
  assert_true(
    capture(() => m.to_binary(range))
    is Err(FirmwareError({ code: GapRequiresFill, .. })),
  )
  assert_eq(m.to_binary(range, fill=b'\xFF'), b"\xFFx\xFF")
}

///|
test "binary sparse output size fails before allocating" {
  let m = MemoryMap::new()
  assert_true(
    capture(() => m.to_binary(AddressRange::new(0L, 0x100000000L), fill=b'\xFF'))
    is Err(FirmwareError({ code: ResourceLimit, .. })),
  )
}

///|
test "read distinguishes zero byte and hole" {
  let m = FirmwareImage::from_binary(b"\x00", 10L).memory
  assert_eq(m.read(10L), Some(b'\x00'))
  assert_eq(m.read(11L), None)
  assert_true(!m.contains(9L))
}

///|
test "copy cannot mutate original" {
  let m = FirmwareImage::from_binary(b"abc", 0L).memory
  let other = m.copy()
  other.insert(0L, b"z", policy=Overwrite)
  assert_eq(m.read(0L), Some(b'a'))
}

///|
test "half open range permits sentinel end" {
  let r = AddressRange::inclusive(0xFFFFFFFFL, 0xFFFFFFFFL)
  assert_eq(r.end, 0x100000000L)
  assert_eq(r.length(), 1L)
  assert_true(!r.contains(r.end))
}

///|
test "reversed ranges fail" {
  assert_true(capture(() => AddressRange::new(10L, 9L)) is Err(_))
  assert_true(capture(() => AddressRange::inclusive(10L, 9L)) is Err(_))
}

///|
test "subtract middle returns two ranges" {
  let r = AddressRange::new(0L, 10L).subtract(AddressRange::new(3L, 6L))
  assert_eq(r.length(), 2)
  assert_eq(r[0].length(), 3L)
  assert_eq(r[1].length(), 4L)
}

///|
test "touching ranges have no intersection" {
  assert_eq(
    AddressRange::new(0L, 10L).intersection(AddressRange::new(10L, 20L)),
    None,
  )
}

///|
test "relocation overflow handles minimum Int64" {
  let r = AddressRange::new(10L, 20L)
  assert_true(capture(() => r.shift(-9223372036854775807L - 1L)) is Err(_))
  assert_eq(r.shift(-10L).start, 0L)
}

///|
test "segment execution uses CS times sixteen plus IP" {
  assert_eq(EntryPoint::Segment(0x1234, 0x5678).address(), 0x179B8L)
  assert_true(capture(() => EntryPoint::Segment(65536, 0).address()) is Err(_))
}

///|
test "range render uses inclusive human endpoints" {
  assert_eq(AddressRange::new(16L, 32L).render(), "0x00000010..0x0000001F")
}

///|
test "holes in window include leading and trailing gap" {
  let m = FirmwareImage::from_binary(b"ab", 2L).memory
  let holes = m.holes_in(AddressRange::new(0L, 6L))
  assert_eq(holes.length(), 2)
  assert_eq(holes[0].end, 2L)
  assert_eq(holes[1].start, 4L)
}

///|
fn[T] capture(action : () -> T raise FirmwareError) -> Result[T, FirmwareError] {
  Ok(action()) catch {
    error => Err(error)
  }
}
