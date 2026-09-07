///|
async test "all original positive fixtures load through real file IO" {
  for
    name in [
      "basic.hex", "extended_linear.hex", "segment_address.hex", "srec16.srec", "srec24.srec",
      "srec32.srec", "sparse.hex", "changed.hex",
    ] {
    let path = "tests/fixtures/" + name
    guard parse_arguments(["inspect", path]) is Run(config) else {
      fail("expected config")
    }
    let image = read_input(path, config)
    assert_true(image.memory.payload_size() > 0)
  }
}

///|
async test "negative fixture rejects checksum through file IO" {
  let path = "tests/fixtures/bad_checksum.hex"
  guard parse_arguments(["inspect", path]) is Run(config) else {
    fail("expected config")
  }
  try read_input(path, config) catch {
    @model.FirmwareError(d) => assert_eq(d.code, ChecksumMismatch)
    error => fail("unexpected IO error: " + error.to_string())
  } noraise {
    _ => fail("expected checksum failure")
  }
}

///|
async test "staged output Unicode path and overwrite policy" {
  let directory = @fs.tmpdir(prefix="moon-firmware-test-")
  let path = directory + "/固件.bin"
  write_output(path, b"first", false)
  try write_output(path, b"second", false) catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidOption)
    error => fail("unexpected IO error: " + error.to_string())
  } noraise {
    _ => fail("expected existing path refusal")
  }
  assert_eq(@fs.read_file(path).binary(), b"first")
  write_output(path, b"second", true)
  assert_eq(@fs.read_file(path).binary(), b"second")
  @fs.remove(path)
  @fs.rmdir(directory)
}
