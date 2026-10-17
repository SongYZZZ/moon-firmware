///|
fn sector_index(sectors : Array[Sector], address : UInt64) -> Int? {
  let mut low = 0
  let mut high = sectors.length()
  while low < high {
    let middle = low + (high - low) / 2
    if sectors[middle].start <= address {
      low = middle + 1
    } else {
      high = middle
    }
  }
  if low == 0 {
    return None
  }
  let index = low - 1
  if address < sectors[index].start + sectors[index].size.to_uint64() {
    Some(index)
  } else {
    None
  }
}

///|
/// Plan a sparse update against observed device contents. Complete baseline
/// evidence is required for every affected erase sector. Never fill an unknown
/// byte with 0xFF. Omitted update bytes mean preserve, not delete.
pub fn plan_update(
  baseline : @image.FirmwareImage,
  overlay : @image.FirmwareImage,
  profile : TargetProfile,
) -> UpdatePlan raise UpdateError {
  validate_profile(profile)
  if overlay.total_bytes() > 16777216 {
    raise UpdateError("ResourceLimit", "update exceeds 16 MiB", None)
  }
  let sectors = profile.sectors.copy()
  sectors.sort_by((a, b) => a.start.compare(b.start))
  let writable = normalize_windows(profile.writable)
  let protected_ranges = normalize_windows(profile.protected_ranges)
  let touched = Array::make(sectors.length(), false)
  let mut output_bytes = 0
  for segment in overlay.segments() {
    let data = segment.data()
    for i = 0; i < data.length(); i = i + 1 {
      let address = segment.address() + i.to_uint64()
      let index = match sector_index(sectors, address) {
        Some(index) => index
        None =>
          raise UpdateError(
            "OutsideGeometry",
            "update byte is outside erase geometry",
            Some(address),
          )
      }
      if baseline.byte_at(address) == Some(data[i]) {
        continue
      }
      if !inside(address, writable) || inside(address, protected_ranges) {
        raise UpdateError(
          "ProtectedWrite",
          "changed byte is outside writable policy or protected",
          Some(address),
        )
      }
      if !touched[index] {
        let size = sectors[index].size
        if size > profile.max_plan_bytes - output_bytes {
          raise UpdateError(
            "ResourceLimit",
            "affected sectors exceed max_plan_bytes",
            Some(address),
          )
        }
        output_bytes += size
        touched[index] = true
      }
    }
  }
  let updates = []
  for index = 0; index < sectors.length(); index = index + 1 {
    if !touched[index] {
      continue
    }
    let sector = sectors[index]
    let before = read_sector(baseline, sector)
    let after = before.to_array()
    let mut erase = false
    let mut changed = 0
    for offset = 0; offset < sector.size; offset = offset + 1 {
      let address = sector.start + offset.to_uint64()
      if overlay.byte_at(address) is Some(value) {
        after[offset] = value
        if value != before[offset] {
          changed += 1
          if (before[offset].to_int() & value.to_int()) != value.to_int() {
            erase = true
          }
        }
      }
    }
    // Even unchanged protected bytes cannot be erased and restored. Reject the
    // collateral erase rather than presenting read-modify-write as protection.
    if erase {
      for window in profile.protected_ranges {
        if overlaps(
            sector.start,
            sector.start + sector.size.to_uint64(),
            window,
          ) {
          raise UpdateError(
            "ProtectedErase",
            "erase would touch protected region " + window.name,
            Some(sector.start),
          )
        }
      }
      if !covers(sector.start, sector.start + sector.size.to_uint64(), writable) {
        raise UpdateError(
          "EraseOutsideWritable",
          "whole erase sector is not writable",
          Some(sector.start),
        )
      }
    }
    let programs = []
    for offset = 0; offset < sector.size; offset = offset + profile.program_unit {
      let mut needed = false
      for k = 0; k < profile.program_unit; k = k + 1 {
        if after[offset + k] !=
          (if erase { b'\xFF' } else { before[offset + k] }) {
          needed = true
        }
      }
      if !needed {
        continue
      }
      let address = sector.start + offset.to_uint64()
      for k = 0; k < profile.program_unit; k = k + 1 {
        if !inside(address + k.to_uint64(), writable) ||
          inside(address + k.to_uint64(), protected_ranges) {
          raise UpdateError(
            "ProtectedProgramUnit",
            "aligned program unit crosses a policy boundary",
            Some(address),
          )
        }
      }
      programs.push({
        address,
        data: Bytes::from_array(
          after[offset:offset + profile.program_unit].to_owned(),
        ),
      })
    }
    updates.push({
      sector,
      before,
      after: Bytes::from_array(after),
      erase,
      programs,
      changed,
    })
  }
  { target: profile.name, unit: profile.program_unit, updates, }
}

