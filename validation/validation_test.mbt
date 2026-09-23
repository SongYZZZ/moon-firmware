///|
fn test_image(
  pieces : Array[(Int64, Bytes)],
  entry? : @model.EntryPoint,
) -> @model.FirmwareImage raise {
  let memory = @model.MemoryMap::new()
  for piece in pieces {
    memory.insert(piece.0, piece.1)
  }
  { ..@model.FirmwareImage::new(), memory, entry, }
}

///|
fn region(
  name : String,
  start : Int64,
  end : Int64,
  executable? : Bool = false,
) -> MemoryRegion raise {
  { name, range: @model.AddressRange::new(start, end), executable, }
}

///|
fn layout_error(options : LayoutOptions) -> @model.ErrorCode raise {
  try validate_layout(@model.FirmwareImage::new(), options) catch {
    @model.FirmwareError(d) => d.code
  } noraise {
    _ => fail("expected invalid layout options")
  }
}

///|
fn flash_error(
  image : @model.FirmwareImage,
  options : FlashOptions,
) -> @model.Diagnostic raise {
  try plan_flash_pages(image, options) catch {
    @model.FirmwareError(d) => d
  } noraise {
    _ => fail("expected flash planning failure")
  }
}

///|
test "payload split across adjacent named regions is accepted" {
  let image = test_image([(0x1000L, b"abcdefgh")])
  let report = validate_layout(
    image,
    LayoutOptions::new([
      region("boot", 0x1000L, 0x1004L),
      region("app", 0x1004L, 0x1010L),
    ]),
  )
  assert_true(report.is_valid())
  assert_eq(report.issues.length(), 0)
  assert_eq(report.payload_bytes, 8)
}

///|
test "every disallowed subrange is reported without scanning gaps" {
  let image = test_image([
    (0x0FFEL, b"abcd"),
    (0x1006L, b"0123456789"),
    (0x3000L, b"xy"),
  ])
  let report = validate_layout(
    image,
    LayoutOptions::new([
      region("a", 0x1000L, 0x1008L),
      region("b", 0x100AL, 0x1010L),
    ]),
  )
  let outside = report.issues.filter(issue => {
    issue.rule == OutsideAllowedRegions
  })
  assert_eq(outside.length(), 3)
  assert_eq(outside[0].range, Some(@model.AddressRange::new(0x0FFEL, 0x1000L)))
  assert_eq(outside[1].range, Some(@model.AddressRange::new(0x1008L, 0x100AL)))
  assert_eq(outside[2].range, Some(@model.AddressRange::new(0x3000L, 0x3002L)))
}

///|
test "alignment and both budgets produce independent issues" {
  let image = test_image([(3L, b"12345"), (20L, b"x")])
  let options = {
    ..LayoutOptions::new([region("all", 0L, 32L)]),
    segment_start_alignment: 4,
    segment_length_alignment: 4,
    max_payload_bytes: 5,
    max_span_bytes: 16L,
  }
  let report = validate_layout(image, options)
  assert_eq(report.issues.length(), 5)
  assert_true(report.issues.any(issue => issue.rule == PayloadBudget))
  assert_true(report.issues.any(issue => issue.rule == SpanBudget))
  assert_eq(report.payload_bytes, 6)
  assert_eq(report.address_span, 18L)
}

///|
test "entry requirements retain warning versus error severity" {
  let options = {
    ..LayoutOptions::new([region("flash", 0L, 32L, executable=true)]),
    entry_required: Warning,
  }
  let advisory = validate_layout(@model.FirmwareImage::new(), options)
  assert_true(advisory.is_valid())
  assert_eq(advisory.issues[0].level, Warning)
  let rejecting = validate_layout(@model.FirmwareImage::new(), {
    ..options,
    entry_required: Error,
  })
  assert_false(rejecting.is_valid())
}

