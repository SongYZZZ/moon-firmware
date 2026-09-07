///|
/// Validated wire record. Address is the 16-bit offset, not an absolute address.
pub struct Record {
  kind : Int
  address : Int
  data : Bytes
} derive(Eq, Debug)

///|
/// Validate a record's structural fields, independent of document state.
pub fn Record::new(
  kind : Int,
  address : Int,
  data : Bytes,
) -> Record raise @model.FirmwareError {
  let location : @codec.Location = {
    format: IntelHex,
    line: 0,
    column_offset: 0,
    record_type: Some(kind),
  }
  check_fields(kind, address, data.length(), location)
  { kind, address, data, }
}

///|
fn check_fields(
  kind : Int,
  address : Int,
  length : Int,
  location : @codec.Location,
) -> Unit raise @model.FirmwareError {
  if kind < 0 || kind > 5 {
    raise location.error(
      UnsupportedRecord,
      8,
      "unsupported Intel HEX record type \{kind}",
    )
  }
  if address < 0 || address > 65535 {
    raise location.error(AddressOverflow, 4, "record offset must fit 16 bits")
  }
  if length > 255 {
    raise location.error(InvalidLength, 2, "record data exceeds 255 bytes")
  }
  let expected = match kind {
    0 => length
    1 => 0
    2 | 4 => 2
    _ => 4
  }
  if length != expected {
    raise location.error(
      InvalidLength,
      2,
      "record type \{kind} requires \{expected} data bytes, found \{length}",
    )
  }
  if kind != 0 && address != 0 {
    raise location.error(
      InvalidRecord,
      4,
      "control record address must be zero",
    )
  }
}

///|
/// Parse one unpadded record, always enforcing checksum and structural lengths.
pub fn parse_line(
  text : String,
  line? : Int = 1,
) -> Record raise @model.FirmwareError {
  parse_at(text, {
    format: IntelHex,
    line,
    column_offset: 0,
    record_type: None,
  })
}

///|
fn parse_at(
  text : String,
  initial : @codec.Location,
) -> Record raise @model.FirmwareError {
  if text.length() > 521 {
    raise initial.error(
      ResourceLimit,
      1,
      "Intel HEX record exceeds 521 characters",
    )
  }
  if !text.has_prefix(":") {
    raise initial.error(
      InvalidRecord,
      1,
      "expected ':' at start of Intel HEX record",
    )
  }
  let bytes = @codec.decode_hex(text, 1, initial)
  if bytes.length() < 5 {
    raise initial.error(InvalidLength, 2, "truncated Intel HEX record")
  }
  let count = bytes[0].to_int()
  let kind = bytes[3].to_int()
  let location = { ..initial, record_type: Some(kind), }
  if bytes.length() != count + 5 {
    raise location.error(
      InvalidLength,
      2,
      "expected \{count} data bytes but found \{bytes.length() - 5}",
    )
  }
  if !verify_checksum(bytes) {
    raise location.error(
      ChecksumMismatch,
      text.length() - 1,
      "checksum mismatch",
    )
  }
  let address = bytes[1].to_int() * 256 + bytes[2].to_int()
  check_fields(kind, address, count, location)
  { kind, address, data: bytes[4:4 + count].to_owned(), }
}
