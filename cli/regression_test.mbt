///|
test "binary size limit cannot silently apply to text output" {
  assert_eq(
    rejected(["convert", "a.hex", "b.hex", "--max-output", "32"]).code,
    InvalidOption,
  )
}

///|
test "text formatting options cannot silently apply to binary output" {
  for option in ["--lowercase", "--crlf"] {
    assert_eq(
      rejected(["convert", "a.hex", "b.bin", option]).code,
      InvalidOption,
    )
  }
  assert_eq(
    rejected(["convert", "a.hex", "b.bin", "--record-length", "16"]).code,
    InvalidOption,
  )
}