///|
test "entry checks distinguish mapped and executable target regions" {
  let mapped = test_image(
    [(0x2000L, b"code")],
    entry=@model.EntryPoint::Linear(0x2001L),
  )
  let options = {
    ..LayoutOptions::new([region("data", 0x2000L, 0x2010L)]),
    entry_mapped: Error,
    entry_executable: Error,
  }
  let report = validate_layout(mapped, options)
  assert_eq(report.issues.length(), 1)
  assert_eq(report.issues[0].rule, EntryNotExecutable)
  assert_eq(report.issues[0].region, Some("data"))
  let absent = test_image(
    [(0x2000L, b"code")],
    entry=@model.EntryPoint::Linear(0x3000L),
  )
  let absent_report = validate_layout(absent, options)
  assert_true(absent_report.issues.any(issue => issue.rule == EntryNotMapped))
  assert_true(
    absent_report.issues.any(issue => issue.rule == EntryNotExecutable),
  )
}

///|
test "Thumb entry normalization is explicit and does not mutate the image" {
  let image = test_image(
    [(0x08000000L, b"code")],
    entry=@model.EntryPoint::Linear(0x08000001L),
  )
  let base = {
    ..LayoutOptions::new([
      region("flash", 0x08000000L, 0x08001000L, executable=true),
    ]),
    entry_mapped: Error,
    entry_alignment: 2,
  }
  let raw = validate_layout(image, base)
  assert_true(raw.issues.any(issue => issue.rule == EntryAlignment))
  assert_eq(raw.checked_entry, Some(0x08000001L))
  let normalized = validate_layout(image, {
    ..base,
    clear_entry_thumb_bit: true,
  })
  assert_true(normalized.is_valid())
  assert_eq(normalized.checked_entry, Some(0x08000000L))
  assert_eq(image.entry, Some(@model.EntryPoint::Linear(0x08000001L)))
}

///|
test "segment entry address participates in entry validation" {
  let image = test_image(
    [(0x12350L, b"x")],
    entry=@model.EntryPoint::Segment(0x1234, 0x10),
  )
  let report = validate_layout(image, {
    ..LayoutOptions::new([region("x86", 0x12000L, 0x13000L, executable=true)]),
    entry_mapped: Error,
    entry_executable: Error,
  })
  assert_true(report.is_valid())
  assert_eq(report.checked_entry, Some(0x12350L))
}

///|
test "layout configuration rejects bad alignment budgets and regions" {
  let base = LayoutOptions::new([region("good", 0L, 16L)])
  assert_eq(
    layout_error({ ..base, segment_start_alignment: 3, }),
    InvalidOption,
  )
  assert_eq(layout_error({ ..base, max_payload_bytes: -1, }), InvalidOption)
  assert_eq(
    layout_error(
      LayoutOptions::new([region("a", 0L, 10L), region("b", 9L, 20L)]),
    ),
    InvalidOption,
  )
  assert_eq(
    layout_error(
      LayoutOptions::new([region("same", 0L, 10L), region("same", 10L, 20L)]),
    ),
    InvalidOption,
  )
  assert_eq(
    layout_error(LayoutOptions::new([region("", 0L, 10L)])),
    InvalidOption,
  )
}

///|
test "empty image creates an empty flash plan" {
  let plan = plan_flash_pages(
    @model.FirmwareImage::new(),
    FlashOptions::new(256, 0xFF),
  )
  assert_eq(plan.pages.length(), 0)
  assert_eq(plan.output_bytes, 0)
  assert_eq(plan.erase_fill_bytes, 0)
}

