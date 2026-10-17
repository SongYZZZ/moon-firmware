///|
/// Small API example; full 16/64/16 KiB evidence is in tests/fixtures/update.
fn main {
  let old = @image.FirmwareImage::from_chunks([
    @image.FirmwareChunk::create(0x1000UL, b"\xA5\xA5\xA5\xA5\xA5\xA5\xA5\xA5").unwrap(),
  ]).unwrap()
  let overlay = @image.FirmwareImage::from_chunks([
    @image.FirmwareChunk::create(0x1001UL, b"\xFF").unwrap(),
  ]).unwrap()
  let target : @planner.TargetProfile = {
    name: "api-example",
    program_unit: 4,
    sectors: [{ name: "app", start: 0x1000UL, size: 8, }],
    writable: [{ name: "app", start: 0x1000UL, end_exclusive: 0x1008UL, }],
    protected_ranges: [],
    max_plan_bytes: 1024,
  }
  try {
    let plan = @planner.plan_update(old, overlay, target)
    let simulated = @planner.simulate_update(plan, old)
    if simulated.byte_at(0x1001UL) != Some(b'\xFF') ||
      simulated.byte_at(0x1002UL) != Some(b'\xA5') {
      abort("unexpected update result")
    }
    println(
      "Changed bytes: \{plan.changed_bytes()}; erase operations: \{plan.erase_count()}",
    )
    println("Unmentioned bytes preserved; NOR simulation verified")
  } catch {
    @planner.UpdateError(code, message, _) => abort(code + ": " + message)
  }
}
