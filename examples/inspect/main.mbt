///|
fn main {
  let image = @firmware.load_firmware(b":0400100001020304E2\n:00000001FF\n") catch {
    @firmware.FirmwareError::FirmwareError(d) => {
      println(d.render())
      return
    }
  }
  println(@firmware.inspect_image(image).render())
}
