///|
/// Parse a complete Intel HEX document into normalized absolute-address memory.
pub fn parse_document(
  text : String,
  options? : @model.ParseOptions = @model.ParseOptions::default(),
) -> @model.FirmwareImage raise @model.FirmwareError {
  let memory = @model.MemoryMap::new()
  let warnings = []
  let counts = Array::make(10, 0)
  let mut base = 0L
  let mut segmented = false
  let mut entry : @model.EntryPoint? = None
  let mut eof = false
  let mut total = 0
  let mut last_line = 0
  @codec.for_each_line(text, IntelHex, options, warnings, source => {
    last_line = source.location.line
    total += 1
    if total > options.max_records {
      raise source.location.error(
        ResourceLimit,
        1,
        "record count limit exceeded",
      )
    }
    let record = parse_at(source.text, source.location)
    let loc = { ..source.location, record_type: Some(record.kind), }
    if eof {
      if options.mode == Permissive && record.kind == 1 {
        let @model.FirmwareError(d) = loc.error(
          DuplicateRecord,
          1,
          "accepted duplicate EOF in permissive mode",
        )
        warnings.push(d)
        counts[1] += 1
        return
      }
      raise loc.error(AfterTerminator, 1, "record after EOF")
    }
    counts[record.kind] += 1
    match record.kind {
      0 => {
        try {
          if segmented && record.address + record.data.length() > 65536 {
            // HEX86 offsets wrap within the segment; HEX386 linear addresses carry.
            let first_length = 65536 - record.address
            memory.insert(
              base + record.address.to_int64(),
              record.data[:first_length].to_owned(),
              policy=options.overlap,
            )
            memory.insert(
              base,
              record.data[first_length:].to_owned(),
              policy=options.overlap,
            )
          } else {
            memory.insert(
              base + record.address.to_int64(),
              record.data,
              policy=options.overlap,
            )
          }
        } catch {
          e => raise @codec.locate_error(e, loc)
        }
        if memory.payload_size() > options.max_payload {
          raise loc.error(ResourceLimit, 2, "payload limit exceeded")
        }
      }
      1 => eof = true
      2 => {
        base = @codec.read_address(record.data, 0, 2) * 16L
        segmented = true
      }
      4 => {
        base = @codec.read_address(record.data, 0, 2) * 65536L
        segmented = false
      }
      3 | 5 => {
        let next = if record.kind == 3 {
          @model.EntryPoint::Segment(
            @codec.read_address(record.data, 0, 2).to_int(),
            @codec.read_address(record.data, 2, 2).to_int(),
          )
        } else {
          @model.EntryPoint::Linear(@codec.read_address(record.data, 0, 4))
        }
        if entry != None {
          if entry != Some(next) || options.mode == Strict {
            raise loc.error(
              EntryConflict,
              10,
              "duplicate or conflicting execution start record",
            )
          }
          let @model.FirmwareError(d) = loc.error(
            DuplicateRecord,
            10,
            "accepted identical execution start in permissive mode",
          )
          warnings.push(d)
        }
        entry = Some(next)
      }
      _ => () // Record construction has already rejected all unsupported types.
    }
  })
  if !eof {
    let loc : @codec.Location = {
      format: IntelHex,
      line: last_line + 1,
      column_offset: 0,
      record_type: None,
    }
    let error = loc.error(MissingTerminator, 1, "missing Intel HEX EOF record")
    if options.mode == Strict || total == 0 {
      raise error
    }
    let @model.FirmwareError(d) = error
    warnings.push(d)
  }
  {
    memory,
    entry,
    warnings,
    metadata: {
      source_format: IntelHex,
      record_counts: counts,
      header: None,
      checksum_status: Verified,
    },
  }
}

///|
/// Verify syntax, checksums, ordering, bounds and overlaps without exposing state.
pub fn validate(
  text : String,
  options? : @model.ParseOptions = @model.ParseOptions::default(),
) -> Array[@model.Diagnostic] raise @model.FirmwareError {
  parse_document(text, options~).warnings
}
