///|
/// Automatic width considers both the highest payload byte and the entry point.
pub(all) enum AddressWidth {
  Auto
  Bits16
  Bits24
  Bits32
} derive(Eq, Debug)

///|
/// Configurable canonical single-block output. CS:IP flattening is opt-in.
pub(all) struct WriterOptions {
  data_length : Int
  address_width : AddressWidth
  uppercase : Bool
  line_ending : @codec.LineEnding
  emit_count : Bool
  flatten_segment_entry : Bool
  max_output_length : Int
} derive(Eq, Debug)

///|
/// Sixteen data bytes, the smallest safe width, S5/S6 count and termination.
pub fn WriterOptions::default() -> WriterOptions {
  {
    data_length: 16,
    address_width: Auto,
    uppercase: true,
    line_ending: LF,
    emit_count: true,
    flatten_segment_entry: false,
    max_output_length: 256 * 1024 * 1024,
  }
}

///|
fn select_kind(
  image : @model.FirmwareImage,
  options : WriterOptions,
) -> (Int, Int64) raise @model.FirmwareError {
  let entry = match image.entry {
    Some(Segment(_, _)) if !options.flatten_segment_entry =>
      raise @model.FirmwareError(
        @model.diagnostic(
          InvalidOption,
          "SREC cannot retain CS:IP; explicitly enable segment entry flattening",
        ),
      )
    Some(value) => value.address()
    None => 0L
  }
  let highest = image.memory.highest_address().unwrap_or(0L).max(entry)
  let kind = match options.address_width {
    Auto =>
      if highest <= 65535L {
        1
      } else if highest <= 0xFFFFFFL {
        2
      } else {
        3
      }
    Bits16 => 1
    Bits24 => 2
    Bits32 => 3
  }
  ignore(@codec.address_bytes(highest, kind + 1))
  if options.data_length < 1 || options.data_length > 253 - kind {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "data length exceeds S\{kind} count capacity",
      ),
    )
  }
  (kind, entry)
}

///|
/// Stream canonical records in address order without building text or record arrays.
pub fn for_each_record(
  image : @model.FirmwareImage,
  visit : (Record) -> Unit raise @model.FirmwareError,
  options? : WriterOptions = WriterOptions::default(),
) -> Unit raise @model.FirmwareError {
  let (kind, entry) = select_kind(image, options)
  if image.metadata.header is Some(header) {
    visit(Record::new(0, 0L, header))
  }
  let mut count = 0
  for segment in image.memory.segments() {
    let mut offset = 0
    while offset < segment.data.length() {
      let length = options.data_length.min(segment.data.length() - offset)
      visit(
        Record::new(
          kind,
          segment.start + offset.to_int64(),
          segment.data[offset:offset + length].to_owned(),
        ),
      )
      offset += length
      count += 1
    }
  }
  if options.emit_count {
    if count > 0xFFFFFF {
      raise @model.FirmwareError(
        @model.diagnostic(ResourceLimit, "data record count cannot fit S6"),
      )
    }
    visit(
      Record::new(if count <= 65535 { 5 } else { 6 }, count.to_int64(), b""),
    )
  }
  visit(Record::new(10 - kind, entry, b""))
}

///|
/// Serialize deterministic Motorola S-Record text. Missing entry becomes zero,
/// because every standard termination record contains an address field.
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
    options~,
  )
  output.finish()
}
