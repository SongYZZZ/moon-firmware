///|
/// Context shared by the two record grammars. Locations use ASCII columns.
pub(all) struct Location {
  format : @model.Format
  line : Int
  column_offset : Int
  record_type : Int?
} derive(Eq, Debug)

///|
/// Construct a source-bound failure, retaining structured parser context.
pub fn Location::error(
  self : Location,
  code : @model.ErrorCode,
  column : Int,
  message : String,
) -> @model.FirmwareError {
  @model.FirmwareError({
    code,
    format: self.format,
    line: self.line,
    column: column + self.column_offset,
    record_type: self.record_type,
    address: None,
    end_address: None,
    message,
  })
}

///|
/// Decode one ASCII digit without locale or Unicode lookalike acceptance.
pub fn hex_digit(code : UInt16) -> Int? {
  let n = code.to_int()
  if n >= 48 && n <= 57 {
    Some(n - 48)
  } else if n >= 65 && n <= 70 {
    Some(n - 55)
  } else if n >= 97 && n <= 102 {
    Some(n - 87)
  } else {
    None
  }
}

///|
/// Decode an exact even number of digits, reporting the first bad column.
pub fn decode_hex(
  text : String,
  start : Int,
  location : Location,
) -> Bytes raise @model.FirmwareError {
  if start < 0 || start > text.length() || (text.length() - start) % 2 != 0 {
    raise location.error(
      InvalidLength,
      text.length(),
      "odd number of hexadecimal digits",
    )
  }
  let bytes = []
  let mut i = start
  while i < text.length() {
    let high = match hex_digit(text[i]) {
      Some(n) => n
      None =>
        raise location.error(
          InvalidDigit,
          i + 1,
          "invalid hex digit '" + text[i:i + 1].to_owned() + "'",
        )
    }
    let low = match hex_digit(text[i + 1]) {
      Some(n) => n
      None =>
        raise location.error(
          InvalidDigit,
          i + 2,
          "invalid hex digit '" + text[i + 1:i + 2].to_owned() + "'",
        )
    }
    bytes.push((high * 16 + low).to_byte())
    i += 2
  }
  Bytes::from_array(bytes)
}

///|
/// Append one encoded byte. The alphabet is shared; checksums are not.
pub fn write_hex_byte(
  out : StringBuilder,
  byte : Byte,
  uppercase : Bool,
) -> Unit {
  let alphabet = if uppercase { "0123456789ABCDEF" } else { "0123456789abcdef" }
  let n = byte.to_int()
  out.write_stringview(alphabet[n / 16:n / 16 + 1])
  out.write_stringview(alphabet[n % 16:n % 16 + 1])
}

///|
/// Encode bytes as plain hexadecimal digits for record bodies and previews.
pub fn encode_hex(bytes : Bytes, uppercase? : Bool = true) -> String {
  let out = StringBuilder(size_hint=bytes.length() * 2)
  for b in bytes {
    write_hex_byte(out, b, uppercase)
  }
  out.to_string()
}

///|
/// Decode a big-endian address of 1..4 bytes from a validated record.
pub fn read_address(
  bytes : Bytes,
  offset : Int,
  width : Int,
) -> Int64 raise @model.FirmwareError {
  if width < 1 || width > 4 || offset < 0 || offset > bytes.length() - width {
    raise @model.FirmwareError(
      @model.diagnostic(InvalidLength, "address field is truncated"),
    )
  }
  let mut value = 0L
  for i in offset..<(offset + width) {
    value = value * 256L + bytes[i].to_int().to_int64()
  }
  value
}

///|
/// Serialize only addresses representable in the requested width.
pub fn address_bytes(
  value : Int64,
  width : Int,
) -> Bytes raise @model.FirmwareError {
  if width < 1 || width > 4 || value < 0L || value >= 1L << (width * 8) {
    raise @model.FirmwareError(
      @model.diagnostic(
        AddressOverflow,
        "address does not fit record width",
        address=value,
      ),
    )
  }
  Bytes::makei(width, i => ((value >> ((width - 1 - i) * 8)) & 255L).to_byte())
}

