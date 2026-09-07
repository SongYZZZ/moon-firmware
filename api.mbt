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
