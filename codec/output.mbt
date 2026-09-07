///|
/// Only standard line endings are emitted by the text writers.
pub(all) enum LineEnding {
  LF
  CRLF
} derive(Eq, Debug)

///|
/// Bounded text sink shared by format writers; never stores an array of lines.
pub struct TextOutput {
  priv builder : StringBuilder
  priv mut length : Int
  priv limit : Int
  priv ending : String
}

///|
/// Validate output budget before allocation. The hard limit is 256 Mi characters.
pub fn TextOutput::new(
  ending : LineEnding,
  limit : Int,
) -> TextOutput raise @model.FirmwareError {
  if limit < 0 || limit > 256 * 1024 * 1024 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "text output limit must be between 0 and 256 Mi characters",
      ),
    )
  }
  {
    builder: StringBuilder(),
    length: 0,
    limit,
    ending: if ending == LF {
      "\n"
    } else {
      "\r\n"
    },
  }
}

///|
/// Check incremental encoded size before adding each bounded protocol record.
pub fn TextOutput::write_line(
  self : TextOutput,
  line : String,
) -> Unit raise @model.FirmwareError {
  if line.length() > self.limit - self.length - self.ending.length() {
    raise @model.FirmwareError(
      @model.diagnostic(ResourceLimit, "encoded document exceeds output limit"),
    )
  }
  self.builder.write_string(line)
  self.builder.write_string(self.ending)
  self.length += line.length() + self.ending.length()
}

///|
/// Finish deterministic ASCII text after all record checks succeed.
pub fn TextOutput::finish(self : TextOutput) -> String {
  self.builder.to_string()
}
