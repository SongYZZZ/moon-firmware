///|
/// Common firmware-level checksums. These operate on reconstructed image bytes;
/// they are distinct from Intel HEX and S-Record record checksums.
pub(all) enum ImageChecksumAlgorithm {
  Crc32Ieee
  Crc16Ccitt
  Sum8
  Sum16
  Sum32
} derive(Eq, Debug)

///|
/// Result retains the exact address window and fill choice used for holes.
pub struct ImageChecksum {
  algorithm : ImageChecksumAlgorithm
  range : @model.AddressRange
  value : Int64
  processed_bytes : Int
  filled_bytes : Int
  fill : Byte?
} derive(Eq, Debug)

///|
fn validate_checksum_window(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
  fill : Byte?,
  max_bytes : Int,
) -> Int raise @model.FirmwareError {
  if max_bytes < 0 ||
    max_bytes > 64 * 1024 * 1024 ||
    range.length() > max_bytes.to_int64() {
    raise @model.FirmwareError(
      @model.diagnostic(
        ResourceLimit,
        "checksum window exceeds configured limit",
      ),
    )
  }
  let holes = image.memory.holes_in(range)
  if !holes.is_empty() && fill == None {
    let hole = holes[0]
    raise @model.FirmwareError(
      @model.diagnostic(
        GapRequiresFill,
        "checksum window contains an address gap; specify fill",
        address=hole.start,
        end_address=hole.end - 1L,
      ),
    )
  }
  holes.fold(init=0L, fn(total, hole) { total + hole.length() }).to_int()
}

///|
fn byte_at(image : @model.FirmwareImage, address : Int64, fill : Byte?) -> Byte {
  image.memory.read(address).unwrap_or(fill.unwrap_or(b'\x00'))
}

///|
fn crc32_ieee(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
  fill : Byte?,
) -> Int64 {
  let mut crc = 0xFFFFFFFFL
  let mut address = range.start
  while address < range.end {
    crc = crc ^ byte_at(image, address, fill).to_int().to_int64()
    for _ in 0..<8 {
      crc = if (crc & 1L) != 0L { (crc >> 1) ^ 0xEDB88320L } else { crc >> 1 }
    }
    address += 1L
  }
  (crc ^ 0xFFFFFFFFL) & 0xFFFFFFFFL
}

///|
fn crc16_ccitt_false(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
  fill : Byte?,
) -> Int64 {
  let mut crc = 0xFFFFL
  let mut address = range.start
  while address < range.end {
    crc = crc ^ (byte_at(image, address, fill).to_int().to_int64() << 8)
    for _ in 0..<8 {
      crc = if (crc & 0x8000L) != 0L {
        ((crc << 1) ^ 0x1021L) & 0xFFFFL
      } else {
        (crc << 1) & 0xFFFFL
      }
    }
    address += 1L
  }
  crc
}

///|
fn additive_checksum(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
  fill : Byte?,
  mask : Int64,
) -> Int64 {
  let mut sum = 0L
  let mut address = range.start
  while address < range.end {
    sum = (sum + byte_at(image, address, fill).to_int().to_int64()) & mask
    address += 1L
  }
  sum
}

///|
/// Calculate a checksum over an explicit half-open address window. Sparse gaps
/// require an explicit fill byte, preventing accidental checksums over invented
/// data. Work and allocation are bounded independently of the highest address.
pub fn checksum_image(
  image : @model.FirmwareImage,
  range : @model.AddressRange,
  algorithm? : ImageChecksumAlgorithm = Crc32Ieee,
  fill? : Byte,
  max_bytes? : Int = 16 * 1024 * 1024,
) -> ImageChecksum raise @model.FirmwareError {
  let filled = validate_checksum_window(image, range, fill, max_bytes)
  let value = match algorithm {
    Crc32Ieee => crc32_ieee(image, range, fill)
    Crc16Ccitt => crc16_ccitt_false(image, range, fill)
    Sum8 => additive_checksum(image, range, fill, 0xFFL)
    Sum16 => additive_checksum(image, range, fill, 0xFFFFL)
    Sum32 => additive_checksum(image, range, fill, 0xFFFFFFFFL)
  }
  {
    algorithm,
    range,
    value,
    processed_bytes: range.length().to_int(),
    filled_bytes: filled,
    fill,
  }
}

///|
/// Uppercase checksum text with the conventional width of its algorithm.
pub fn ImageChecksum::hex(self : ImageChecksum) -> String {
  let digits = match self.algorithm {
    Sum8 => 2
    Crc16Ccitt | Sum16 => 4
    Crc32Ieee | Sum32 => 8
  }
  "0x" + self.value.to_string(radix=16).to_upper().pad_start(digits, '0')
}