///|
test "flash planner fills only touched complete pages" {
  let image = test_image([(0x1002L, b"AB"), (0x100EL, b"CD"), (0x1030L, b"Z")])
  let plan = plan_flash_pages(image, FlashOptions::new(16, 0xFF))
  assert_eq(plan.pages.length(), 2)
  assert_eq(plan.pages[0].range, @model.AddressRange::new(0x1000L, 0x1010L))
  assert_eq(plan.pages[1].range, @model.AddressRange::new(0x1030L, 0x1040L))
  assert_eq(plan.pages[0].data[2:4], b"AB")
  assert_eq(plan.pages[0].data[14:16], b"CD")
  assert_eq(plan.pages[1].data[0], b'Z')
  assert_eq(plan.payload_bytes, 5)
  assert_eq(plan.output_bytes, 32)
  assert_eq(plan.erase_fill_bytes, 27)
}

///|
test "segments crossing and sharing pages coalesce deterministically" {
  let image = test_image([(14L, b"abcd"), (20L, b"xy")])
  let plan = plan_flash_pages(image, FlashOptions::new(16, 0))
  assert_eq(plan.pages.length(), 2)
  assert_eq(plan.pages[0].data[14:16], b"ab")
  assert_eq(plan.pages[1].data[0:2], b"cd")
  assert_eq(plan.pages[1].data[4:6], b"xy")
  assert_eq(plan.pages[1].source_ranges.length(), 2)
}

///|
test "highest 32-bit address fits its final flash page" {
  let image = test_image([(0xFFFFFFFFL, b"!")])
  let plan = plan_flash_pages(image, {
    ..FlashOptions::new(256, 0xFF),
    max_output_bytes: 256,
  })
  assert_eq(plan.pages[0].range.start, 0xFFFFFF00L)
  assert_eq(plan.pages[0].range.end, 0x100000000L)
  assert_eq(plan.pages[0].data[255], b'!')
}

///|
test "flash planner enforces page count and byte limits before allocation" {
  let image = test_image([(0L, b"a"), (0x1000L, b"b")])
  assert_eq(
    flash_error(image, { ..FlashOptions::new(256, 0xFF), max_pages: 1, }).code,
    ResourceLimit,
  )
  assert_eq(
    flash_error(image, {
      ..FlashOptions::new(256, 0xFF),
      max_output_bytes: 511,
    }).code,
    ResourceLimit,
  )
}

///|
test "allowed flash bounds require containment of entire pages" {
  let image = test_image([(0x1002L, b"a")])
  let options = {
    ..FlashOptions::new(256, 0xFF),
    allowed_range: Some(@model.AddressRange::new(0x1002L, 0x1003L)),
  }
  let diagnostic = flash_error(image, options)
  assert_eq(diagnostic.code, InvalidRange)
  assert_eq(diagnostic.address, Some(0x1000L))
  let accepted = plan_flash_pages(image, {
    ..options,
    allowed_range: Some(@model.AddressRange::new(0x1000L, 0x1100L)),
  })
  assert_eq(accepted.pages.length(), 1)
}

///|
test "invalid flash options are structured errors" {
  let image = @model.FirmwareImage::new()
  assert_eq(flash_error(image, FlashOptions::new(3, 0)).code, InvalidOption)
  assert_eq(
    flash_error(image, { ..FlashOptions::new(256, 0), max_pages: -1, }).code,
    InvalidOption,
  )
  assert_eq(
    flash_error(image, {
      ..FlashOptions::new(256, 0),
      max_output_bytes: 64 * 1024 * 1024 + 1,
    }).code,
    InvalidOption,
  )
}

///|
test "renderers expose actionable summaries without dumping page bytes" {
  let image = test_image([(0x1001L, b"x")])
  let report = validate_layout(image, LayoutOptions::new([]))
  assert_true(report.render().contains("Layout: invalid"))
  assert_true(report.render().contains("0x00001001..0x00001001"))
  let manifest = plan_flash_pages(image, FlashOptions::new(16, 0xFF)).render_manifest()
  assert_true(manifest.contains("Flash pages: 1"))
  assert_true(manifest.contains("0x00001000..0x0000100F: 1 payload bytes"))
}

