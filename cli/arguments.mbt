///|
/// Validated command configuration. Construction stays inside the CLI package.
pub struct Config {
  command : String
  inputs : Array[String]
  output : String?
  input_format : @model.Format
  base_address : Int64?
  parse_options : @model.ParseOptions
  convert_options : @firmware.ConvertOptions
  range : @model.AddressRange?
  entry_policy : @firmware.EntryPolicy
  release_options : @validation.CortexMReleaseOptions?
  force : Bool
  json : Bool
}

///|
/// Help/version are explicit outcomes, so neither opens an input file.
pub(all) enum Request {
  Help(String)
  Version
  Run(Config)
}

///|
fn usage_error(message : String) -> @model.FirmwareError {
  @model.FirmwareError(@model.diagnostic(InvalidOption, message))
}

///|
fn parse_format(value : String) -> @model.Format raise @model.FirmwareError {
  match value.to_lower() {
    "hex" | "ihex" => IntelHex
    "srec" | "srecord" => SRecord
    "bin" | "binary" => RawBinary
    _ => raise usage_error("format must be hex, srec or bin")
  }
}

///|
fn parse_overlap(
  value : String,
) -> @model.OverlapPolicy raise @model.FirmwareError {
  match value {
    "reject" => Reject
    "identical" => AllowIdentical
    "overwrite" => Overwrite
    _ => raise usage_error("overlap must be reject, identical or overwrite")
  }
}

///|
fn parse_entry_policy(
  value : String,
) -> @firmware.EntryPolicy raise @model.FirmwareError {
  match value {
    "reject" => RejectEntryConflict
    "first" => PreferFirst
    "last" => PreferLast
    _ => raise usage_error("entry policy must be reject, first or last")
  }
}

