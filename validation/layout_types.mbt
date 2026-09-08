///|
/// Named target region. Disjoint regions describe the allowed payload union;
/// executable marks regions in which an execution entry is permitted.
pub(all) struct MemoryRegion {
  name : String
  range : @model.AddressRange
  executable : Bool
} derive(Eq, Debug)

///|
/// Whether entry checks are disabled, advisory, or required for acceptance.
pub(all) enum CheckLevel {
  Disabled
  Warning
  Error
} derive(Eq, Debug)

///|
/// Stable categories for machine-readable target-layout results.
pub(all) enum LayoutRule {
  OutsideAllowedRegions
  SegmentStartAlignment
  SegmentLengthAlignment
  PayloadBudget
  SpanBudget
  MissingEntry
  EntryNotMapped
  EntryNotExecutable
  EntryAlignment
} derive(Eq, Debug)

///|
/// A specific violation. Ranges are half-open, matching the memory model.
/// region is provided when an entry belongs to a non-executable named region.
pub struct LayoutIssue {
  rule : LayoutRule
  level : CheckLevel
  range : @model.AddressRange?
  region : String?
  message : String
} derive(Eq, Debug)

///|
/// Layout constraints. Empty regions allow no payload; use one full-address
/// region to permit any address. Entry normalization never changes the image.
/// Alignment values are positive powers of two, and 1 disables alignment.
pub(all) struct LayoutOptions {
  regions : Array[MemoryRegion]
  segment_start_alignment : Int
  segment_length_alignment : Int
  max_payload_bytes : Int
  max_span_bytes : Int64
  entry_required : CheckLevel
  entry_mapped : CheckLevel
  entry_executable : CheckLevel
  entry_alignment : Int
  clear_entry_thumb_bit : Bool
} derive(Eq, Debug)

///|
/// Default constraints for an explicit target region list. Payload must fit
/// those regions; entry placement problems are warnings, not parse errors.
pub fn LayoutOptions::new(regions : Array[MemoryRegion]) -> LayoutOptions {
  {
    regions: regions.copy(),
    segment_start_alignment: 1,
    segment_length_alignment: 1,
    max_payload_bytes: 64 * 1024 * 1024,
    max_span_bytes: 0x100000000L,
    entry_required: Disabled,
    entry_mapped: Warning,
    entry_executable: Warning,
    entry_alignment: 1,
    clear_entry_thumb_bit: false,
  }
}

///|
/// Complete deterministic result. Invalid configuration raises FirmwareError;
/// a valid configuration reports every layout violation without fail-fast.
pub struct LayoutReport {
  issues : Array[LayoutIssue]
  payload_bytes : Int
  address_span : Int64
  segment_count : Int
  checked_entry : Int64?
} derive(Eq, Debug)

///|
/// Warnings do not reject an image. A report can be accepted while advisory
/// entry placement checks remain visible in issues.
pub fn LayoutReport::is_valid(self : LayoutReport) -> Bool {
  !self.issues.any(issue => issue.level == Error)
}

///|
/// Produce a readable validation report without discarding typed rule data.
pub fn LayoutReport::render(self : LayoutReport) -> String {
  let out = StringBuilder()
  out.write_string(
    if self.is_valid() {
      "Layout: valid\n"
    } else {
      "Layout: invalid\n"
    },
  )
  out.write_string("Payload: \{self.payload_bytes} bytes\n")
  out.write_string("Address span: \{self.address_span} bytes\n")
  out.write_string("Segments: \{self.segment_count}\n")
  for issue in self.issues {
    out.write_string(
      if issue.level == Warning {
        "warning: "
      } else {
        "error: "
      },
    )
    out.write_string(issue.message)
    if issue.range is Some(range) {
      out.write_string(" at " + range.render())
    }
    if issue.region is Some(name) {
      out.write_string(" (region " + name + ")")
    }
    out.write_char('\n')
  }
  out.to_string()
}

///|
fn valid_alignment(value : Int) -> Bool {
  value > 0 && value <= 1024 * 1024 && (value & (value - 1)) == 0
}

///|
fn checked_regions(
  options : LayoutOptions,
) -> Array[MemoryRegion] raise @model.FirmwareError {
  if !valid_alignment(options.segment_start_alignment) ||
    !valid_alignment(options.segment_length_alignment) ||
    !valid_alignment(options.entry_alignment) {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "layout alignments must be powers of two between 1 and 1048576",
      ),
    )
  }
  if options.max_payload_bytes < 0 ||
    options.max_payload_bytes > 64 * 1024 * 1024 ||
    options.max_span_bytes < 0L ||
    options.max_span_bytes > 0x100000000L {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "layout budgets exceed supported payload or address bounds",
      ),
    )
  }
  if options.regions.length() > 1024 {
    raise @model.FirmwareError(
      @model.diagnostic(
        ResourceLimit,
        "target layout permits at most 1024 named regions",
      ),
    )
  }
  let regions = options.regions.copy()
  regions.sort_by_key(region => region.range.start)
  let names : Array[String] = []
  for i in 0..<regions.length() {
    let region = regions[i]
    if region.name.is_empty() ||
      region.name.length() > 128 ||
      region.name.contains("\n") ||
      region.name.contains("\r") {
      raise @model.FirmwareError(
        @model.diagnostic(
          InvalidOption,
          "region names must be nonempty single-line strings of at most 128 characters",
        ),
      )
    }
    if names.contains(region.name) {
      raise @model.FirmwareError(
        @model.diagnostic(
          InvalidOption,
          "duplicate target region name: " + region.name,
        ),
      )
    }
    names.push(region.name)
    if region.range.is_empty() {
      raise @model.FirmwareError(
        @model.diagnostic(
          InvalidOption,
          "target region cannot be empty: " + region.name,
          address=region.range.start,
        ),
      )
    }
    if i > 0 && regions[i - 1].range.end > region.range.start {
      raise @model.FirmwareError(
        @model.diagnostic(
          InvalidOption,
          "target regions overlap: " +
          regions[i - 1].name +
          " and " +
          region.name,
          address=region.range.start,
          end_address=regions[i - 1].range.end.min(region.range.end) - 1L,
        ),
      )
    }
  }
  regions
}