///|
fn cortex_target() -> CortexMReleaseOptions raise {
  CortexMReleaseOptions::new(
    @model.AddressRange::new(0x08000000L, 0x08010000L),
    @model.AddressRange::new(0x20000000L, 0x20010000L),
    page_size=1024,
  )
}

///|
test "Cortex-M release gate accepts a mapped vector table and reset handler" {
  let image = test_image([
    (0x08000000L, b"\x00\x00\x01\x20\x09\x00\x00\x08\x70"),
  ])
  let report = validate_cortex_m_release(image, cortex_target())
  assert_true(report.is_valid())
  assert_eq(report.release_issues().length(), 0)
  assert_eq(report.flash_plan().unwrap().pages.length(), 1)
  assert_eq(report.vector_table().unwrap().stack_pointer(), 0x20010000L)
  assert_true(report.render().contains("Release gate: passed"))
}

///|
test "Cortex-M release gate reports missing vector bytes without crashing" {
  let image = test_image([(0x08000000L, b"short")])
  let report = validate_cortex_m_release(image, cortex_target())
  assert_false(report.is_valid())
  assert_eq(report.release_issues()[0].rule, VectorTableMissing)
  assert_eq(report.vector_table(), None)
  assert_eq(report.flash_plan(), None)
}

///|
test "Cortex-M release gate checks stack RAM Thumb state and reset mapping" {
  let image = test_image([(0x08000000L, b"\x04\x00\x00\x10\x00\x01\x00\x10")])
  let report = validate_cortex_m_release(image, cortex_target())
  let issues = report.release_issues()
  assert_true(issues.any(issue => issue.rule == StackPointerOutsideRam))
  assert_true(issues.any(issue => issue.rule == StackPointerMisaligned))
  assert_true(issues.any(issue => issue.rule == ResetThumbBitMissing))
  assert_true(issues.any(issue => issue.rule == ResetHandlerOutsideFlash))
  assert_true(issues.any(issue => issue.rule == ResetHandlerUnmapped))
  assert_false(report.is_valid())
}

///|
test "Cortex-M release gate rejects payload outside target Flash" {
  let image = test_image([
    (0x08000000L, b"\x00\x00\x01\x20\x09\x00\x00\x08\x70"),
    (0x20000000L, b"ram-payload"),
  ])
  let report = validate_cortex_m_release(image, cortex_target())
  assert_false(report.layout.is_valid())
  assert_false(report.is_valid())
  assert_true(report.render().contains("outside all allowed target regions"))
}

///|
test "Cortex-M release target validates page alignment and vector bounds" {
  let image = @model.FirmwareImage::new()
  let mut caught = false
  ignore(validate_cortex_m_release(image, { ..cortex_target(), page_size: 3, })) catch {
    @model.FirmwareError(d) => {
      caught = true
      assert_eq(d.code, InvalidOption)
    }
    _ => fail("expected FirmwareError")
  }
  assert_true(caught)
}

///|
test "Cortex-M release target rejects empty RAM regions" {
  let image = @model.FirmwareImage::new()
  let mut caught = false
  let empty_ram = @model.AddressRange::new(0x20000000L, 0x20000000L)
  ignore(
    validate_cortex_m_release(image, { ..cortex_target(), ram: [empty_ram], }),
  ) catch {
    @model.FirmwareError(d) => {
      caught = true
      assert_eq(d.code, InvalidOption)
    }
    _ => fail("expected FirmwareError")
  }
  assert_true(caught)
}

///|
test "Cortex-M release target rejects overflowing vector addresses" {
  let image = @model.FirmwareImage::new()
  let mut caught = false
  ignore(
    validate_cortex_m_release(image, {
      ..cortex_target(),
      vector_address: 9223372036854775807L,
    }),
  ) catch {
    @model.FirmwareError(d) => {
      caught = true
      assert_eq(d.code, InvalidOption)
    }
    _ => fail("expected FirmwareError")
  }
  assert_true(caught)
}
