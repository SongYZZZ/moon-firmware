///|
/// Stable reasons why a Cortex-M release image is rejected by its target gate.
pub(all) enum ReleaseRule {
  VectorTableMissing
  StackPointerOutsideRam
  StackPointerMisaligned
  ResetThumbBitMissing
  ResetHandlerOutsideFlash
  ResetHandlerUnmapped
} derive(Eq, Debug)

///|
/// One target-specific release violation with an optional relevant address.
pub struct ReleaseIssue {
  rule : ReleaseRule
  address : Int64?
  message : String
} derive(Eq, Debug)

///|
pub fn ReleaseIssue::category(self : ReleaseIssue) -> ReleaseRule {
  self.rule
}

///|
pub fn ReleaseIssue::at_address(self : ReleaseIssue) -> Int64? {
  self.address
}

///|
pub fn ReleaseIssue::description(self : ReleaseIssue) -> String {
  self.message
}

///|
/// Explicit Cortex-M target contract. RAM ranges accept a stack pointer at
/// their exclusive end because startup stacks commonly begin at the top of RAM.
/// Flash boundaries must be aligned to page_size so a whole-page plan cannot
/// silently touch bytes outside the declared programming region.
pub(all) struct CortexMReleaseOptions {
  flash : @model.AddressRange
  ram : Array[@model.AddressRange]
  vector_address : Int64
  page_size : Int
  erase_value : Byte
  stack_alignment : Int
  max_pages : Int
  max_output_bytes : Int
} derive(Eq, Debug)

///|
/// Construct a conservative release contract for one Flash and one RAM range.
pub fn CortexMReleaseOptions::new(
  flash : @model.AddressRange,
  ram : @model.AddressRange,
  vector_address? : Int64 = flash.start,
  page_size? : Int = 1024,
  erase_value? : Byte = 0xFF,
) -> CortexMReleaseOptions {
  {
    flash,
    ram: [ram],
    vector_address,
    page_size,
    erase_value,
    stack_alignment: 8,
    max_pages: 65536,
    max_output_bytes: 16 * 1024 * 1024,
  }
}

///|
/// Complete release-gate evidence. Layout and page plans remain available to
/// callers; target-specific vector findings are accumulated instead of failing
/// at the first bad field.
pub struct CortexMReleaseReport {
  options : CortexMReleaseOptions
  layout : LayoutReport
  vectors : @analysis.CortexMVectorTable?
  plan : FlashPlan?
  issues : Array[ReleaseIssue]
} derive(Eq, Debug)

///|
/// A release passes only when address layout and Cortex-M vector checks pass
/// and a bounded whole-page programming plan can be produced.
pub fn CortexMReleaseReport::is_valid(self : CortexMReleaseReport) -> Bool {
  self.layout.is_valid() && self.issues.is_empty() && self.plan is Some(_)
}

///|
/// Target-specific findings in deterministic validation order.
pub fn CortexMReleaseReport::release_issues(
  self : CortexMReleaseReport,
) -> Array[ReleaseIssue] {
  self.issues.copy()
}

///|
/// Generic payload and optional metadata-entry layout evidence.
pub fn CortexMReleaseReport::layout_report(
  self : CortexMReleaseReport,
) -> LayoutReport {
  self.layout
}

///|
/// Validated flash-page plan, absent when layout or vector checks reject.
pub fn CortexMReleaseReport::flash_plan(
  self : CortexMReleaseReport,
) -> FlashPlan? {
  self.plan
}

///|
/// Decoded vector information, absent when the first eight bytes are missing.
pub fn CortexMReleaseReport::vector_table(
  self : CortexMReleaseReport,
) -> @analysis.CortexMVectorTable? {
  self.vectors
}

///|
fn release_option_error(message : String) -> @model.FirmwareError {
  @model.FirmwareError(@model.diagnostic(InvalidOption, message))
}

///|
fn checked_release_options(
  options : CortexMReleaseOptions,
) -> Unit raise @model.FirmwareError {
  if options.flash.is_empty() || options.ram.is_empty() {
    raise release_option_error(
      "release target requires non-empty Flash and RAM ranges",
    )
  }
  if options.ram.length() > 32 {
    raise release_option_error("release target permits at most 32 RAM ranges")
  }
  if !valid_alignment(options.page_size) ||
    options.flash.start % options.page_size.to_int64() != 0L ||
    options.flash.end % options.page_size.to_int64() != 0L {
    raise release_option_error(
      "Flash boundaries must align to a power-of-two page size",
    )
  }
  if options.vector_address < options.flash.start ||
    options.vector_address + 8L > options.flash.end {
    raise release_option_error("vector table must fit inside the Flash range")
  }
  if options.stack_alignment < 1 ||
    options.stack_alignment > 1024 ||
    (options.stack_alignment & (options.stack_alignment - 1)) != 0 {
    raise release_option_error(
      "stack alignment must be a power of two up to 1024",
    )
  }
  if options.max_pages < 0 ||
    options.max_pages > 65536 ||
    options.max_output_bytes < 0 ||
    options.max_output_bytes > 64 * 1024 * 1024 {
    raise release_option_error("release plan limits exceed supported bounds")
  }
}

