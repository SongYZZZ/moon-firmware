///|
/// Record length is configurable; output uses extended linear addressing.
pub(all) struct WriterOptions {
  data_length : Int
  uppercase : Bool
  line_ending : @codec.LineEnding
  max_output_length : Int
} derive(Eq, Debug)

///|
/// Standard 16-byte uppercase LF output with a bounded text allocation.
pub fn WriterOptions::default() -> WriterOptions {
  {
    data_length: 16,
    uppercase: true,
    line_ending: LF,
    max_output_length: 256 * 1024 * 1024,
  }
}

///|
/// Encode one validated record and compute its two's complement checksum.
pub fn Record::encode(self : Record, uppercase? : Bool = true) -> String {
  let body = [
    self.data.length().to_byte(),
    (self.address >> 8).to_byte(),
    (self.address & 255).to_byte(),
    self.kind.to_byte(),
  ]
  for b in self.data {
    body.push(b)
  }
  let bytes = Bytes::from_array(body)
  ":" +
  @codec.encode_hex(bytes, uppercase~) +
  @codec.encode_hex(Bytes::from_array([compute_checksum(bytes)]), uppercase~)
}

///|
/// Walk records without allocating the full text document. Callback failures stop
/// emission; streaming clients are responsible for staging partially written IO.
pub fn for_each_record(
  image : @model.FirmwareImage,
  visit : (Record) -> Unit raise @model.FirmwareError,
  data_length? : Int = 16,
) -> Unit raise @model.FirmwareError {
  if data_length < 1 || data_length > 255 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "Intel HEX record data length must be 1..255",
      ),
    )
  }
  if image.entry is Some(entry) {
    ignore(entry.address())
  }
  let mut upper = 0L
  for segment in image.memory.segments() {
    let mut offset = 0
    while offset < segment.data.length() {
      let absolute = segment.start + offset.to_int64()
      let next_upper = absolute >> 16
      if next_upper != upper {
        visit(Record::new(4, 0, @codec.address_bytes(next_upper, 2)))
        upper = next_upper
      }
      let low = (absolute & 65535L).to_int()
      // Split at the 64 KiB bank edge even when data_length permits more data.
      let length = data_length
        .min(segment.data.length() - offset)
        .min(65536 - low)
      visit(
        Record::new(0, low, segment.data[offset:offset + length].to_owned()),
      )
      offset += length
    }
  }
  match image.entry {
    Some(Linear(address)) =>
      visit(Record::new(5, 0, @codec.address_bytes(address, 4)))
    Some(Segment(cs, ip)) =>
      visit(
        Record::new(
          3,
          0,
          @codec.address_bytes(cs.to_int64(), 2) +
          @codec.address_bytes(ip.to_int64(), 2),
        ),
      )
    None => ()
  }
  visit(Record::new(1, 0, b""))
}

///|
/// Write a complete deterministic Intel HEX file, preserving execution metadata.
pub fn encode(
  image : @model.FirmwareImage,
  options? : WriterOptions = WriterOptions::default(),
) -> String raise @model.FirmwareError {
  let output = @codec.TextOutput::new(
    options.line_ending,
    options.max_output_length,
  )
  for_each_record(
    image,
    record => output.write_line(record.encode(uppercase=options.uppercase)),
    data_length=options.data_length,
  )
  output.finish()
}
