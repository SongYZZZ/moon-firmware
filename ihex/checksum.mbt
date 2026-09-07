///|
/// Intel HEX two's complement of count, address, type and data bytes.
pub fn compute_checksum(body : Bytes) -> Byte {
  let mut sum = 0
  for b in body {
    sum = (sum + b.to_int()) & 255
  }
  ((256 - sum) & 255).to_byte()
}

///|
/// A complete decoded Intel record sums to zero modulo 256.
pub fn verify_checksum(record_bytes : Bytes) -> Bool {
  if record_bytes.is_empty() {
    return false
  }
  let mut sum = 0
  for b in record_bytes {
    sum = (sum + b.to_int()) & 255
  }
  sum == 0
}
