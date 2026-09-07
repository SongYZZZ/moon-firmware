///|
/// Read through an opened regular-file handle, bounding size before allocation.
async fn read_input(path : String, config : Config) -> @model.FirmwareImage {
  try {
    if path.contains_char('\u0000') {
      raise usage_error("input path contains NUL")
    }
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    if file.kind() != Regular {
      raise usage_error("input must be a regular file: " + path)
    }
    let size = file.size()
    if size < 0L || size > config.parse_options.max_text_length.to_int64() {
      raise @model.FirmwareError(
        @model.diagnostic(
          ResourceLimit,
          "input file exceeds configured size limit",
        ),
      )
    }
    let bytes = file.read_exactly_at(size.to_int(), position=0L)
    if file.size() != size {
      raise usage_error("input size changed while being read: " + path)
    }
    let hint = if config.input_format != Unknown {
      config.input_format
    } else {
      @firmware.format_from_path(path)
    }
    @firmware.load_firmware(
      bytes,
      hint~,
      base_address?=config.base_address,
      options=config.parse_options,
    )
  } catch {
    @model.FirmwareError(d) =>
      raise @model.FirmwareError({ ..d, message: path + ": " + d.message, })
    e =>
      raise @model.FirmwareError(
        @model.diagnostic(Io, path + ": " + e.to_string()),
      )
  }
}

///|
/// Close staging data before rename so Windows never sees an open descriptor.
async fn write_staging(path : String, bytes : Bytes) -> Unit {
  let file = @fs.create(path, allow_existing=false, permission=0o644)
  defer file.close()
  file.write(bytes)
  file.sync()
}

///|
/// Same-directory staging protects existing output from conversion failures.
async fn write_output(path : String, bytes : Bytes, force : Bool) -> Unit {
  if path.is_empty() || path.contains_char('\u0000') {
    raise usage_error("invalid output path")
  }
  if !force && @fs.exists(path) {
    raise usage_error("output exists; pass --force to replace: " + path)
  }
  let nonce = match @env.rand(8) {
    Some(bytes) => @codec.encode_hex(bytes)
    None => raise usage_error("cannot obtain random temporary file name")
  }
  let staging = path + ".moonfirmware-" + nonce + ".tmp"
  try {
    write_staging(staging, bytes)
    @fs.rename(staging, path, replace=force)
  } catch {
    error => {
      // Cleanup is best-effort; preserve the primary write/rename failure.
      try {
        if @fs.exists(staging) {
          @fs.remove(staging)
        }
      } catch {
        _ => ()
      }
      raise @model.FirmwareError(
        @model.diagnostic(Io, path + ": " + error.to_string()),
      )
    }
  }
}

///|
async fn show_warnings(warnings : Array[@model.Diagnostic]) -> Unit {
  for warning in warnings {
    @stdio.stderr.write("warning: " + warning.render() + "\n")
  }
}
