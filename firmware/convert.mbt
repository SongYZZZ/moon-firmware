///|
/// Content detection is conservative. Printable text with no record signature
/// remains Unknown; a binary hint is needed for ambiguous printable raw bytes.
pub fn detect_format(bytes : Bytes) -> @model.Format {
  if bytes.is_empty() {
    return Unknown
  }
  let mut start = 0
  if bytes.length() >= 3 &&
    bytes[0] == b'\xEF' &&
    bytes[1] == b'\xBB' &&
    bytes[2] == b'\xBF' {
    start = 3
  }
  let limit = bytes.length().min(65536)
  let mut line_start = true
  for i in start..<limit {
    let b = bytes[i].to_int()
    if line_start {
      if b == 32 || b == 9 || b == 13 || b == 10 {
        continue
      }
      if b == 58 {
        return IntelHex
      }
      if b == 83 &&
        i + 1 < bytes.length() &&
        bytes[i + 1].to_int() >= 48 &&
        bytes[i + 1].to_int() <= 57 {
        return SRecord
      }
      if b == 35 || b == 59 {
        line_start = false
        continue
      }
      break
    } else if b == 10 {
      line_start = true
    }
  }
  for i in 0..<limit {
    let n = bytes[i].to_int()
    if (n < 32 && n != 9 && n != 10 && n != 13) || n == 127 || n >= 128 {
      return RawBinary
    }
  }
  Unknown
}

///|
/// Extension hints are subordinate to content, and never suppress text errors.
pub fn format_from_path(path : String) -> @model.Format {
  let name = path.to_lower()
  if name.has_suffix(".hex") ||
    name.has_suffix(".ihx") ||
    name.has_suffix(".ihex") {
    IntelHex
  } else if name.has_suffix(".srec") ||
    name.has_suffix(".s19") ||
    name.has_suffix(".s28") ||
    name.has_suffix(".s37") ||
    name.has_suffix(".srecord") ||
    name.has_suffix(".mot") {
    SRecord
  } else if name.has_suffix(".bin") {
    RawBinary
  } else {
    Unknown
  }
}

///|
/// Byte-to-text boundary rejects non-ASCII, except a leading UTF-8 BOM which the
/// permissive line policy handles explicitly. Invalid UTF-8 is never replaced.
pub fn decode_text(
  bytes : Bytes,
  format : @model.Format,
  max_length? : Int = 256 * 1024 * 1024,
) -> String raise @model.FirmwareError {
  if max_length < 0 || bytes.length() > max_length {
    raise @model.FirmwareError(
      @model.diagnostic(ResourceLimit, "input text exceeds configured limit"),
    )
  }
  let out = StringBuilder(size_hint=bytes.length())
  let mut pos = 0
  let mut line = 1
  let mut column = 1
  if bytes.length() >= 3 &&
    bytes[0] == b'\xEF' &&
    bytes[1] == b'\xBB' &&
    bytes[2] == b'\xBF' {
    out.write_char('\uFEFF')
    pos = 3
    column = 2
  }
  while pos < bytes.length() {
    let n = bytes[pos].to_int()
    if n >= 128 || n == 0 {
      let loc : @codec.Location = {
        format,
        line,
        column_offset: 0,
        record_type: None,
      }
      raise loc.error(
        InvalidDigit,
        column,
        "firmware text must contain ASCII bytes",
      )
    }
    // n has been bounded to ASCII above, so conversion cannot fail.
    out.write_char(n.to_char().unwrap())
    if n == 10 {
      line += 1
      column = 1
    } else {
      column += 1
    }
    pos += 1
  }
  out.to_string()
}

