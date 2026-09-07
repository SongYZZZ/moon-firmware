///|
/// Execution metadata conflicts are separate from data overwrite policy.
pub(all) enum EntryPolicy {
  RejectEntryConflict
  PreferFirst
  PreferLast
} derive(Eq, Debug)

///|
/// Merge images transactionally; no caller-owned image is modified on failure.
/// Default rejects every overlap. AllowIdentical still rejects differing bytes.
pub fn merge_images(
  images : Array[@model.FirmwareImage],
  policy? : @model.OverlapPolicy = Reject,
  entry_policy? : EntryPolicy = RejectEntryConflict,
) -> @model.FirmwareImage raise @model.FirmwareError {
  if images.is_empty() {
    raise @model.FirmwareError(
      @model.diagnostic(InvalidOption, "merge requires at least one image"),
    )
  }
  let memory = @model.MemoryMap::new()
  let warnings = []
  let mut entry : @model.EntryPoint? = None
  let mut header : Bytes? = None
  for image in images {
    if image.entry is Some(value) {
      ignore(value.address())
      if entry != None && entry != image.entry {
        match entry_policy {
          RejectEntryConflict =>
            raise @model.FirmwareError(
              @model.diagnostic(
                EntryConflict,
                "merge has conflicting execution entry points",
              ),
            )
          PreferFirst =>
            warnings.push(
              @model.diagnostic(
                EntryConflict,
                "merge retained first execution entry",
              ),
            )
          PreferLast => {
            entry = image.entry
            warnings.push(
              @model.diagnostic(
                EntryConflict,
                "merge retained last execution entry",
              ),
            )
          }
        }
      } else {
        entry = image.entry
      }
    }
    if image.metadata.header is Some(value) {
      if header != None && header != Some(value) {
        warnings.push(
          @model.diagnostic(InvalidRecord, "merge retained first S0 header"),
        )
      } else {
        header = Some(value)
      }
    }
    for s in image.memory.segments() {
      memory.insert(s.start, s.data, policy~)
    }
    for d in image.warnings {
      warnings.push(d)
    }
  }
  {
    memory,
    entry,
    warnings,
    metadata: { ..@model.Metadata::new(Unknown), header, },
  }
}

///|
/// Extract a half-open window. An entry outside it is dropped with a warning.
pub fn extract_range(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
) -> @model.FirmwareImage raise @model.FirmwareError {
  let warnings = image.warnings.copy()
  let mut entry = image.entry
  if entry is Some(value) {
    if !range.contains(value.address()) {
      entry = None
      warnings.push(
        @model.diagnostic(
          InvalidRange,
          "extraction removed entry point outside the selected range",
        ),
      )
    }
  }
  {
    memory: image.memory.slice(range),
    entry,
    warnings,
    metadata: { ..@model.Metadata::new(Unknown), header: image.metadata.header },
  }
}

///|
/// Relocate all payload and execution addresses with checked signed arithmetic.
/// Segmented entry representation is replaced with Linear and diagnosed.
pub fn relocate(
  image : @model.FirmwareImage,
  delta : Int64,
) -> @model.FirmwareImage raise @model.FirmwareError {
  let memory = @model.MemoryMap::new()
  for segment in image.memory.segments() {
    let shifted = segment.range().shift(delta)
    memory.insert(shifted.start, segment.data)
  }
  let warnings = image.warnings.copy()
  let entry = match image.entry {
    Some(value) => {
      let address = value.address()
      let shifted = @model.AddressRange::inclusive(address, address).shift(
        delta,
      )
      if value is Segment(_, _) {
        warnings.push(
          @model.diagnostic(
            InvalidRecord,
            "relocation converted segmented entry to linear address",
          ),
        )
      }
      Some(@model.EntryPoint::Linear(shifted.start))
    }
    None => None
  }
  {
    memory,
    entry,
    warnings,
    metadata: { ..@model.Metadata::new(Unknown), header: image.metadata.header },
  }
}

///|
/// Remove a window, preserving both disjoint outer portions and dropping an
/// entry that points into removed memory. This never fills the new gap.
pub fn remove_range(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
) -> @model.FirmwareImage raise @model.FirmwareError {
  let memory = @model.MemoryMap::new()
  for s in image.memory.segments() {
    for retained in s.range().subtract(range) {
      let start = (retained.start - s.start).to_int()
      let end = (retained.end - s.start).to_int()
      memory.insert(retained.start, s.data[start:end].to_owned())
    }
  }
  let warnings = image.warnings.copy()
  let mut entry = image.entry
  if entry is Some(value) {
    if range.contains(value.address()) {
      entry = None
      warnings.push(
        @model.diagnostic(
          InvalidRange,
          "removed execution entry within erased window",
        ),
      )
    }
  }
  {
    memory,
    entry,
    warnings,
    metadata: { ..@model.Metadata::new(Unknown), header: image.metadata.header },
  }
}

///|
/// Fill only unoccupied bytes in a bounded window. Existing payload is retained.
pub fn fill_range(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
  value : Byte,
  max_added? : Int = 16 * 1024 * 1024,
) -> @model.FirmwareImage raise @model.FirmwareError {
  let holes = image.memory.holes_in(range)
  let mut added = 0L
  for hole in holes {
    added += hole.length()
  }
  if max_added < 0 ||
    max_added > 64 * 1024 * 1024 ||
    added > max_added.to_int64() ||
    added > (64 * 1024 * 1024 - image.memory.payload_size()).to_int64() {
    raise @model.FirmwareError(
      @model.diagnostic(ResourceLimit, "fill would exceed payload budget"),
    )
  }
  let result = image.copy()
  for hole in holes {
    result.memory.insert(hole.start, Bytes::make(hole.length().to_int(), value))
  }
  {
    ..result,
    metadata: { ..@model.Metadata::new(Unknown), header: image.metadata.header },
  }
}