///|
/// Preflight every sector before any simulated writes. Matching is byte-exact;
/// CRCs in the manifest are review aids, not authentication or a substitute.
pub fn simulate_update(
  plan : UpdatePlan,
  observed : @image.FirmwareImage,
) -> @image.FirmwareImage raise UpdateError {
  for item in plan.updates {
    if read_sector(observed, item.sector) != item.before {
      raise UpdateError(
        "StaleBaseline",
        "observed sector differs from the plan preimage",
        Some(item.sector.start),
      )
    }
  }
  let mut current = observed
  for item in plan.updates {
    let memory = item.before.to_array()
    if item.erase {
      memory.fill(b'\xFF')
    }
    for program in item.programs {
      let offset = (program.address - item.sector.start).to_int()
      for k = 0; k < program.data.length(); k = k + 1 {
        let value = program.data[k]
        if (memory[offset + k].to_int() & value.to_int()) != value.to_int() {
          raise UpdateError(
            "IllegalNorTransition",
            "program attempts a zero-to-one transition",
            Some(program.address),
          )
        }
        memory[offset + k] = value
      }
    }
    let actual = Bytes::from_array(memory)
    if actual != item.after {
      raise UpdateError(
        "VerifyFailed",
        "simulated final sector differs from expected bytes",
        Some(item.sector.start),
      )
    }
    current = match current.write(item.sector.start, actual) {
      Ok(image) => image
      Err(error) =>
        raise UpdateError(
          "SimulationFailed",
          error.message(),
          Some(item.sector.start),
        )
    }
  }
  current
}

///|
/// Verify a replayed or caller-supplied result and expose only affected-sector
/// bytes for independent comparison. Never label an unchecked image verified.
pub fn UpdatePlan::verify_result(
  self : UpdatePlan,
  result_image : @image.FirmwareImage,
) -> Json raise UpdateError {
  let evidence : Array[Json] = []
  for item in self.updates {
    let actual = match
      result_image.read_range(
        item.sector.start,
        item.sector.size,
        RejectMissing,
        item.sector.size,
      ) {
      Ok(bytes) => bytes
      Err(_) =>
        raise UpdateError(
          "VerifyFailed",
          "result sector is incomplete",
          Some(item.sector.start),
        )
    }
    if actual != item.after {
      raise UpdateError(
        "VerifyFailed",
        "result differs from expected sector bytes",
        Some(item.sector.start),
      )
    }
    evidence.push({
      "address": address_text(item.sector.start).to_json(),
      "size": item.sector.size.to_json(),
      "actual_hex": @image.encode_hex_bytes(actual).to_json(),
      "actual_crc32": @image.crc32(actual).to_json(),
    })
  }
  evidence.to_json()
}

///|
/// Machine-readable ordered operations, with complete pre/postimage evidence.
/// All checks precede the first erase/program. This describes a host-side NOR
/// simulation; it is not an executable hardware driver or a signed OTA package.
pub fn UpdatePlan::to_json(self : UpdatePlan) -> Json {
  let operations : Array[Json] = []
  let sectors : Array[Json] = []
  for item in self.updates {
    operations.push({
      "op": "check_preimage",
      "address": address_text(item.sector.start).to_json(),
      "expected_hex": @image.encode_hex_bytes(item.before).to_json(),
    })
  }
  for item in self.updates {
    let address = address_text(item.sector.start).to_json()
    sectors.push({
      "name": item.sector.name.to_json(),
      "address": address,
      "size": item.sector.size.to_json(),
      "erase": item.erase.to_json(),
      "changed_bytes": item.changed.to_json(),
      "preserved_bytes": (item.sector.size - item.changed).to_json(),
      "before_crc32": item.before |> @image.crc32 |> UInt::to_json,
      "after_crc32": item.after |> @image.crc32 |> UInt::to_json,
    })
    if item.erase {
      operations.push({
        "op": "erase",
        "address": address,
        "size": item.sector.size.to_json(),
      })
    }
    for program in item.programs {
      operations.push({
        "op": "program",
        "address": address_text(program.address).to_json(),
        "data_hex": @image.encode_hex_bytes(program.data).to_json(),
      })
    }
    operations.push({
      "op": "verify",
      "address": address,
      "expected_hex": @image.encode_hex_bytes(item.after).to_json(),
    })
  }
  {
    "schema": "moonfirmware.update-plan.v1",
    "target": self.target.to_json(),
    "model": "NOR erased=FF; program clears bits; sparse overlay preserves omitted bytes",
    "entry_metadata": "overlay entry metadata is ignored; baseline entry is retained",
    "program_unit": self.unit.to_json(),
    "changed_bytes": self.changed_bytes().to_json(),
    "affected_sectors": self.sector_count().to_json(),
    "erase_count": self.erase_count().to_json(),
    "program_bytes": self.program_bytes().to_json(),
    "sectors": sectors.to_json(),
    "operations": operations.to_json(),
  }
}