///|
/// Parse a decimal or 0x-prefixed unsigned address without overflow.
pub fn parse_number(
  text : String,
  max_value? : Int64 = 0xFFFFFFFFL,
) -> Int64 raise @model.FirmwareError {
  let hex = text.has_prefix("0x") || text.has_prefix("0X")
  let start = if hex { 2 } else { 0 }
  let radix = if hex { 16L } else { 10L }
  if start == text.length() || max_value < 0L {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "expected unsigned decimal or 0x hexadecimal number",
      ),
    )
  }
  let mut number = 0L
  for i in start..<text.length() {
    let digit = match hex_digit(text[i]) {
      Some(n) if n.to_int64() < radix => n.to_int64()
      _ =>
        raise @model.FirmwareError(
          @model.diagnostic(InvalidOption, "invalid digit in number: " + text),
        )
    }
    if digit > max_value || number > (max_value - digit) / radix {
      raise @model.FirmwareError(
        @model.diagnostic(
          AddressOverflow,
          "number exceeds allowed range: " + text,
        ),
      )
    }
    number = number * radix + digit
  }
  number
}

///|
/// Normalized line plus its original starting column after permissive trim.
pub(all) struct SourceLine {
  text : String
  location : Location
}

///|
/// Iterate bounded lines without splitting a large document into an array.
/// Permissive mode accepts ASCII outer whitespace, blank/comment lines and BOM.
/// Every tolerance creates a warning. LF and CRLF are supported in both modes.
pub fn for_each_line(
  text : String,
  format : @model.Format,
  options : @model.ParseOptions,
  warnings : Array[@model.Diagnostic],
  visit : (SourceLine) -> Unit raise @model.FirmwareError,
) -> Unit raise @model.FirmwareError {
  options.validate()
  if text.length() > options.max_text_length {
    raise @model.FirmwareError(
      @model.diagnostic(ResourceLimit, "document exceeds text limit"),
    )
  }
  let mut line = 1
  let mut start = 0
  let mut pos = 0
  while pos <= text.length() {
    if pos == text.length() || text[pos] == 10 {
      // A final newline is a delimiter, not an extra blank record.
      if start == text.length() {
        break
      }
      let mut end = pos
      if end > start && text[end - 1] == 13 {
        end -= 1
      }
      let loc : Location = { format, line, column_offset: 0, record_type: None }
      if end - start > options.max_line_length {
        raise loc.error(
          ResourceLimit,
          1,
          "line exceeds configured length limit",
        )
      }
      let original = text[start:end].to_owned()
      let mut from = 0
      let mut until = original.length()
      if options.mode == Permissive {
        if line == 1 && until > 0 && original[0] == 0xFEFF {
          from = 1
        }
        while from < until && (original[from] == 32 || original[from] == 9) {
          from += 1
        }
        while until > from &&
              (original[until - 1] == 32 || original[until - 1] == 9) {
          until -= 1
        }
      }
      let body = original[from:until].to_owned()
      let skip = body.is_empty() || body.has_prefix(";") || body.has_prefix("#")
      if options.mode == Permissive &&
        (skip || from != 0 || until != original.length()) {
        let @model.FirmwareError(d) = loc.error(
          InvalidRecord,
          1,
          "accepted whitespace, BOM or comment in permissive mode",
        )
        warnings.push(d)
      }
      if !(options.mode == Permissive && skip) {
        visit({ text: body, location: { ..loc, column_offset: from } })
      }
      start = pos + 1
      line += 1
    } else if pos - start > options.max_line_length {
      let loc : Location = { format, line, column_offset: 0, record_type: None }
      raise loc.error(ResourceLimit, 1, "line exceeds configured length limit")
    }
    pos += 1
  }
}

///|
/// Reattach source context to an address or overlap failure from the model.
pub fn locate_error(
  error : @model.FirmwareError,
  location : Location,
) -> @model.FirmwareError {
  let @model.FirmwareError(d) = error
  @model.FirmwareError({
    ..d,
    format: location.format,
    line: location.line,
    column: location.column_offset + 1,
    record_type: location.record_type,
  })
}
