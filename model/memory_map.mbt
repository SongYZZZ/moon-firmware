///|
/// Immutable snapshot of one contiguous occupied region.
pub struct MemorySegment {
  start : Int64
  data : Bytes
} derive(Eq, Debug)

///|
/// Checked segment constructor; bytes are immutable in the public API.
pub fn MemorySegment::new(
  start : Int64,
  data : Bytes,
) -> MemorySegment raise FirmwareError {
  ignore(data_range(start, data.length()))
  { start, data, }
}

///|
/// Interval occupied by this segment.
pub fn MemorySegment::range(self : MemorySegment) -> AddressRange {
  { start: self.start, end: self.start + self.data.length().to_int64(), }
}

///|
/// Internal growable data avoids quadratic copying for ascending tiny records.
priv struct StoredSegment {
  start : Int64
  data : Array[Byte]
}

///|
/// Sorted, nonempty, disjoint and nonadjacent segments. No allocation for gaps.
pub struct MemoryMap {
  priv mut storage : Array[StoredSegment]
  priv mut size : Int
}

///|
/// An empty sparse map. Insertions are transactional on validation failure.
pub fn MemoryMap::new() -> MemoryMap {
  { storage: [], size: 0, }
}

///|
/// Payload size rather than the address span.
pub fn MemoryMap::payload_size(self : MemoryMap) -> Int {
  self.size
}

///|
/// Count normalized occupied regions.
pub fn MemoryMap::segment_count(self : MemoryMap) -> Int {
  self.storage.length()
}

///|
/// Return immutable snapshots, never the map's mutable internal buffers.
pub fn MemoryMap::segments(self : MemoryMap) -> Array[MemorySegment] {
  self.storage.map(s => { start: s.start, data: Bytes::from_array(s.data), })
}

///|
/// Independent mutable copy for transactional multi-image operations.
pub fn MemoryMap::copy(self : MemoryMap) -> MemoryMap {
  {
    storage: self.storage.map(s => { start: s.start, data: s.data.copy(), }),
    size: self.size,
  }
}

///|
/// Lowest occupied address, or None for an empty map.
pub fn MemoryMap::lowest_address(self : MemoryMap) -> Int64? {
  if self.storage.is_empty() {
    None
  } else {
    Some(self.storage[0].start)
  }
}

///|
/// Highest occupied address (inclusive), or None.
pub fn MemoryMap::highest_address(self : MemoryMap) -> Int64? {
  if self.storage.is_empty() {
    None
  } else {
    let s = self.storage[self.storage.length() - 1]
    Some(s.start + s.data.length().to_int64() - 1L)
  }
}

///|
/// Span including internal gaps; empty maps have no bounds.
pub fn MemoryMap::bounds(self : MemoryMap) -> AddressRange? {
  match (self.lowest_address(), self.highest_address()) {
    (Some(start), Some(last)) => Some({ start, end: last + 1L, })
    _ => None
  }
}

