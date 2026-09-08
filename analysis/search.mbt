///|
/// Bytes plus a per-bit mask. A zero mask bit is a wildcard; an all-ones mask
/// performs an exact byte comparison.
pub struct MaskedPattern {
  bytes : Bytes
  mask : Bytes
} derive(Eq, Debug)

///|
/// Construct an exact nonempty pattern.
pub fn MaskedPattern::exact(
  bytes : Bytes,
) -> MaskedPattern raise @model.FirmwareError {
  if bytes.is_empty() {
    raise @model.FirmwareError(
      @model.diagnostic(InvalidOption, "search pattern cannot be empty"),
    )
  }
  if bytes.length() > 1024 * 1024 {
    raise @model.FirmwareError(
      @model.diagnostic(ResourceLimit, "search pattern exceeds 1 MiB"),
    )
  }
  { bytes, mask: Bytes::make(bytes.length(), 0xFF), }
}

///|
/// Construct a masked nonempty pattern. Pattern and mask lengths must match.
pub fn MaskedPattern::new(
  bytes : Bytes,
  mask : Bytes,
) -> MaskedPattern raise @model.FirmwareError {
  if bytes.is_empty() || bytes.length() != mask.length() {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "search bytes and mask must have the same nonzero length",
      ),
    )
  }
  if bytes.length() > 1024 * 1024 {
    raise @model.FirmwareError(
      @model.diagnostic(ResourceLimit, "search pattern exceeds 1 MiB"),
    )
  }
  { bytes, mask, }
}

///|
fn pattern_matches(data : Bytes, offset : Int, pattern : MaskedPattern) -> Bool {
  for index in 0..<pattern.bytes.length() {
    let observed = data[offset + index].to_int()
    let mask = pattern.mask[index].to_int()
    if (observed & mask) != (pattern.bytes[index].to_int() & mask) {
      return false
    }
  }
  true
}

///|
/// Find pattern starts in normalized occupied segments. Matches may cross an
/// original record boundary after normalization, but never cross an address gap.
/// Overlapping matches are returned in ascending address order.
pub fn find_pattern(
  image : @model.FirmwareImage,
  pattern : MaskedPattern,
  within? : @model.AddressRange,
  max_matches? : Int = 100000,
) -> Array[Int64] raise @model.FirmwareError {
  if max_matches < 0 || max_matches > 1000000 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "match limit must be between 0 and 1000000",
      ),
    )
  }
  let result = []
  for segment in image.memory.segments() {
    let searched = match within {
      Some(window) => segment.range().intersection(window)
      None => Some(segment.range())
    }
    if searched is Some(range) {
      let from = (range.start - segment.start).to_int()
      let until = (range.end - segment.start).to_int()
      let last = until - pattern.bytes.length()
      if last >= from {
        for offset in from..<=last {
          if pattern_matches(segment.data, offset, pattern) {
            if result.length() >= max_matches {
              raise @model.FirmwareError(
                @model.diagnostic(ResourceLimit, "pattern match limit exceeded"),
              )
            }
            result.push(segment.start + offset.to_int64())
          }
        }
      }
    }
  }
  result
}

///|
/// One printable ASCII run, retaining its absolute firmware address and bytes.
pub struct AsciiSpan {
  address : Int64
  bytes : Bytes
} derive(Eq, Debug)

///|
fn printable_ascii(byte : Byte) -> Bool {
  let value = byte.to_int()
  value >= 32 && value <= 126
}

///|
/// Extract printable ASCII runs from occupied data. A gap always terminates a
/// run. Limits bound both returned objects and retained bytes.
pub fn find_ascii_strings(
  image : @model.FirmwareImage,
  min_length? : Int = 4,
  max_strings? : Int = 10000,
  max_retained_bytes? : Int = 16 * 1024 * 1024,
) -> Array[AsciiSpan] raise @model.FirmwareError {
  if min_length < 1 ||
    min_length > 1024 * 1024 ||
    max_strings < 0 ||
    max_strings > 1000000 ||
    max_retained_bytes < 0 ||
    max_retained_bytes > 64 * 1024 * 1024 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "ASCII search limits are outside supported bounds",
      ),
    )
  }
  let result = []
  let mut retained = 0
  for segment in image.memory.segments() {
    let mut start = 0
    while start < segment.data.length() {
      while start < segment.data.length() &&
            !printable_ascii(segment.data[start]) {
        start += 1
      }
      let mut end = start
      while end < segment.data.length() && printable_ascii(segment.data[end]) {
        end += 1
      }
      if end - start >= min_length {
        if result.length() >= max_strings ||
          end - start > max_retained_bytes - retained {
          raise @model.FirmwareError(
            @model.diagnostic(
              ResourceLimit,
              "ASCII search result limit exceeded",
            ),
          )
        }
        result.push({
          address: segment.start + start.to_int64(),
          bytes: segment.data[start:end].to_owned(),
        })
        retained += end - start
      }
      start = if end == start { start + 1 } else { end }
    }
  }
  result
}
