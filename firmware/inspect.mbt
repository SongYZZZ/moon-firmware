///|
/// Facts computed from normalized memory and source metadata.
pub(all) struct ImageStatistics {
  format : @model.Format
  lowest_address : Int64?
  highest_address : Int64?
  address_span : Int64
  payload_bytes : Int
  segment_count : Int
  gap_count : Int
  gap_bytes : Int64
  largest_gap : Int64
  entry : @model.EntryPoint?
  checksum_status : @model.ChecksumStatus
  record_count : Int
  record_counts : Array[Int]
  warning_count : Int
} derive(Eq, Debug)

///|
/// Inspect without allocating dense bytes or depending on textual formatting.
pub fn inspect_image(image : @model.FirmwareImage) -> ImageStatistics {
  let gaps = image.memory.gaps()
  let mut gap_bytes = 0L
  let mut largest_gap = 0L
  for gap in gaps {
    gap_bytes += gap.length()
    largest_gap = largest_gap.max(gap.length())
  }
  let mut record_count = 0
  for count in image.metadata.record_counts {
    record_count += count
  }
  {
    format: image.metadata.source_format,
    lowest_address: image.memory.lowest_address(),
    highest_address: image.memory.highest_address(),
    address_span: match image.memory.bounds() {
      Some(range) => range.length()
      None => 0L
    },
    payload_bytes: image.memory.payload_size(),
    segment_count: image.memory.segment_count(),
    gap_count: gaps.length(),
    gap_bytes,
    largest_gap,
    entry: image.entry,
    checksum_status: image.metadata.checksum_status,
    record_count,
    record_counts: image.metadata.record_counts.copy(),
    warning_count: image.warnings.length(),
  }
}

///|
/// Execution display retains CS:IP notation when available.
pub fn format_entry(entry : @model.EntryPoint?) -> String {
  match entry {
    None => "none"
    Some(Linear(address)) => @model.hex_address(address)
    Some(Segment(cs, ip)) =>
      "CS:IP " +
      cs.to_string(radix=16).to_upper().pad_start(4, '0') +
      ":" +
      ip.to_string(radix=16).to_upper().pad_start(4, '0')
  }
}

///|
/// A transformed image has no claim that original record checksums still apply.
pub fn format_checksum(status : @model.ChecksumStatus) -> String {
  match status {
    Verified => "valid"
    NotApplicable => "not applicable"
    Derived => "derived image (no source record checksum)"
  }
}

///|
/// Stable human-readable report used by the CLI and examples.
pub fn ImageStatistics::render(self : ImageStatistics) -> String {
  let out = StringBuilder()
  out.write_string("Format: " + self.format.label() + "\n")
  out.write_string(
    "Payload: \{self.payload_bytes} bytes\nSegments: \{self.segment_count}\n",
  )
  match (self.lowest_address, self.highest_address) {
    (Some(low), Some(high)) =>
      out.write_string(
        "Address range: " +
        @model.hex_address(low) +
        " - " +
        @model.hex_address(high) +
        "\n",
      )
    _ => out.write_string("Address range: empty\n")
  }
  out.write_string(
    "Address span: \{self.address_span} bytes\nGaps: \{self.gap_count}\nGap bytes: \{self.gap_bytes}\n",
  )
  out.write_string("Entry point: " + format_entry(self.entry) + "\n")
  out.write_string("Checksum: " + format_checksum(self.checksum_status) + "\n")
  out.write_string(
    "Record count: \{self.record_count}\nWarnings: \{self.warning_count}",
  )
  out.to_string()
}

///|
/// Compact deterministic report. Ranges are inclusive in rendered output.
pub fn FirmwareDiff::render(self : FirmwareDiff) -> String {
  let out = StringBuilder()
  out.write_string(
    "Identical bytes: \{self.identical_bytes}\nChanged bytes: \{self.changed_bytes}\nAdded bytes: \{self.added_bytes}\nRemoved bytes: \{self.removed_bytes}\nEntry changed: \{self.entry_changed}\n",
  )
  for
    group in [
      ("Changed ranges", self.changed),
      ("Only left", self.only_left),
      ("Only right", self.only_right),
    ] {
    let (name, ranges) = group
    out.write_string(name + ":\n")
    if ranges.is_empty() {
      out.write_string("  none\n")
    }
    for range in ranges {
      out.write_string("  " + range.render() + "\n")
    }
  }
  out.to_string()
}