///|
/// Binary search for the last segment starting at or before an address.
fn MemoryMap::locate(self : MemoryMap, address : Int64) -> Int {
  let mut low = 0
  let mut high = self.storage.length()
  while low < high {
    let mid = low + (high - low) / 2
    if self.storage[mid].start <= address {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low - 1
}

///|
/// Read an occupied byte; holes and out-of-range addresses return None.
pub fn MemoryMap::read(self : MemoryMap, address : Int64) -> Byte? {
  let index = self.locate(address)
  if index < 0 {
    return None
  }
  let s = self.storage[index]
  let offset = address - s.start
  if offset >= 0L && offset < s.data.length().to_int64() {
    Some(s.data[offset.to_int()])
  } else {
    None
  }
}

///|
/// True only for occupied addresses; does not treat gaps as zero bytes.
pub fn MemoryMap::contains(self : MemoryMap, address : Int64) -> Bool {
  self.read(address) != None
}

///|
/// Insert data using a checked overlap policy. Limits cap payload at 64 MiB.
pub fn MemoryMap::insert(
  self : MemoryMap,
  address : Int64,
  bytes : Bytes,
  policy? : OverlapPolicy = Reject,
) -> Unit raise FirmwareError {
  let incoming = data_range(address, bytes.length())
  if bytes.is_empty() {
    return
  }
  // Fast append is the common path for text-record decoders.
  let n = self.storage.length()
  if n > 0 {
    let last = self.storage[n - 1]
    let end = last.start + last.data.length().to_int64()
    if address == end {
      self.check_size(bytes.length())
      for b in bytes {
        last.data.push(b)
      }
      self.size += bytes.length()
      return
    }
    if address > end {
      self.check_size(bytes.length())
      self.check_segments(n + 1)
      self.storage.push({ start: address, data: bytes.to_array(), })
      self.size += bytes.length()
      return
    }
  }
  let mut first = self.locate(address)
  if first < 0 {
    first = 0
  }
  if first < n {
    let s = self.storage[first]
    if s.start + s.data.length().to_int64() < address {
      first += 1
    }
  }
  let mut stop = first
  let mut start = address
  let mut end = incoming.end
  let mut removed = 0
  while stop < n && self.storage[stop].start <= end {
    let s = self.storage[stop]
    let old_end = s.start + s.data.length().to_int64()
    let overlap_start = address.max(s.start)
    let overlap_end = incoming.end.min(old_end)
    if overlap_start < overlap_end && policy != Overwrite {
      let mut conflict_start : Int64? = None
      let mut conflict_end = overlap_start
      let mut pos = overlap_start
      while pos < overlap_end {
        let different = policy == Reject ||
          s.data[(pos - s.start).to_int()] != bytes[(pos - address).to_int()]
        if different {
          if conflict_start == None {
            conflict_start = Some(pos)
          }
          conflict_end = pos + 1L
        } else if conflict_start != None {
          break
        }
        pos += 1L
      }
      if conflict_start is Some(conflict) {
        raise FirmwareError(
          diagnostic(
            AddressConflict,
            "address overlap rejected",
            address=conflict,
            end_address=conflict_end - 1L,
          ),
        )
      }
    }
    start = start.min(s.start)
    end = end.max(old_end)
    removed += s.data.length()
    stop += 1
  }
  let length64 = end - start
  if length64 > (64 * 1024 * 1024).to_int64() {
    raise FirmwareError(
      diagnostic(ResourceLimit, "contiguous payload exceeds 64 MiB"),
    )
  }
  let length = length64.to_int()
  self.check_size(length - removed)
  self.check_segments(n - (stop - first) + 1)
  let data = Array::make(length, b'\x00')
  for i in first..<stop {
    let s = self.storage[i]
    let offset = (s.start - start).to_int()
    for j in 0..<s.data.length() {
      data[offset + j] = s.data[j]
    }
  }
  let offset = (address - start).to_int()
  for i in 0..<bytes.length() {
    data[offset + i] = bytes[i]
  }
  let result = []
  for i in 0..<first {
    result.push(self.storage[i])
  }
  result.push({ start, data, })
  for i in stop..<n {
    result.push(self.storage[i])
  }
  self.storage = result
  self.size += length - removed
}

///|
fn MemoryMap::check_size(
  self : MemoryMap,
  added : Int,
) -> Unit raise FirmwareError {
  if added > 64 * 1024 * 1024 - self.size {
    raise FirmwareError(diagnostic(ResourceLimit, "payload exceeds 64 MiB"))
  }
}

///|
fn MemoryMap::check_segments(
  _self : MemoryMap,
  count : Int,
) -> Unit raise FirmwareError {
  if count > 65536 {
    raise FirmwareError(
      diagnostic(ResourceLimit, "segment count exceeds 65536"),
    )
  }
}

///|
/// Internal holes only. No leading zero-to-first-address gap is invented.
pub fn MemoryMap::gaps(self : MemoryMap) -> Array[AddressRange] {
  let result = []
  for i in 1..<self.storage.length() {
    let previous = self.storage[i - 1]
    result.push({
      start: previous.start + previous.data.length().to_int64(),
      end: self.storage[i].start,
    })
  }
  result
}

///|
/// Copy just the occupied intersections with a checked interval.
pub fn MemoryMap::slice(
  self : MemoryMap,
  range : AddressRange,
) -> MemoryMap raise FirmwareError {
  let result = MemoryMap::new()
  for s in self.storage {
    let segment_range : AddressRange = {
      start: s.start,
      end: s.start + s.data.length().to_int64(),
    }
    if segment_range.intersection(range) is Some(overlap) {
      let from = (overlap.start - s.start).to_int()
      let until = (overlap.end - s.start).to_int()
      result.insert(overlap.start, Bytes::from_array(s.data[from:until]))
    }
  }
  result
}

///|
/// Holes in an explicit window, including leading and trailing holes.
pub fn MemoryMap::holes_in(
  self : MemoryMap,
  range : AddressRange,
) -> Array[AddressRange] {
  let result = []
  let mut cursor = range.start
  for s in self.storage {
    let start = s.start.max(range.start)
    let end = (s.start + s.data.length().to_int64()).min(range.end)
    if start < end {
      if cursor < start {
        result.push({ start: cursor, end: start, })
      }
      cursor = end
    }
  }
  if cursor < range.end {
    result.push({ start: cursor, end: range.end, })
  }
  result
}

///|
/// Dense bytes from an explicit interval. Refuse holes unless fill is supplied.
pub fn MemoryMap::to_binary(
  self : MemoryMap,
  range : AddressRange,
  fill? : Byte,
  max_size? : Int = 16 * 1024 * 1024,
) -> Bytes raise FirmwareError {
  if max_size < 0 ||
    max_size > 64 * 1024 * 1024 ||
    range.length() > max_size.to_int64() {
    raise FirmwareError(
      diagnostic(ResourceLimit, "binary output exceeds configured limit"),
    )
  }
  let holes = self.holes_in(range)
  if fill == None && !holes.is_empty() {
    let hole = holes[0]
    raise FirmwareError(
      diagnostic(
        GapRequiresFill,
        "binary output has gaps; specify fill",
        address=hole.start,
        end_address=hole.end - 1L,
      ),
    )
  }
  let data = Array::make(range.length().to_int(), fill.unwrap_or(b'\x00'))
  for s in self.storage {
    let from = s.start.max(range.start)
    let end = (s.start + s.data.length().to_int64()).min(range.end)
    let mut pos = from
    while pos < end {
      data[(pos - range.start).to_int()] = s.data[(pos - s.start).to_int()]
      pos += 1L
    }
  }
  Bytes::from_array(data)
}

///|
/// Semantic memory equality, independent of source record boundaries.
pub fn MemoryMap::same_memory(self : MemoryMap, other : MemoryMap) -> Bool {
  if self.size != other.size || self.storage.length() != other.storage.length() {
    return false
  }
  for i in 0..<self.storage.length() {
    let a = self.storage[i]
    let b = other.storage[i]
    if a.start != b.start || a.data != b.data {
      return false
    }
  }
  true
}
