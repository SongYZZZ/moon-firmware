///|
/// The wire format or origin of an image.
pub(all) enum Format {
  IntelHex
  SRecord
  RawBinary
  Unknown
} derive(Eq, Debug)

///|
/// Machine-readable failure categories; messages add context, not identity.
pub(all) enum ErrorCode {
  InvalidDigit
  InvalidLength
  InvalidRecord
  UnsupportedRecord
  ChecksumMismatch
  MissingTerminator
  AfterTerminator
  DuplicateRecord
  CountMismatch
  AddressOverflow
  InvalidRange
  AddressConflict
  GapRequiresFill
  ResourceLimit
  InvalidOption
  UnknownFormat
  EntryConflict
  Io
} derive(Eq, Debug)

///|
/// Diagnostic locations are one-based; zero means not tied to a text line.
pub(all) struct Diagnostic {
  code : ErrorCode
  format : Format
  line : Int
  column : Int
  record_type : Int?
  address : Int64?
  end_address : Int64?
  message : String
} derive(Eq, Debug)

///|
/// Library failures always carry a structured diagnostic.
pub(all) suberror FirmwareError {
  FirmwareError(Diagnostic)
} derive(Debug)

///|
/// Create a diagnostic outside a parser; parser code supplies source fields.
pub fn diagnostic(
  code : ErrorCode,
  message : String,
  address? : Int64,
  end_address? : Int64,
) -> Diagnostic {
  {
    code,
    message,
    format: Unknown,
    line: 0,
    column: 0,
    record_type: None,
    address,
    end_address,
  }
}

///|
/// Human-readable name independent of enum debugging syntax.
pub fn Format::label(self : Format) -> String {
  match self {
    IntelHex => "Intel HEX"
    SRecord => "Motorola S-Record"
    RawBinary => "Raw binary"
    Unknown => "Unknown"
  }
}

///|
/// Stable fixed-width display for firmware addresses and range endpoints.
pub fn hex_address(address : Int64) -> String {
  "0x" + address.to_string(radix=16).to_upper().pad_start(8, '0')
}

///|
/// Render diagnostic text without losing structured address information.
pub fn Diagnostic::render(self : Diagnostic) -> String {
  let out = StringBuilder()
  if self.line > 0 {
    out.write_string("line \{self.line}")
    if self.column > 0 {
      out.write_string(", column \{self.column}")
    }
    out.write_string(": ")
  }
  out.write_string(self.message)
  match self.address {
    Some(start) => {
      out.write_string(" at " + hex_address(start))
      match self.end_address {
        Some(end) => out.write_string(".." + hex_address(end))
        None => ()
      }
    }
    None => ()
  }
  out.to_string()
}

///|
/// Strict structural validation or a small documented set of tolerances.
pub(all) enum ParseMode {
  Strict
  Permissive
} derive(Eq, Debug)

///|
/// Reject any overlap, accept byte-identical overlap, or replace existing data.
pub(all) enum OverlapPolicy {
  Reject
  AllowIdentical
  Overwrite
} derive(Eq, Debug)

///|
/// Resource limits apply before parsing or allocating output buffers.
pub(all) struct ParseOptions {
  mode : ParseMode
  overlap : OverlapPolicy
  max_line_length : Int
  max_records : Int
  max_payload : Int
  max_text_length : Int
  max_warnings : Int
} derive(Eq, Debug)

///|
/// Conservative defaults, independent of the largest address in the input.
pub fn ParseOptions::default() -> ParseOptions {
  {
    mode: Strict,
    overlap: Reject,
    max_line_length: 1024,
    max_records: 1000000,
    max_payload: 64 * 1024 * 1024,
    max_text_length: 256 * 1024 * 1024,
    max_warnings: 1024,
  }
}

///|
/// Check options once before processing untrusted records.
pub fn ParseOptions::validate(self : ParseOptions) -> Unit raise FirmwareError {
  if self.max_line_length < 11 ||
    self.max_line_length > 65536 ||
    self.max_records < 1 ||
    self.max_records > 10000000 ||
    self.max_payload < 0 ||
    self.max_payload > 64 * 1024 * 1024 ||
    self.max_text_length < 0 ||
    self.max_text_length > 256 * 1024 * 1024 ||
    self.max_warnings < 0 ||
    self.max_warnings > 65536 {
    raise FirmwareError(
      diagnostic(InvalidOption, "parse limits outside supported bounds"),
    )
  }
}
