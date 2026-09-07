///|
/// Preserve segmented execution state instead of silently flattening CS:IP.
pub(all) enum EntryPoint {
  Linear(Int64)
  Segment(Int, Int)
} derive(Eq, Debug)

///|
/// Validated execution address in the same address space as payload.
pub fn EntryPoint::address(self : EntryPoint) -> Int64 raise FirmwareError {
  match self {
    Linear(address) => {
      ignore(data_range(address, 0))
      address
    }
    Segment(cs, ip) => {
      if cs < 0 || cs > 65535 || ip < 0 || ip > 65535 {
        raise FirmwareError(
          diagnostic(AddressOverflow, "CS and IP must be 16-bit values"),
        )
      }
      cs.to_int64() * 16L + ip.to_int64()
    }
  }
}

///|
/// Provenance survives decoding. Checksums describe source records, not hashes.
pub(all) enum ChecksumStatus {
  Verified
  NotApplicable
  Derived
} derive(Eq, Debug)

///|
/// Original record statistics and S0 header bytes, with no lossy text decoding.
pub(all) struct Metadata {
  source_format : Format
  record_counts : Array[Int]
  header : Bytes?
  checksum_status : ChecksumStatus
} derive(Eq, Debug)

///|
/// Metadata for an image assembled in memory or transformed after parsing.
pub fn Metadata::new(format : Format) -> Metadata {
  {
    source_format: format,
    record_counts: Array::make(10, 0),
    header: None,
    checksum_status: if format == RawBinary {
      NotApplicable
    } else {
      Derived
    },
  }
}

///|
/// An owned sparse map, optional entry point, source metadata and warnings.
pub(all) struct FirmwareImage {
  memory : MemoryMap
  entry : EntryPoint?
  metadata : Metadata
  warnings : Array[Diagnostic]
}

///|
/// Empty image with unknown origin.
pub fn FirmwareImage::new() -> FirmwareImage {
  {
    memory: MemoryMap::new(),
    entry: None,
    metadata: Metadata::new(Unknown),
    warnings: [],
  }
}

///|
/// Deep-copy mutable state, including metadata counters and diagnostics array.
pub fn FirmwareImage::copy(self : FirmwareImage) -> FirmwareImage {
  {
    memory: self.memory.copy(),
    entry: self.entry,
    metadata: {
      ..self.metadata,
      record_counts: self.metadata.record_counts.copy(),
    },
    warnings: self.warnings.copy(),
  }
}

///|
/// Construct a raw binary image with explicit placement.
pub fn FirmwareImage::from_binary(
  bytes : Bytes,
  base_address : Int64,
) -> FirmwareImage raise FirmwareError {
  let memory = MemoryMap::new()
  memory.insert(base_address, bytes)
  { memory, entry: None, metadata: Metadata::new(RawBinary), warnings: [], }
}

///|
/// Compare memory and exact execution state, ignoring serialization metadata.
pub fn FirmwareImage::semantic_equal(
  self : FirmwareImage,
  other : FirmwareImage,
) -> Bool {
  self.entry == other.entry && self.memory.same_memory(other.memory)
}
