///|
/// Parse a single S-record block. Strict mode enforces homogeneous data width,
/// one leading S0, at most one count, and a matching termination record.
pub fn parse_document(
  text : String,
  options? : @model.ParseOptions = @model.ParseOptions::default(),
) -> @model.FirmwareImage raise @model.FirmwareError {
  let memory = @model.MemoryMap::new()
  let warnings = []
  let counts = Array::make(10, 0)
  let mut header : Bytes? = None
  let mut entry : @model.EntryPoint? = None
  let mut data_kind = 0
  let mut data_count = 0
  let mut count_seen = false
  let mut terminated = false
  let mut total = 0
  let mut last_line = 0
  @codec.for_each_line(text, SRecord, options, warnings, source => {
    total += 1
    last_line = source.location.line
    if total > options.max_records {
      raise source.location.error(
        ResourceLimit,
        1,
        "record count limit exceeded",
      )
    }
    let record = parse_at(source.text, source.location)
    let loc = { ..source.location, record_type: Some(record.kind) }
    if terminated {
      raise loc.error(AfterTerminator, 1, "record after S-record termination")
    }
    counts[record.kind] += 1
    match record.kind {
      0 => {
        if total != 1 || header != None {
          raise loc.error(
            DuplicateRecord,
            1,
            "S0 must occur once at the beginning",
          )
        }
        header = Some(record.data)
      }
      1 | 2 | 3 => {
        if count_seen {
          raise loc.error(InvalidRecord, 1, "data record after S5/S6 count")
        }
        if data_kind != 0 && data_kind != record.kind {
          if options.mode == Strict {
            raise loc.error(
              InvalidRecord,
              2,
              "mixed S1/S2/S3 widths in one block",
            )
          }
          let @model.FirmwareError(d) = loc.error(
            InvalidRecord,
            2,
            "accepted mixed data address widths in permissive mode",
          )
          warnings.push(d)
        }
        data_kind = data_kind.max(record.kind)
        data_count += 1
        memory.insert(record.address, record.data, policy=options.overlap) catch {
          e => raise @codec.locate_error(e, loc)
        }
        if memory.payload_size() > options.max_payload {
          raise loc.error(ResourceLimit, 3, "payload limit exceeded")
        }
      }
      5 | 6 => {
        if count_seen {
          raise loc.error(DuplicateRecord, 1, "multiple S5/S6 count records")
        }
        if record.address != data_count.to_int64() {
          raise loc.error(
            CountMismatch,
            5,
            "declared \{record.address} data records but observed \{data_count}",
          )
        }
        count_seen = true
      }
      7 | 8 | 9 => {
        let expected = 10 - data_kind
        if data_kind != 0 && record.kind != expected {
          raise loc.error(
            InvalidRecord,
            2,
            "termination must be S\{expected} for the data address width",
          )
        }
        entry = Some(@model.EntryPoint::Linear(record.address))
        terminated = true
      }
      _ => ()
    }
  })
  if !terminated {
    let loc : @codec.Location = {
      format: SRecord,
      line: last_line + 1,
      column_offset: 0,
      record_type: None,
    }
    let error = loc.error(
      MissingTerminator,
      1,
      "missing S7/S8/S9 termination record",
    )
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
      source_format: SRecord,
      record_counts: counts,
      header,
      checksum_status: Verified,
    },
  }
}

///|
/// Validate record checksums, addresses, overlap policy and block structure.
pub fn validate(
  text : String,
  options? : @model.ParseOptions = @model.ParseOptions::default(),
) -> Array[@model.Diagnostic] raise @model.FirmwareError {
  parse_document(text, options~).warnings
}
