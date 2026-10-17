///|
async test "accepted update writes a verified manifest through real file IO" {
  let directory = @fs.tmpdir(prefix="moon-update-accepted-")
  let path = directory + "/plan.json"
  guard parse_arguments([
      "plan-update", "tests/fixtures/update/baseline.hex", "tests/fixtures/update/program-overlay.hex",
      "--profile", "tests/fixtures/update/target.json", "-o", path,
    ])
    is PlanUpdate(request) else {
    fail("expected update request")
  }
  assert_eq(run_update(request), 0)
  let text = read_update_text(path, 1048576)
  assert_true(text.contains("moonfirmware.update-plan.v1"))
  assert_true(text.contains("\"simulation\": \"verified\""))
  @fs.remove(path)
  @fs.rmdir(directory)
}

///|
async test "protected erase refusal cannot create an output manifest" {
  let directory = @fs.tmpdir(prefix="moon-update-refused-")
  let path = directory + "/plan.json"
  guard parse_arguments([
      "plan-update", "tests/fixtures/update/baseline.hex", "tests/fixtures/update/erase-overlay.hex",
      "--profile", "tests/fixtures/update/shared-calibration.json", "-o", path,
    ])
    is PlanUpdate(request) else {
    fail("expected update request")
  }
  assert_eq(run_update(request), 1)
  assert_false(@fs.exists(path))
  @fs.rmdir(directory)
}

///|
async test "accepted update cannot overwrite existing output without force" {
  let directory = @fs.tmpdir(prefix="moon-update-existing-")
  let path = directory + "/plan.json"
  write_output(path, b"existing", false)
  guard parse_arguments([
      "plan-update", "tests/fixtures/update/baseline.hex", "tests/fixtures/update/program-overlay.hex",
      "--profile", "tests/fixtures/update/target.json", "-o", path,
    ])
    is PlanUpdate(request) else {
    fail("expected update request")
  }
  try run_update(request) catch {
    @model.FirmwareError(d) => assert_eq(d.code, InvalidOption)
    error => fail("unexpected update error: " + error.to_string())
  } noraise {
    _ => fail("expected output overwrite refusal")
  }
  assert_eq(read_update_text(path, 1048576), "existing")
  @fs.remove(path)
  @fs.rmdir(directory)
}
