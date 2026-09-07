///|
/// Command-specific help is also the source of truth for CLI syntax.
pub fn help(command : String) -> String {
  let out = StringBuilder()
  out.write_string("MoonFirmware 0.1.0 - addressed firmware image toolkit\n\n")
  match command {
    "inspect" =>
      out.write_string(
        "Usage: moon-firmware inspect INPUT [--json]\nShow address bounds, payload, segments, gaps, entry and record counts.\n",
      )
    "verify" =>
      out.write_string(
        "Usage: moon-firmware verify INPUT\nValidate records, checksums, address bounds and overlaps.\n",
      )
    "convert" =>
      out.write_string(
        "Usage: moon-firmware convert INPUT OUTPUT [OPTIONS]\nConvert HEX / SREC / BIN. A binary window uses inclusive --start and --end.\n",
      )
    "merge" =>
      out.write_string(
        "Usage: moon-firmware merge INPUT INPUT... -o OUTPUT [OPTIONS]\nMerge in argument order. Default rejects all overlaps.\n  --entry-policy reject|first|last\n",
      )
    "extract" =>
      out.write_string(
        "Usage: moon-firmware extract INPUT --start ADDRESS --end ADDRESS -o OUTPUT\nEnd address is inclusive; holes remain sparse in text formats.\n",
      )
    "diff" =>
      out.write_string(
        "Usage: moon-firmware diff LEFT RIGHT [--json]\nCompare occupied addresses. Exit 1 if bytes or entry differ; 0 if equal.\n",
      )
    _ =>
      out.write_string(
        "Usage: moon-firmware COMMAND [OPTIONS]\nCommands: inspect, verify, convert, merge, extract, diff\nUse COMMAND --help for details.\n",
      )
  }
  out.write_string(
    "\nInput options:\n  --input-format hex|srec|bin   Hint for ambiguous input (signature wins)\n  --base-address ADDRESS      Required for BIN input\n  --permissive                Documented tolerances, checksum still mandatory\n  --overlap reject|identical|overwrite\n",
  )
  if command == "" || ["convert", "merge", "extract"].contains(command) {
    out.write_string(
      "\nOutput options:\n  -o, --output PATH\n  --output-format hex|srec|bin\n  --record-length N           Default 16\n  --fill BYTE                 Required for BIN gaps\n  --max-output BYTES          BIN limit, default 16777216; hard cap 67108864\n  --address-width auto|16|24|32   SREC only\n  --no-count                  Omit SREC S5/S6\n  --flatten-entry             Allow SREC CS:IP flattening\n  --lowercase                 Lowercase hex digits\n  --crlf                      Windows line endings\n  --force                     Replace existing output via staged rename\n",
    )
  }
  out.write_string(
    "\nNumbers: unsigned decimal or 0x hexadecimal. Addresses are bytes.\n-- stops option parsing. Exit 2 for usage, parse, validation or IO errors.\n--help / -h shows help; --version shows version.\n",
  )
  out.to_string()
}
