///|
/// Validate occupied address ranges, budgets, alignment and execution entry
/// against a board layout. Work is proportional to payload/segment snapshots
/// and region boundaries, never the numeric distance between sparse segments.
/// Diagnostic order is budgets, occupied regions in address order, then entry.
pub fn validate_layout(
  image : @model.FirmwareImage,
  options : LayoutOptions,
) -> LayoutReport raise @model.FirmwareError {
  let regions = checked_regions(options)
  let issues : Array[LayoutIssue] = []
  let bounds = image.memory.bounds()
  let span = match bounds {
    Some(range) => range.length()
    None => 0L
  }
  let payload = image.memory.payload_size()
  if payload > options.max_payload_bytes {
    issues.push({
      rule: PayloadBudget,
      level: Error,
      range: bounds,
      region: None,
      message: "payload \{payload} exceeds budget \{options.max_payload_bytes} bytes",
    })
  }
  if span > options.max_span_bytes {
    issues.push({
      rule: SpanBudget,
      level: Error,
      range: bounds,
      region: None,
      message: "address span \{span} exceeds budget \{options.max_span_bytes} bytes",
    })
  }
  let mut first_region = 0
  for segment in image.memory.segments() {
    let range = segment.range()
    if range.start % options.segment_start_alignment.to_int64() != 0L {
      issues.push({
        rule: SegmentStartAlignment,
        level: Error,
        range: Some(range),
        region: None,
        message: "segment start must align to \{options.segment_start_alignment} bytes",
      })
    }
    if range.length() % options.segment_length_alignment.to_int64() != 0L {
      issues.push({
        rule: SegmentLengthAlignment,
        level: Error,
        range: Some(range),
        region: None,
        message: "segment length must align to \{options.segment_length_alignment} bytes",
      })
    }
    // Sorted disjoint regions permit a monotonic cursor even for huge gaps.
    while first_region < regions.length() &&
          regions[first_region].range.end <= range.start {
      first_region += 1
    }
    let mut cursor = range.start
    let mut index = first_region
    while index < regions.length() && regions[index].range.start < range.end {
      let allowed = regions[index].range
      if cursor < allowed.start {
        outside_issue(
          issues,
          @model.AddressRange::new(cursor, allowed.start.min(range.end)),
        )
      }
      cursor = cursor.max(allowed.end.min(range.end))
      index += 1
    }
    if cursor < range.end {
      outside_issue(issues, @model.AddressRange::new(cursor, range.end))
    }
  }
  let checked_entry = validate_entry(image, regions, options, issues)
  {
    issues,
    payload_bytes: payload,
    address_span: span,
    segment_count: image.memory.segment_count(),
    checked_entry,
  }
}

///|
fn outside_issue(
  issues : Array[LayoutIssue],
  range : @model.AddressRange,
) -> Unit {
  issues.push({
    rule: OutsideAllowedRegions,
    level: Error,
    range: Some(range),
    region: None,
    message: "occupied bytes lie outside all allowed target regions",
  })
}

///|
fn validate_entry(
  image : @model.FirmwareImage,
  regions : Array[MemoryRegion],
  options : LayoutOptions,
  issues : Array[LayoutIssue],
) -> Int64? raise @model.FirmwareError {
  let entry = match image.entry {
    None => {
      if options.entry_required != Disabled {
        issues.push({
          rule: MissingEntry,
          level: options.entry_required,
          range: None,
          region: None,
          message: "firmware has no execution entry point",
        })
      }
      return None
    }
    Some(value) => value.address()
  }
  let address = if options.clear_entry_thumb_bit {
    entry - entry % 2L
  } else {
    entry
  }
  let range = @model.AddressRange::new(address, address + 1L)
  if address % options.entry_alignment.to_int64() != 0L {
    issues.push({
      rule: EntryAlignment,
      level: Error,
      range: Some(range),
      region: None,
      message: "entry address must align to \{options.entry_alignment} bytes",
    })
  }
  if options.entry_mapped != Disabled && !image.memory.contains(address) {
    issues.push({
      rule: EntryNotMapped,
      level: options.entry_mapped,
      range: Some(range),
      region: None,
      message: "entry address has no occupied firmware byte",
    })
  }
  if options.entry_executable != Disabled {
    let mut enclosing : MemoryRegion? = None
    for region in regions {
      if region.range.contains(address) {
        enclosing = Some(region)
        break
      }
    }
    match enclosing {
      Some(region) =>
        if !region.executable {
          issues.push({
            rule: EntryNotExecutable,
            level: options.entry_executable,
            range: Some(range),
            region: Some(region.name),
            message: "entry address belongs to a non-executable target region",
          })
        }
      None =>
        issues.push({
          rule: EntryNotExecutable,
          level: options.entry_executable,
          range: Some(range),
          region: None,
          message: "entry address lies outside all executable target regions",
        })
    }
  }
  Some(address)
}
