///|
fn invalid_profile(message : String) -> UpdateError {
  UpdateError("InvalidProfile", message, None)
}

///|
fn overlaps(a : UInt64, b : UInt64, window : Window) -> Bool {
  a < window.end_exclusive && window.start < b
}

///|
fn inside(address : UInt64, windows : Array[Window]) -> Bool {
  covers(address, address + 1UL, windows)
}

///|
/// Normalize policy unions once; per-byte membership then costs O(log n).
fn normalize_windows(windows : Array[Window]) -> Array[Window] {
  let ordered = windows.copy()
  ordered.sort_by((a, b) => a.start.compare(b.start))
  let result : Array[Window] = []
  for window in ordered {
    let last = result.length() - 1
    if last >= 0 && window.start <= result[last].end_exclusive {
      if window.end_exclusive > result[last].end_exclusive {
        result[last] = { ..result[last], end_exclusive: window.end_exclusive, }
      }
    } else {
      result.push(window)
    }
  }
  result
}

///|
fn covers(start : UInt64, end : UInt64, windows : Array[Window]) -> Bool {
  let mut low = 0
  let mut high = windows.length()
  while low < high {
    let mid = low + (high - low) / 2
    if windows[mid].start <= start {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low > 0 && windows[low - 1].end_exclusive >= end
}

///|
/// Validate before allocating sector buffers; hard limits cannot be relaxed by
/// untrusted profile fields. Geometry is sorted on a copy by the planner.
pub fn validate_profile(profile : TargetProfile) -> Unit raise UpdateError {
  if profile.name.is_empty() || profile.name.length() > 128 {
    raise invalid_profile("target name must contain 1..128 characters")
  }
  let unit = profile.program_unit
  if unit < 1 || unit > 256 || (unit & (unit - 1)) != 0 {
    raise invalid_profile("program_unit must be a power of two in 1..256")
  }
  if profile.sectors.is_empty() || profile.sectors.length() > 4096 {
    raise invalid_profile("expected 1..4096 erase sectors")
  }
  if profile.max_plan_bytes < 1 || profile.max_plan_bytes > 16777216 {
    raise invalid_profile("max_plan_bytes must be in 1..16777216")
  }
  if profile.writable.is_empty() ||
    profile.writable.length() > 4096 ||
    profile.protected_ranges.length() > 4096 {
    raise invalid_profile(
      "writable/protected policy has invalid interval count",
    )
  }
  for window in profile.writable + profile.protected_ranges {
    if window.name.is_empty() ||
      window.start >= window.end_exclusive ||
      window.end_exclusive > 0x100000000UL {
      raise invalid_profile(
        "policy windows need a name and 0 <= start < end <= 2^32",
      )
    }
  }
  let sectors = profile.sectors.copy()
  sectors.sort_by((a, b) => a.start.compare(b.start))
  let names : Map[String, Bool] = Map([])
  let mut end = 0UL
  for sector in sectors {
    if sector.name.is_empty() || names.contains(sector.name) {
      raise invalid_profile("sector names must be nonempty and unique")
    }
    names[sector.name] = true
    if sector.size < unit || sector.size > 1048576 || sector.size % unit != 0 {
      raise invalid_profile(
        "sector size must be a program-unit multiple <= 1 MiB",
      )
    }
    if sector.start >= 0x100000000UL ||
      sector.start % unit.to_uint64() != 0UL ||
      sector.start + sector.size.to_uint64() > 0x100000000UL ||
      sector.start < end {
      raise invalid_profile(
        "sector geometry overlaps, overflows or is misaligned",
      )
    }
    end = sector.start + sector.size.to_uint64()
  }
}

///|
fn object_fields(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise UpdateError {
  guard value is Object(fields) else {
    raise invalid_profile("expected JSON object")
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise invalid_profile("unknown profile field: " + key)
    }
  }
  fields
}

///|
fn field(fields : Map[String, Json], key : String) -> Json raise UpdateError {
  match fields.get(key) {
    Some(value) => value
    None => raise invalid_profile("missing profile field: " + key)
  }
}

///|
fn text_value(value : Json) -> String raise UpdateError {
  guard value is String(text) else {
    raise invalid_profile("expected JSON string")
  }
  text
}

///|
fn integer_value(value : Json) -> Int raise UpdateError {
  guard value is Number(number, ..) else {
    raise invalid_profile("expected JSON integer")
  }
  if number < 1.0 ||
    number > 16777216.0 ||
    number != number.to_int().to_double() {
    raise invalid_profile("expected positive integer <= 16777216")
  }
  number.to_int()
}

///|
fn address_value(value : Json) -> UInt64 raise UpdateError {
  let text = text_value(value)
  @codec.parse_number(text, max_value=4294967296L).reinterpret_as_uint64() catch {
    _ =>
      raise invalid_profile(
        "address must be an unsigned decimal or 0x string <= 2^32",
      )
  }
}

///|
fn array_value(value : Json) -> Array[Json] raise UpdateError {
  guard value is Array(items) else {
    raise invalid_profile("expected JSON array")
  }
  if items.length() > 4096 {
    raise invalid_profile("too many profile entries")
  }
  items
}

///|
fn read_windows(value : Json) -> Array[Window] raise UpdateError {
  array_value(value).map(item => {
    let fields = object_fields(item, ["name", "start", "end_exclusive"])
    {
      name: text_value(field(fields, "name")),
      start: address_value(field(fields, "start")),
      end_exclusive: address_value(field(fields, "end_exclusive")),
    }
  })
}

///|
/// Explicit versioned target contract. Unknown keys are rejected to catch
/// misspelled safety settings instead of silently ignoring them.
pub fn parse_target_profile(text : String) -> TargetProfile raise UpdateError {
  if text.length() > 1048576 {
    raise invalid_profile("profile exceeds 1 MiB")
  }
  let json = @json.parse(text[:]) catch {
    _ => raise invalid_profile("invalid JSON target profile")
  }
  let fields = object_fields(json, [
    "schema", "name", "program_unit", "sectors", "writable", "protected", "max_plan_bytes",
  ])
  if text_value(field(fields, "schema")) != "moonfirmware.target.v1" {
    raise invalid_profile("unsupported target schema")
  }
  let sectors = array_value(field(fields, "sectors")).map(item => {
    let item_fields = object_fields(item, ["name", "start", "size"])
    Sector::{
      name: text_value(field(item_fields, "name")),
      start: address_value(field(item_fields, "start")),
      size: integer_value(field(item_fields, "size")),
    }
  })
  let profile = TargetProfile::{
    name: text_value(field(fields, "name")),
    program_unit: integer_value(field(fields, "program_unit")),
    sectors,
    writable: read_windows(field(fields, "writable")),
    protected_ranges: read_windows(field(fields, "protected")),
    max_plan_bytes: integer_value(field(fields, "max_plan_bytes")),
  }
  validate_profile(profile)
  profile
}
