///|
/// The update workflow is separate from legacy format/conversion options.
pub struct UpdateRequest {
  baseline : String
  overlay : String
  profile : String
  observed : String?
  output : String?
  force : Bool
  json : Bool
}

///|
fn parse_update_arguments(
  args : Array[String],
) -> Request raise @model.FirmwareError {
  let inputs = []
  let values : Map[String, String] = Map([])
  let flags : Map[String, Bool] = Map([])
  let mut literal = false
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if literal {
      inputs.push(arg)
      i += 1
      continue
    }
    if arg == "--" {
      literal = true
      i += 1
      continue
    }
    if arg == "--help" || arg == "-h" {
      return Help("plan-update")
    }
    if ["--profile", "--observed", "--output", "-o"].contains(arg) {
      let key = if arg == "-o" { "--output" } else { arg }
      if values.contains(key) {
        raise usage_error("duplicate option: " + key)
      }
      i += 1
      if i >= args.length() || args[i].is_empty() || args[i].has_prefix("--") {
        raise usage_error("missing value for " + key)
      }
      values[key] = args[i]
    } else if ["--json", "--force"].contains(arg) {
      if flags.contains(arg) {
        raise usage_error("duplicate flag: " + arg)
      }
      flags[arg] = true
    } else if arg.has_prefix("-") {
      raise usage_error("unknown plan-update option: " + arg)
    } else {
      inputs.push(arg)
    }
    i += 1
  }
  if inputs.length() != 2 || !values.contains("--profile") {
    raise usage_error(
      "plan-update requires BASELINE OVERLAY --profile TARGET.json",
    )
  }
  if flags.contains("--force") && !values.contains("--output") {
    raise usage_error("--force requires --output")
  }
  PlanUpdate({
    baseline: inputs[0],
    overlay: inputs[1],
    profile: values["--profile"],
    observed: values.get("--observed"),
    output: values.get("--output"),
    force: flags.contains("--force"),
    json: flags.contains("--json"),
  })
}

///|
async fn read_update_text(path : String, max_bytes : Int) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise usage_error("input must be a regular file: " + path)
  }
  let length = file.size()
  if length < 0L || length > max_bytes.to_int64() {
    raise usage_error("update workflow input exceeds size limit: " + path)
  }
  let bytes = file.read_exactly_at(length.to_int(), position=0L)
  if file.size() != length {
    raise usage_error("input size changed while reading: " + path)
  }
  @utf8.decode(bytes) catch {
    _ => raise usage_error("input is not valid UTF-8: " + path)
  }
}

///|
async fn run_update(request : UpdateRequest) -> Int {
  try {
    let profile = @update.parse_target_profile(
      read_update_text(request.profile, 1048576),
    )
    let baseline = @update.parse_update_image(
      read_update_text(request.baseline, 4194304),
    )
    let overlay = @update.parse_update_image(
      read_update_text(request.overlay, 4194304),
    )
    let plan = @update.plan_update(baseline, overlay, profile)
    let observed = match request.observed {
      Some(path) => @update.parse_update_image(read_update_text(path, 4194304))
      None => baseline
    }
    let simulated = @update.simulate_update(plan, observed)
    let result : Json = {
      "status": "accepted",
      "simulation": "verified",
      "baseline_source": (if request.observed is Some(_) {
        "separate_observed_snapshot"
      } else {
        "supplied_baseline_only"
      }).to_json(),
      "simulation_evidence": plan.verify_result(simulated),
      "plan": plan.to_json(),
    }
    let json = result.stringify(indent=2) + "\n"
    if request.output is Some(path) {
      write_output(path, @utf8.encode(json), request.force)
    }
    @stdio.stdout.write(
      if request.json {
        json
      } else {
        "Update plan: accepted; simulation verified\n" +
        "Affected sectors: \{plan.sector_count()}\n" +
        "Erase operations: \{plan.erase_count()}\n" +
        "Changed bytes: \{plan.changed_bytes()}\n" +
        "Program bytes: \{plan.program_bytes()}\n"
      },
    )
    0
  } catch {
    @update.UpdateError(code, message, address) => {
      let result : Json = {
        "status": "rejected",
        "code": code.to_json(),
        "message": message.to_json(),
        "address": match address {
          Some(value) => ("0x" + value.to_string(radix=16)).to_json()
          None => Json::null()
        },
      }
      @stdio.stdout.write(result.stringify() + "\n")
      if ["InputFormat", "InvalidProfile"].contains(code) {
        2
      } else {
        1
      }
    }
    error => raise error
  }
}