///|
/// Parse argv without the executable name. Options may follow positionals;
/// -- terminates option processing for paths that start with a dash.
pub fn parse_arguments(
  args : Array[String],
) -> Request raise @model.FirmwareError {
  if args.is_empty() {
    return Help("")
  }
  if args[0] == "--version" {
    return Version
  }
  if args[0] == "--help" || args[0] == "-h" {
    return Help("")
  }
  let command = args[0]
  if !["inspect", "verify", "convert", "merge", "extract", "diff", "gate"].contains(
      command,
    ) {
    raise usage_error("unknown command: " + command)
  }
  let valued = [
    "--input-format", "--output-format", "--base-address", "--fill", "--start", "--end",
    "--record-length", "--address-width", "--max-output", "--overlap", "--entry-policy",
    "--flash-start", "--flash-end", "--ram-start", "--ram-end", "--vector-address",
    "--page-size", "--erase-value", "-o", "--output",
  ]
  let boolean = [
    "--permissive", "--force", "--json", "--lowercase", "--crlf", "--flatten-entry",
    "--no-count",
  ]
  let options : Map[String, String] = Map([])
  let flags : Map[String, Bool] = Map([])
  let positional = []
  let mut i = 1
  let mut literal = false
  while i < args.length() {
    let argument = args[i]
    if literal {
      positional.push(argument)
      i += 1
      continue
    }
    if argument == "--" {
      literal = true
      i += 1
      continue
    }
    if argument == "--help" || argument == "-h" {
      return Help(command)
    }
    let pair = argument.split_once("=")
    let key = match pair {
      Some((key, _)) => key.to_owned()
      None => argument
    }
    if valued.contains(key) {
      let value = match pair {
        Some((_, value)) => value.to_owned()
        None => {
          i += 1
          if i >= args.length() {
            raise usage_error("missing value for " + key)
          }
          args[i]
        }
      }
      if value.is_empty() {
        raise usage_error("empty value for " + key)
      }
      let name = if key == "-o" { "--output" } else { key }
      if options.contains(name) {
        raise usage_error("duplicate option: " + name)
      }
      options[name] = value
    } else if boolean.contains(key) {
      if pair != None {
        raise usage_error("flag takes no value: " + key)
      }
      if flags.contains(key) {
        raise usage_error("duplicate flag: " + key)
      }
      flags[key] = true
    } else if argument.has_prefix("-") {
      raise usage_error("unknown option: " + argument)
    } else {
      positional.push(argument)
    }
    i += 1
  }
  let writes = command == "convert" ||
    command == "merge" ||
    command == "extract"
  for key, _ in options {
    if [
        "--output-format", "--fill", "--record-length", "--address-width", "--max-output",
        "--output",
      ].contains(key) &&
      !writes {
      raise usage_error(key + " is only valid for output commands")
    }
    if ["--start", "--end"].contains(key) &&
      command != "extract" &&
      command != "convert" {
      raise usage_error(key + " is only valid for extract or binary convert")
    }
    if key == "--entry-policy" && command != "merge" {
      raise usage_error("--entry-policy is only valid for merge")
    }
    if [
        "--flash-start", "--flash-end", "--ram-start", "--ram-end", "--vector-address",
        "--page-size", "--erase-value",
      ].contains(key) &&
      command != "gate" {
      raise usage_error(key + " is only valid for gate")
    }
  }
  for key, _ in flags {
    if key != "--permissive" && key != "--json" && !writes {
      raise usage_error(key + " is only valid for output commands")
    }
    if key == "--json" && command != "inspect" && command != "diff" {
      raise usage_error("--json is only valid for inspect or diff")
    }
  }
  let mut output = options.get("--output")
  if command == "convert" && positional.length() == 2 && output == None {
    output = Some(positional[1])
    ignore(positional.pop())
  }
  let required = if command == "diff" { 2 } else { 1 }
  if command == "merge" {
    if positional.length() < 2 {
      raise usage_error("merge requires at least two input paths")
    }
  } else if positional.length() != required {
    raise usage_error("\{command} requires \{required} input path(s)")
  }
  if writes && output == None {
    raise usage_error("output path is required; use -o")
  }
  let range = match (options.get("--start"), options.get("--end")) {
    (Some(start), Some(end)) =>
      Some(
        @model.AddressRange::inclusive(
          @codec.parse_number(start),
          @codec.parse_number(end),
        ),
      )
    (None, None) => None
    _ =>
      raise usage_error(
        "--start and --end must be specified together (inclusive end)",
      )
  }
  if command == "extract" && range == None {
    raise usage_error("extract requires --start and --end")
  }
  let format = match options.get("--output-format") {
    Some(value) => parse_format(value)
    None =>
      match output {
        Some(path) => @firmware.format_from_path(path)
        None => @model.Format::Unknown
      }
  }
  if writes && format == Unknown {
    raise usage_error("unknown output extension; specify --output-format")
  }
  if command == "convert" && range != None && format != RawBinary {
    raise usage_error(
      "convert --start/--end selects a binary window; use extract for text formats",
    )
  }
  if options.contains("--fill") && format != RawBinary {
    raise usage_error("--fill applies to binary output")
  }
  if options.contains("--max-output") && format != RawBinary {
    raise usage_error("--max-output applies to binary output")
  }
  if format == RawBinary &&
    (
      options.contains("--record-length") ||
      flags.contains("--lowercase") ||
      flags.contains("--crlf")
    ) {
    raise usage_error("text writer options require HEX or SREC output")
  }
  let mut conversion = @firmware.ConvertOptions::new(format)
  if options.get("--fill") is Some(value) {
    conversion = {
      ..conversion,
      fill: Some(@codec.parse_number(value, max_value=255L).to_byte()),
    }
  }
  if options.get("--max-output") is Some(value) {
    conversion = {
      ..conversion,
      max_binary_size: @codec.parse_number(value, max_value=67108864L).to_int(),
    }
  }
  conversion = {
    ..conversion,
    binary_range: if command == "convert" {
      range
    } else {
      None
    },
  }
  let length = match options.get("--record-length") {
    Some(value) => @codec.parse_number(value, max_value=255L).to_int()
    None => 16
  }
  if length == 0 {
    raise usage_error("record length must be positive")
  }
  let upper = !flags.contains("--lowercase")
  let ending = if flags.contains("--crlf") {
    @codec.LineEnding::CRLF
  } else {
    LF
  }
  let width = match options.get("--address-width") {
    None | Some("auto") => @srec.AddressWidth::Auto
    Some(value) => parse_width(value)
  }
  conversion = {
    ..conversion,
    intel_hex: {
      ..conversion.intel_hex,
      data_length: length,
      uppercase: upper,
      line_ending: ending,
    },
    srecord: {
      ..conversion.srecord,
      data_length: length,
      uppercase: upper,
      line_ending: ending,
      address_width: width,
      emit_count: !flags.contains("--no-count"),
      flatten_segment_entry: flags.contains("--flatten-entry"),
    },
  }
  if format != SRecord &&
    (
      options.contains("--address-width") ||
      flags.contains("--no-count") ||
      flags.contains("--flatten-entry")
    ) {
    raise usage_error("SREC writer options require SREC output")
  }
  let overlap = match options.get("--overlap") {
    Some(value) => parse_overlap(value)
    None => @model.OverlapPolicy::Reject
  }
  let input_format = match options.get("--input-format") {
    Some(value) => parse_format(value)
    None => @model.Format::Unknown
  }
  let base_address = match options.get("--base-address") {
    Some(value) => Some(@codec.parse_number(value))
    None => None
  }
  let entry_policy = match options.get("--entry-policy") {
    Some(value) => parse_entry_policy(value)
    None => @firmware.EntryPolicy::RejectEntryConflict
  }
  let release_options = if command == "gate" {
    let required_gate = [
      "--flash-start", "--flash-end", "--ram-start", "--ram-end", "--page-size",
    ]
    for key in required_gate {
      if !options.contains(key) {
        raise usage_error("gate requires " + key)
      }
    }
    let flash = @model.AddressRange::inclusive(
      @codec.parse_number(options["--flash-start"]),
      @codec.parse_number(options["--flash-end"]),
    )
    let ram = @model.AddressRange::inclusive(
      @codec.parse_number(options["--ram-start"]),
      @codec.parse_number(options["--ram-end"]),
    )
    let vector_address = match options.get("--vector-address") {
      Some(value) => @codec.parse_number(value)
      None => flash.start
    }
    let page_size = @codec.parse_number(
      options["--page-size"],
      max_value=1048576L,
    ).to_int()
    let erase_value = match options.get("--erase-value") {
      Some(value) => @codec.parse_number(value, max_value=255L).to_byte()
      None => b'\xFF'
    }
    Some(
      @validation.CortexMReleaseOptions::new(
        flash,
        ram,
        vector_address~,
        page_size~,
        erase_value~,
      ),
    )
  } else {
    None
  }
  Run({
    command,
    inputs: positional,
    output,
    input_format,
    base_address,
    parse_options: {
      ..@model.ParseOptions::default(),
      mode: if flags.contains("--permissive") {
        Permissive
      } else {
        Strict
      },
      overlap,
    },
    convert_options: conversion,
    range,
    entry_policy,
    release_options,
    force: flags.contains("--force"),
    json: flags.contains("--json"),
  })
}

///|
fn parse_width(value : String) -> @srec.AddressWidth raise @model.FirmwareError {
  match value {
    "16" => Bits16
    "24" => Bits24
    "32" => Bits32
    _ => raise usage_error("address width must be auto, 16, 24 or 32")
  }
}
