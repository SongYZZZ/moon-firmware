///|
fn main {
  try {
    let binary = @firmware.FirmwareImage::from_binary(
      b"\x01\x02\x03\x04", 0x08000000L,
    )
    let original = {
      ..binary,
      entry: Some(@firmware.EntryPoint::Linear(0x08000001L)),
    }
    let srec = @firmware.convert(
      original,
      @firmware.ConvertOptions::new(SRecord),
    )
    let decoded = @firmware.load_firmware(srec.bytes)
    println(
      "SREC round-trip preserves memory and entry: \{original.semantic_equal(decoded)}",
    )
    println(@firmware.inspect_image(decoded).render())
  } catch {
    @firmware.FirmwareError::FirmwareError(d) => println(d.render())
  }
}
