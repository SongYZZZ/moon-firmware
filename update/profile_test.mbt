///|
fn replaced(text : String, old : String, new : String) -> String {
  text.replace(old=old[:], new=new[:])
}

///|
fn profile_json() -> String {
  let text =
    #|{"schema":"moonfirmware.target.v1","name":"test-nor","program_unit":4,"sectors":[{"name":"app","start":"0x1000","size":16}],"writable":[{"name":"app","start":"0x1000","end_exclusive":"0x1010"}],"protected":[],"max_plan_bytes":1024}
  text
}

///|
fn json_profile_error(text : String) -> String raise {
  try @update.parse_target_profile(text) catch {
    @update.UpdateError(code, _, _) => code
  } noraise {
    _ => fail("expected profile rejection")
  }
}

///|
test "versioned JSON profile retains exact addresses and geometry" {
  let target = @update.parse_target_profile(profile_json())
  assert_eq(target.sectors[0].start, 0x1000UL)
  assert_eq(target.sectors[0].size, 16)
  assert_eq(target.program_unit, 4)
}

///|
test "profile JSON rejects invalid syntax and missing fields" {
  for text in ["{", "{}", "[]", "null", "true"] {
    assert_eq(json_profile_error(text), "InvalidProfile")
  }
}

///|
test "unknown safety fields and schema versions are refused" {
  assert_eq(
    json_profile_error(
      replaced(profile_json(), "\"program_unit\"", "\"program_unt\""),
    ),
    "InvalidProfile",
  )
  assert_eq(
    json_profile_error(replaced(profile_json(), "target.v1", "target.v2")),
    "InvalidProfile",
  )
}

///|
test "profile JSON rejects float, negative and string sizes" {
  for value in ["1.5", "-16", "\"16\"", "0", "16777217"] {
    assert_eq(
      json_profile_error(
        replaced(profile_json(), "\"size\":16", "\"size\":" + value),
      ),
      "InvalidProfile",
    )
  }
}

///|
test "addresses are explicit strings with 32-bit bounds" {
  for value in ["4096", "\"-1\"", "\"0x100000001\"", "null"] {
    assert_eq(
      json_profile_error(
        replaced(profile_json(), "\"start\":\"0x1000\"", "\"start\":" + value),
      ),
      "InvalidProfile",
    )
  }
}

///|
test "empty and reversed policy windows are refused" {
  assert_eq(
    json_profile_error(replaced(profile_json(), "0x1010", "0x1000")),
    "InvalidProfile",
  )
  assert_eq(
    json_profile_error(replaced(profile_json(), "0x1010", "0x0FFF")),
    "InvalidProfile",
  )
}

///|
test "profile names, interval counts and budgets are bounded" {
  assert_eq(profile_error({ ..profile(), name: "", }), "InvalidProfile")
  assert_eq(
    profile_error({ ..profile(), max_plan_bytes: 16777217, }),
    "InvalidProfile",
  )
  assert_eq(profile_error({ ..profile(), sectors: [], }), "InvalidProfile")
  assert_eq(profile_error({ ..profile(), writable: [], }), "InvalidProfile")
}

///|
test "adjacent policy ranges form a single writable union" {
  let target = {
    ..profile(),
    writable: [
      { name: "right", start: 0x1008UL, end_exclusive: 0x1030UL, },
      { name: "left", start: 0x1000UL, end_exclusive: 0x1008UL, },
    ],
  }
  let plan = @update.plan_update(
    baseline(),
    make_image([(0x1000UL, b"\xFF")]),
    target,
  )
  assert_eq(plan.erase_count(), 1)
}

///|
test "sectors supplied out of order produce the same deterministic plan" {
  let target = profile()
  let reverse = { ..target, sectors: [target.sectors[1], target.sectors[0]], }
  let delta = make_image([(0x1000UL, b"\x00"), (0x1010UL, b"\x00")])
  assert_eq(
    @update.plan_update(baseline(), delta, target).to_json(),
    @update.plan_update(baseline(), delta, reverse).to_json(),
  )
}
