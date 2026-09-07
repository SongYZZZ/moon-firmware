///|
/// Motorola S-Record one's complement of count, address and data bytes.
/// This is deliberately independent of Intel HEX two's complement arithmetic.
pub fn compute_checksum(body : Bytes) -> Byte {
  let mut sum = 0
  for b in body {
    sum = (sum + b.to_int()) & 255
  }
  (255 - sum).to_byte()
}

///|
/// A decoded S-record including its checksum sums to 0xFF modulo 256.
pub fn verify_checksum(record_bytes : Bytes) -> Bool {
  if record_bytes.is_empty() {
    return false
  }
  let mut sum = 0
  for b in record_bytes {
    sum = (sum + b.to_int()) & 255
  }
  sum == 255
}
