///|
/// Address-level comparison, retaining compact ranges rather than expanded gaps.
pub(all) struct FirmwareDiff {
  only_left : Array[@model.AddressRange]
  only_right : Array[@model.AddressRange]
  changed : Array[@model.AddressRange]
  identical_bytes : Int64
  changed_bytes : Int64
  removed_bytes : Int64
  added_bytes : Int64
  entry_changed : Bool
} derive(Eq, Debug)

///|
/// True when occupied bytes and exact execution entry state are equal.
pub fn FirmwareDiff::is_equal(self : FirmwareDiff) -> Bool {
  self.changed_bytes == 0L &&
  self.removed_bytes == 0L &&
  self.added_bytes == 0L &&
  !self.entry_changed
}

///|
fn append_range(
  ranges : Array[@model.AddressRange],
  start : Int64,
  end : Int64,
) -> Unit raise @model.FirmwareError {
  if start >= end {
    return
  }
  let n = ranges.length()
  if n > 0 && ranges[n - 1].end == start {
    ranges[n - 1] = @model.AddressRange::new(ranges[n - 1].start, end)
  } else {
    ranges.push(@model.AddressRange::new(start, end))
  }
}

///|
/// Sweep occupied interval boundaries. Runtime depends on actual payload and
/// segment count, never on the numeric distance between sparse addresses.
pub fn diff_images(
  left : @model.FirmwareImage,
  right : @model.FirmwareImage,
) -> FirmwareDiff raise @model.FirmwareError {
  let a = left.memory.segments()
  let b = right.memory.segments()
  let only_left = []
  let only_right = []
  let changed = []
  let mut identical_bytes = 0L
  let mut changed_bytes = 0L
  let mut removed_bytes = 0L
  let mut added_bytes = 0L
  let mut i = 0
  let mut j = 0
  let mut position = 0L
  while i < a.length() || j < b.length() {
    while i < a.length() && a[i].range().end <= position {
      i += 1
    }
    while j < b.length() && b[j].range().end <= position {
      j += 1
    }
    let left_start = if i < a.length() { a[i].start } else { 0x100000000L }
    let right_start = if j < b.length() { b[j].start } else { 0x100000000L }
    if left_start > position && right_start > position {
      position = left_start.min(right_start)
    }
    if position == 0x100000000L {
      break
    }
    let has_left = i < a.length() && a[i].range().contains(position)
    let has_right = j < b.length() && b[j].range().contains(position)
    let left_end = if has_left { a[i].range().end } else { left_start }
    let right_end = if has_right { b[j].range().end } else { right_start }
    let end = left_end.min(right_end)
    if has_left && has_right {
      let mut run_start : Int64? = None
      let mut pos = position
      while pos < end {
        let before = a[i].data[(pos - a[i].start).to_int()]
        let after = b[j].data[(pos - b[j].start).to_int()]
        if before != after {
          changed_bytes += 1L
          if run_start == None {
            run_start = Some(pos)
          }
        } else {
          identical_bytes += 1L
          if run_start is Some(start) {
            append_range(changed, start, pos)
            run_start = None
          }
        }
        pos += 1L
      }
      if run_start is Some(start) {
        append_range(changed, start, end)
      }
    } else if has_left {
      append_range(only_left, position, end)
      removed_bytes += end - position
    } else if has_right {
      append_range(only_right, position, end)
      added_bytes += end - position
    }
    position = end
  }
  {
    only_left,
    only_right,
    changed,
    identical_bytes,
    changed_bytes,
    removed_bytes,
    added_bytes,
    entry_changed: left.entry != right.entry,
  }
}
