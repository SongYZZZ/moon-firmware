///|
/// A validated S-record. S5/S6 use the address field as a record count.
pub struct Record {
  kind : Int
  address : Int64
  data : Bytes
} derive(Eq, Debug)

///|
/// S4 is reserved and is never treated as a data record.
pub fn address_width(kind : Int) -> Int raise @model.FirmwareError {
  match kind {
    0 | 1 | 5 | 9 => 2
    2 | 6 | 8 => 3
    3 | 7 => 4
    _ =>
      raise @model.FirmwareError(
        @model.diagnostic(
          UnsupportedRecord,
          "unsupported S-record type S\{kind}",
        ),
      )
  }
}

///|
/// Check address width, count capacity and no-data control records.
pub fn Record::new(
  kind : Int,
  address : Int64,
  data : Bytes,
) -> Record raise @model.FirmwareError {
  let width = address_width(kind)
  ignore(@codec.address_bytes(address, width))
  if data.length() > 254 - width {
    raise @model.FirmwareError(
      @model.diagnostic(InvalidLength, "S-record count exceeds 255"),
    )
  }
  if kind >= 5 && !data.is_empty() {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidLength,
        "count and termination records cannot contain data",
      ),
    )
  }
  if kind == 0 && address != 0L {
    raise @model.FirmwareError(
      @model.diagnostic(InvalidRecord, "S0 header address must be zero"),
    )
  }
  if kind >= 1 && kind <= 3 {
    ignore(@model.data_range(address, data.length()))
  }
  { kind, address, data }
}

///|
/// Parse a single line with mandatory count and independent SREC checksum checks.
pub fn parse_line(
  text : String,
  line? : Int = 1,
) -> Record raise @model.FirmwareError {
  parse_at(text, { format: SRecord, line, column_offset: 0, record_type: None })
}

///|
fn parse_at(
  text : String,
  initial : @codec.Location,
) -> Record raise @model.FirmwareError {
  if text.length() > 514 {
    raise initial.error(ResourceLimit, 1, "S-record exceeds 514 characters")
  }
  if text.length() < 2 || text[0] != 83 {
    raise initial.error(InvalidRecord, 1, "expected S-record prefix")
  }
  let kind = text[1].to_int() - 48
  let location = { ..initial, record_type: Some(kind) }
  let width = address_width(kind) catch {
    e => raise @codec.locate_error(e, location)
  }
  let bytes = @codec.decode_hex(text, 2, location)
  if bytes.is_empty() {
    raise location.error(InvalidLength, 3, "missing S-record count")
  }
  let count = bytes[0].to_int()
  if count != bytes.length() - 1 {
    raise location.error(
      InvalidLength,
      3,
      "expected \{count} bytes after count but found \{bytes.length() - 1}",
    )
  }
  if count < width + 1 {
    raise location.error(
      InvalidLength,
      3,
      "count is too small for address and checksum",
    )
  }
  if !verify_checksum(bytes) {
    raise location.error(
      ChecksumMismatch,
      text.length() - 1,
      "checksum mismatch",
    )
  }
  let address = @codec.read_address(bytes, 1, width)
  let data = bytes[1 + width:bytes.length() - 1].to_owned()
  Record::new(kind, address, data) catch {
    e => raise @codec.locate_error(e, location)
  }
}

///|
/// Encode count and address in big-endian order with a one's complement checksum.
pub fn Record::encode(
  self : Record,
  uppercase? : Bool = true,
) -> String raise @model.FirmwareError {
  let width = address_width(self.kind)
  let body = Bytes::from_array([(self.data.length() + width + 1).to_byte()]) +
    @codec.address_bytes(self.address, width) +
    self.data
  "S\{self.kind}" +
  @codec.encode_hex(body, uppercase~) +
  @codec.encode_hex(Bytes::from_array([compute_checksum(body)]), uppercase~)
}
