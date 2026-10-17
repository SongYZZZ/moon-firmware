///|
test "update CLI requires two inputs and a target profile" {
  for
    args in [
      ["plan-update"],
      ["plan-update", "old.hex", "new.hex"],
      ["plan-update", "old.hex", "--profile", "target.json"],
    ] {
    assert_eq(rejected(args).code, InvalidOption)
  }
}

///|
test "update CLI rejects irrelevant legacy and duplicate options" {
  for
    options in [
      ["--page-size", "1024"],
      ["--fill", "0xFF"],
      ["--profile", "other.json"],
      ["--force"],
      ["--json", "--json"],
      ["--observed"],
    ] {
    assert_eq(
      rejected(
        ["plan-update", "old.hex", "overlay.hex", "--profile", "target.json"] +
        options,
      ).code,
      InvalidOption,
    )
  }
}

///|
test "update CLI exposes independent request and help" {
  assert_true(
    @cli.parse_arguments(["plan-update", "--help"]) is Help("plan-update"),
  )
  assert_true(
    @cli.parse_arguments([
      "plan-update", "old.hex", "overlay.hex", "--profile", "target.json", "--json",
    ])
    is PlanUpdate(_),
  )
}
