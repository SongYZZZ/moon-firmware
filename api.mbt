///|
/// Shared sparse image types. Detailed protocol record APIs live in /ihex and /srec.
pub using @model {
  type AddressRange,
  type MemoryMap,
  type MemorySegment,
  type FirmwareImage,
  type EntryPoint,
  type Metadata,
  type Diagnostic,
  type FirmwareError,
  type ErrorCode,
  type Format,
  type ParseMode,
  type ParseOptions,
  type OverlapPolicy,
  type ChecksumStatus,
}

///|
/// Format detection, loading, conversion and address-based image operations.
pub using @firmware {
  type ConvertOptions,
  type ConversionResult,
  type EntryPolicy,
  type FirmwareDiff,
  type ImageStatistics,
  detect_format,
  load_firmware,
  convert,
  merge_images,
  extract_range,
  diff_images,
  inspect_image,
  relocate,
  remove_range,
  fill_range,
}

///|
/// Parse Intel HEX while exposing a format-specific name at the module root.
pub fn parse_intel_hex(
  text : String,
  options? : ParseOptions = ParseOptions::default(),
) -> FirmwareImage raise FirmwareError {
  @ihex.parse_document(text, options~)
}

///|
/// Serialize an image as deterministic Intel HEX text.
pub fn write_intel_hex(
  image : FirmwareImage,
  options? : @ihex.WriterOptions = @ihex.WriterOptions::default(),
) -> String raise FirmwareError {
  @ihex.encode(image, options~)
}

///|
/// Parse a Motorola S-Record block at the module root.
pub fn parse_srecord(
  text : String,
  options? : ParseOptions = ParseOptions::default(),
) -> FirmwareImage raise FirmwareError {
  @srec.parse_document(text, options~)
}

///|
/// Serialize an image as deterministic Motorola S-Record text.
pub fn write_srecord(
  image : FirmwareImage,
  options? : @srec.WriterOptions = @srec.WriterOptions::default(),
) -> String raise FirmwareError {
  @srec.encode(image, options~)
}

///|
/// Optional target-layout and bounded flash-page planning APIs.
pub using @validation {
  type MemoryRegion,
  type CheckLevel,
  type LayoutRule,
  type LayoutIssue,
  type LayoutOptions,
  type LayoutReport,
  type FlashOptions,
  type FlashPage,
  type FlashPlan,
  validate_layout,
  plan_flash_pages,
}

///|
/// Address-aware checksums, searches, integer access and Cortex-M inspection.
pub using @analysis {
  type ImageChecksumAlgorithm,
  type ImageChecksum,
  type MaskedPattern,
  type AsciiSpan,
  type ByteOrder,
  type CortexMVectorTable,
  checksum_image,
  find_pattern,
  find_ascii_strings,
  read_uint,
  encode_uint,
  write_uint,
  find_uint,
  inspect_cortex_m_vectors,
}
