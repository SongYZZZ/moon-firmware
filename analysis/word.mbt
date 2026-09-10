///|
/// Integer byte order for addressed word reads and reference scans.
pub(all) enum ByteOrder {
  LittleEndian
  BigEndian
} derive(Eq, Debug)

///|
/// Read one unsigned 1..4 byte integer from consecutive occupied addresses.
/// The result uses Int64 so every 32-bit bit pattern remains nonnegative.
pub fn read_uint(
  image : @model.FirmwareImage,
  address : Int64,
  width : Int,
  order? : ByteOrder = LittleEndian,
) -> Int64 raise @model.FirmwareError {
  if width < 1 || width > 4 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "integer width must be between 1 and 4 bytes",
      ),
    )
  }
  ignore(@model.data_range(address, width))
  let mut value = 0L
  for index in 0..<width {
    let source = if order == LittleEndian { width - 1 - index } else { index }
    let byte_address = address + source.to_int64()
    let byte = match image.memory.read(byte_address) {
      Some(value) => value
      None =>
        raise @model.FirmwareError(
          @model.diagnostic(
            InvalidRange,
            "integer read crosses an unmapped address",
            address=byte_address,
          ),
        )
    }
    value = value * 256L + byte.to_int().to_int64()
  }
  value
}

///|
/// Encode one unsigned 1..4 byte integer with explicit byte order.
pub fn encode_uint(
  value : Int64,
  width : Int,
  order? : ByteOrder = LittleEndian,
) -> Bytes raise @model.FirmwareError {
  if width < 1 || width > 4 || value < 0L || value >= 1L << (width * 8) {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "unsigned integer does not fit requested width",
      ),
    )
  }
  Bytes::makei(width, index => {
    let shift = if order == LittleEndian {
      index * 8
    } else {
      (width - 1 - index) * 8
    }
    ((value >> shift) & 255L).to_byte()
  })
}

///|
/// Return an image copy with encoded bytes applied under an explicit overlap
/// policy. The source image remains unchanged if encoding or insertion fails.
pub fn write_uint(
  image : @model.FirmwareImage,
  address : Int64,
  value : Int64,
  width : Int,
  order? : ByteOrder = LittleEndian,
  policy? : @model.OverlapPolicy = Overwrite,
) -> @model.FirmwareImage raise @model.FirmwareError {
  let bytes = encode_uint(value, width, order~)
  let result = image.copy()
  result.memory.insert(address, bytes, policy~)
  { ..result, metadata: @model.Metadata::new(Unknown), }
}

///|
/// Find occupied words equal to an unsigned value. Candidates are checked at
/// a caller-selected alignment and cannot cross gaps. Results are sorted.
pub fn find_uint(
  image : @model.FirmwareImage,
  value : Int64,
  width : Int,
  order? : ByteOrder = LittleEndian,
  alignment? : Int = 1,
  max_matches? : Int = 100000,
) -> Array[Int64] raise @model.FirmwareError {
  let needle = encode_uint(value, width, order~)
  if alignment < 1 ||
    alignment > 1024 * 1024 ||
    (alignment & (alignment - 1)) != 0 ||
    max_matches < 0 ||
    max_matches > 1000000 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "word search alignment or match limit is invalid",
      ),
    )
  }
  let result = []
  for segment in image.memory.segments() {
    let last = segment.data.length() - width
    if last >= 0 {
      for offset in 0..<=last {
        let address = segment.start + offset.to_int64()
        if address % alignment.to_int64() == 0L &&
          segment.data[offset:offset + width] == needle {
          if result.length() >= max_matches {
            raise @model.FirmwareError(
              @model.diagnostic(ResourceLimit, "word match limit exceeded"),
            )
          }
          result.push(address)
        }
      }
    }
  }
  result
}

///|
/// Minimal Cortex-M vector information at an explicit vector-table base.
pub struct CortexMVectorTable {
  base_address : Int64
  initial_stack_pointer : Int64
  reset_vector : Int64
  reset_address : Int64
  thumb : Bool
  stack_aligned : Bool
  reset_mapped : Bool
} derive(Eq, Debug)

///|
/// Address from which the first two Cortex-M vectors were decoded.
pub fn CortexMVectorTable::base(self : CortexMVectorTable) -> Int64 {
  self.base_address
}

///|
/// Initial main stack pointer stored in vector slot zero.
pub fn CortexMVectorTable::stack_pointer(self : CortexMVectorTable) -> Int64 {
  self.initial_stack_pointer
}

///|
/// Raw reset vector, including the architectural Thumb-state bit.
pub fn CortexMVectorTable::raw_reset_vector(self : CortexMVectorTable) -> Int64 {
  self.reset_vector
}

///|
/// Reset handler address with the Thumb-state bit cleared.
pub fn CortexMVectorTable::reset_handler(self : CortexMVectorTable) -> Int64 {
  self.reset_address
}

///|
/// Whether the raw reset vector selects Thumb state.
pub fn CortexMVectorTable::has_thumb_bit(self : CortexMVectorTable) -> Bool {
  self.thumb
}

///|
/// Whether the initial stack pointer meets the requested alignment.
pub fn CortexMVectorTable::is_stack_aligned(self : CortexMVectorTable) -> Bool {
  self.stack_aligned
}

///|
/// Whether the normalized reset handler has a byte in the sparse image.
pub fn CortexMVectorTable::is_reset_mapped(self : CortexMVectorTable) -> Bool {
  self.reset_mapped
}

///|
/// Decode the first two little-endian Cortex-M vectors without assuming that
/// the image starts at address zero. This inspects structure only; device-
/// specific RAM and executable-region checks belong in target layout policy.
pub fn inspect_cortex_m_vectors(
  image : @model.FirmwareImage,
  base_address : Int64,
  stack_alignment? : Int = 8,
) -> CortexMVectorTable raise @model.FirmwareError {
  if stack_alignment < 1 ||
    stack_alignment > 1024 ||
    (stack_alignment & (stack_alignment - 1)) != 0 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "stack alignment must be a power of two up to 1024",
      ),
    )
  }
  let stack = read_uint(image, base_address, 4)
  let reset = read_uint(image, base_address + 4L, 4)
  let target = reset & 0xFFFFFFFEL
  {
    base_address,
    initial_stack_pointer: stack,
    reset_vector: reset,
    reset_address: target,
    thumb: (reset & 1L) != 0L,
    stack_aligned: stack % stack_alignment.to_int64() == 0L,
    reset_mapped: image.memory.contains(target),
  }
}