///|
/// Load bytes with optional format hint and explicit raw binary placement.
/// Record signatures take precedence over hints, including a misleading .bin.
pub fn load_firmware(
  bytes : Bytes,
  hint? : @model.Format = Unknown,
  base_address? : Int64,
  options? : @model.ParseOptions = @model.ParseOptions::default(),
) -> @model.FirmwareImage raise @model.FirmwareError {
  options.validate()
  let detected = detect_format(bytes)
  let format = match detected {
    IntelHex | SRecord => detected
    _ => if hint != Unknown { hint } else { detected }
  }
  if format != RawBinary && base_address != None {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "base address applies only to raw binary input",
      ),
    )
  }
  match format {
    IntelHex =>
      @ihex.parse_document(
        decode_text(bytes, format, max_length=options.max_text_length),
        options~,
      )
    SRecord =>
      @srec.parse_document(
        decode_text(bytes, format, max_length=options.max_text_length),
        options~,
      )
    RawBinary => {
      let base = match base_address {
        Some(address) => address
        None =>
          raise @model.FirmwareError(
            @model.diagnostic(
              InvalidOption,
              "raw binary input requires base address",
            ),
          )
      }
      if bytes.length() > options.max_payload {
        raise @model.FirmwareError(
          @model.diagnostic(ResourceLimit, "raw input exceeds payload limit"),
        )
      }
      @model.FirmwareImage::from_binary(bytes, base)
    }
    Unknown =>
      raise @model.FirmwareError(
        @model.diagnostic(
          UnknownFormat,
          "unrecognized input; specify a format hint",
        ),
      )
  }
}

///|
/// Unified output configuration, keeping the protocol-specific controls typed.
pub(all) struct ConvertOptions {
  format : @model.Format
  binary_range : @model.AddressRange?
  fill : Byte?
  max_binary_size : Int
  intel_hex : @ihex.WriterOptions
  srecord : @srec.WriterOptions
}

///|
/// Defaults keep sparse BIN expansion below 16 MiB and require explicit fill.
pub fn ConvertOptions::new(format : @model.Format) -> ConvertOptions {
  {
    format,
    binary_range: None,
    fill: None,
    max_binary_size: 16 * 1024 * 1024,
    intel_hex: @ihex.WriterOptions::default(),
    srecord: @srec.WriterOptions::default(),
  }
}

///|
/// Encoded bytes and explicit information about metadata that the output loses.
pub(all) struct ConversionResult {
  bytes : Bytes
  warnings : Array[@model.Diagnostic]
  binary_base : Int64?
}

///|
/// Convert an in-memory image, reporting unavoidable format metadata changes.
pub fn convert(
  image : @model.FirmwareImage,
  options : ConvertOptions,
) -> ConversionResult raise @model.FirmwareError {
  let warnings = image.warnings.copy()
  let mut binary_base = None
  let bytes = match options.format {
    IntelHex => {
      if image.metadata.header != None {
        warnings.push(
          @model.diagnostic(
            InvalidRecord,
            "Intel HEX cannot preserve S0 header bytes",
          ),
        )
      }
      @utf8.encode(@ihex.encode(image, options=options.intel_hex))
    }
    SRecord => {
      if image.entry == None {
        warnings.push(
          @model.diagnostic(
            InvalidRecord,
            "SREC termination uses entry address zero when source has no entry",
          ),
        )
      }
      if image.entry is Some(Segment(_, _)) &&
        options.srecord.flatten_segment_entry {
        warnings.push(
          @model.diagnostic(
            InvalidRecord,
            "SREC flattened CS:IP into an absolute entry address",
          ),
        )
      }
      @utf8.encode(@srec.encode(image, options=options.srecord))
    }
    RawBinary => {
      let range = match options.binary_range {
        Some(value) => value
        None =>
          match image.memory.bounds() {
            Some(value) => value
            None => @model.AddressRange::new(0L, 0L)
          }
      }
      binary_base = Some(range.start)
      if image.entry != None || image.metadata.header != None {
        warnings.push(
          @model.diagnostic(
            InvalidRecord,
            "raw binary discards execution entry and header metadata",
          ),
        )
      }
      if options.binary_range != None &&
        image.memory.slice(range).payload_size() != image.memory.payload_size() {
        warnings.push(
          @model.diagnostic(
            InvalidRange,
            "binary window excludes source payload outside the selected range",
          ),
        )
      }
      image.memory.to_binary(
        range,
        fill?=options.fill,
        max_size=options.max_binary_size,
      )
    }
    Unknown =>
      raise @model.FirmwareError(
        @model.diagnostic(UnknownFormat, "output format must be explicit"),
      )
  }
  { bytes, warnings, binary_base, }
}
