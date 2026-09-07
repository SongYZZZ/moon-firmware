///|
/// Half-open [start, end) interval. End may equal 2^32; start must be smaller.
pub struct AddressRange {
  start : Int64
  end : Int64
} derive(Eq, Debug)

///|
/// Construct a checked interval. Empty intervals are legal.
pub fn AddressRange::new(
  start : Int64,
  end : Int64,
) -> AddressRange raise FirmwareError {
  if start < 0L || end < start || end > 0x100000000L {
    raise FirmwareError(
      diagnostic(
        InvalidRange,
        "expected 0 <= start <= end <= 2^32",
        address=start,
        end_address=end,
      ),
    )
  }
  { start, end }
}

///|
/// Convert an inclusive user-facing range to the library's half-open model.
pub fn AddressRange::inclusive(
  start : Int64,
  last : Int64,
) -> AddressRange raise FirmwareError {
  if last < 0L || last > 0xFFFFFFFFL || last < start {
    raise FirmwareError(
      diagnostic(
        InvalidRange,
        "invalid inclusive address range",
        address=start,
        end_address=last,
      ),
    )
  }
  AddressRange::new(start, last + 1L)
}

///|
/// Number of addresses in the interval, without narrowing to machine Int.
pub fn AddressRange::length(self : AddressRange) -> Int64 {
  self.end - self.start
}

///|
/// Empty intervals contain no addresses.
pub fn AddressRange::is_empty(self : AddressRange) -> Bool {
  self.start == self.end
}

///|
/// Test membership using an exclusive upper bound.
pub fn AddressRange::contains(self : AddressRange, address : Int64) -> Bool {
  address >= self.start && address < self.end
}

///|
/// A nonempty intersection, or None for disjoint/touching intervals.
pub fn AddressRange::intersection(
  self : AddressRange,
  other : AddressRange,
) -> AddressRange? {
  let start = self.start.max(other.start)
  let end = self.end.min(other.end)
  if start < end {
    Some({ start, end })
  } else {
    None
  }
}

///|
/// Split around an intersection, retaining the two possible outer intervals.
pub fn AddressRange::subtract(
  self : AddressRange,
  other : AddressRange,
) -> Array[AddressRange] {
  match self.intersection(other) {
    None => if self.is_empty() { [] } else { [self] }
    Some(overlap) => {
      let result = []
      if self.start < overlap.start {
        result.push({ start: self.start, end: overlap.start })
      }
      if overlap.end < self.end {
        result.push({ start: overlap.end, end: self.end })
      }
      result
    }
  }
}

///|
/// Checked relocation of a range, useful for bootloader image rebasing.
pub fn AddressRange::shift(
  self : AddressRange,
  delta : Int64,
) -> AddressRange raise FirmwareError {
  // Validate delta before adding, including the most negative Int64 value.
  if delta < -self.start || delta > 0x100000000L - self.end {
    raise FirmwareError(
      diagnostic(AddressOverflow, "relocation exceeds 32-bit address space"),
    )
  }
  AddressRange::new(self.start + delta, self.end + delta)
}

///|
/// Display a nonempty interval with inclusive endpoints for firmware tools.
pub fn AddressRange::render(self : AddressRange) -> String {
  if self.is_empty() {
    "empty at " + hex_address(self.start)
  } else {
    hex_address(self.start) + ".." + hex_address(self.end - 1L)
  }
}

///|
/// Check a start plus byte length without overflow in either integer width.
pub fn data_range(
  address : Int64,
  length : Int,
) -> AddressRange raise FirmwareError {
  if address < 0L ||
    address > 0xFFFFFFFFL ||
    length < 0 ||
    length.to_int64() > 0x100000000L - address {
    raise FirmwareError(
      diagnostic(AddressOverflow, "data exceeds 32-bit address space", address~),
    )
  }
  AddressRange::new(address, address + length.to_int64())
}