///|
fn vector_bytes_present(image : @model.FirmwareImage, address : Int64) -> Bool {
  for offset in 0..<8 {
    if !image.memory.contains(address + offset.to_int64()) {
      return false
    }
  }
  true
}

///|
fn stack_in_ram(stack : Int64, ranges : Array[@model.AddressRange]) -> Bool {
  ranges.any(range => stack >= range.start && stack <= range.end)
}

///|
/// Validate a firmware image as a Cortex-M release artifact and build the exact
/// set of touched whole Flash pages. This function performs no device I/O.
pub fn validate_cortex_m_release(
  image : @model.FirmwareImage,
  options : CortexMReleaseOptions,
) -> CortexMReleaseReport raise @model.FirmwareError {
  checked_release_options(options)
  let layout = validate_layout(image, {
    ..LayoutOptions::new([
      { name: "flash", range: options.flash, executable: true, },
    ]),
    entry_mapped: Error,
    entry_executable: Error,
    entry_alignment: 2,
    clear_entry_thumb_bit: true,
  })
  let issues : Array[ReleaseIssue] = []
  let mut vectors : @analysis.CortexMVectorTable? = None
  if !vector_bytes_present(image, options.vector_address) {
    issues.push({
      rule: VectorTableMissing,
      address: Some(options.vector_address),
      message: "the first eight vector-table bytes are not fully mapped",
    })
  } else {
    let decoded = @analysis.inspect_cortex_m_vectors(
      image,
      options.vector_address,
      stack_alignment=options.stack_alignment,
    )
    vectors = Some(decoded)
    let stack = decoded.stack_pointer()
    if !stack_in_ram(stack, options.ram) {
      issues.push({
        rule: StackPointerOutsideRam,
        address: Some(stack),
        message: "initial stack pointer is outside declared RAM",
      })
    }
    if !decoded.is_stack_aligned() {
      issues.push({
        rule: StackPointerMisaligned,
        address: Some(stack),
        message: "initial stack pointer does not meet target alignment",
      })
    }
    let reset = decoded.reset_handler()
    if !decoded.has_thumb_bit() {
      issues.push({
        rule: ResetThumbBitMissing,
        address: Some(decoded.raw_reset_vector()),
        message: "Cortex-M reset vector does not set the Thumb-state bit",
      })
    }
    if !options.flash.contains(reset) {
      issues.push({
        rule: ResetHandlerOutsideFlash,
        address: Some(reset),
        message: "reset handler is outside declared Flash",
      })
    }
    if !decoded.is_reset_mapped() {
      issues.push({
        rule: ResetHandlerUnmapped,
        address: Some(reset),
        message: "reset handler address is absent from the firmware image",
      })
    }
  }
  let plan = if layout.is_valid() && issues.is_empty() {
    Some(
      plan_flash_pages(image, {
        ..FlashOptions::new(options.page_size, options.erase_value),
        max_pages: options.max_pages,
        max_output_bytes: options.max_output_bytes,
        allowed_range: Some(options.flash),
      }),
    )
  } else {
    None
  }
  { options, layout, vectors, plan, issues, }
}

///|
/// Render release evidence without embedding firmware payload bytes.
pub fn CortexMReleaseReport::render(self : CortexMReleaseReport) -> String {
  let out = StringBuilder()
  out.write_string(
    if self.is_valid() {
      "Release gate: passed\n"
    } else {
      "Release gate: failed\n"
    },
  )
  out.write_string("Flash: " + self.options.flash.render() + "\n")
  out.write_string(
    "Vector table: " + @model.hex_address(self.options.vector_address) + "\n",
  )
  match self.vectors {
    Some(table) => {
      out.write_string(
        "Initial stack pointer: " +
        @model.hex_address(table.stack_pointer()) +
        "\n",
      )
      out.write_string(
        "Reset handler: " + @model.hex_address(table.reset_handler()) + "\n",
      )
    }
    None => ()
  }
  for issue in self.issues {
    out.write_string("error: " + issue.message)
    if issue.address is Some(address) {
      out.write_string(" at " + @model.hex_address(address))
    }
    out.write_char('\n')
  }
  if !self.layout.is_valid() {
    out.write_string(self.layout.render())
  }
  if self.plan is Some(plan) {
    out.write_string(plan.render_manifest())
  }
  out.to_string()
}
