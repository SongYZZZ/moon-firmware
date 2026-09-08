# MoonFirmware

MoonFirmware is an embedded firmware image library and native CLI independently implemented in MoonBit. It parses, validates, and writes Intel HEX and Motorola S-Record, then performs conversion, merge, extraction, and address-aware diff in one sparse address model.

Author: 宋永振 ([SongYZZZ](https://github.com/SongYZZZ)) · License: Apache-2.0 · Version: 0.1.0

[中文 README](README.md) · [Design](docs/DESIGN.md) · [Format support](docs/FORMAT_SUPPORT.md) · [Testing](docs/TESTING.md) · [0.1.0 audit](docs/RELEASE_AUDIT.md)

## Why MoonFirmware

HEX and SREC files are addressed record streams rather than plain hexadecimal text. Each record carries a type, address, length, data, and checksum, and one image may occupy flash regions gigabytes apart. MoonFirmware reconstructs a `FirmwareImage`, detects overlaps and gaps, and preserves address and entry-point semantics through conversions.

MoonFirmware is not a hex editor. A hex editor focuses on raw bytes at file offsets. MoonFirmware focuses on addressed firmware images, record validation, checksums, sparse memory reconstruction, conversion, merge, extraction, diff, and embedded-tooling workflows.

## Features

- Intel HEX types 00–05 with record checksums, HEX86 segmented wrap semantics, linear 64 KiB boundary handling, and deterministic output.
- Motorola S-Record S0/S1/S2/S3/S5/S6/S7/S8/S9 with an independent checksum implementation, count validation, termination validation, and automatic address width.
- Sparse normalized `MemoryMap` whose storage follows payload size rather than the highest address.
- `Reject`, `AllowIdentical`, and `Overwrite` overlap policies; safe rejection is the default.
- All HEX/SREC/BIN directions. BIN input requires a base address; BIN gaps require an explicit fill byte.
- Multi-image merge, range extraction, address-space diff, inspect, and verify.
- Target memory-layout validation, entry-point checks, and bounded touched-page flash plans.
- CRC-32, CRC-16, additive checksums, masked search, ASCII discovery, endian word access, and Cortex-M vector inspection.
- Strict and permissive parsing. Permissive mode never accepts checksum corruption.
- Native CLI with regular-file checks, resource limits, no overwrite by default, exclusive same-directory staging, sync, and rename.

## Quick start

The tested baseline is MoonBit `moon 0.1.20260827` and `moonc 0.10.11`. The CLI targets native:

```powershell
moon update
moon run cmd/moon-firmware -- inspect tests/fixtures/basic.hex
```

The actual output is:

```text
Format: Intel HEX
Payload: 4 bytes
Segments: 1
Address range: 0x00000010 - 0x00000013
Address span: 4 bytes
Gaps: 0
Gap bytes: 0
Entry point: none
Checksum: valid
Record count: 2
Warnings: 0
```

Install a release executable with the expected name into a chosen directory:

```powershell
moon install ./cmd/moon-firmware --bin ./artifacts/install
./artifacts/install/moon-firmware.exe --version
./artifacts/install/moon-firmware.exe inspect tests/fixtures/basic.hex
```

## CLI workflows

Every command supports `--help`. Numbers are decimal or `0x` hexadecimal. Start and end options are inclusive. Content signatures take precedence over extension hints.

```powershell
moon run cmd/moon-firmware -- verify tests/fixtures/basic.hex
moon run cmd/moon-firmware -- convert tests/fixtures/basic.hex artifacts/basic.srec --force
moon run cmd/moon-firmware -- convert artifacts/basic.srec artifacts/basic-round.hex --force
moon run cmd/moon-firmware -- convert tests/fixtures/basic.hex artifacts/basic.bin --force
moon run cmd/moon-firmware -- convert artifacts/basic.bin artifacts/basic-from-bin.hex --base-address 0x10 --force
moon run cmd/moon-firmware -- convert artifacts/basic.bin artifacts/basic-from-bin.srec --base-address 0x10 --force
moon run cmd/moon-firmware -- merge tests/fixtures/basic.hex tests/fixtures/extended_linear.hex -o artifacts/merged.hex --force
moon run cmd/moon-firmware -- extract tests/fixtures/extended_linear.hex --start 0x08000001 --end 0x08000002 -o artifacts/extracted.hex --force
moon run cmd/moon-firmware -- diff tests/fixtures/basic.hex tests/fixtures/changed.hex
```

Use `--fill 0xFF` for a gapped BIN, optionally with an explicit `--start`/`--end` window. The default BIN limit is 16 MiB and the hard limit is 64 MiB. Replacing a path requires `--force`. Diff returns 0 for semantic equality, 1 for a difference, and 2 for usage, validation, parsing, or I/O errors.

Actual diff output:

```text
Identical bytes: 2
Changed bytes: 2
Added bytes: 0
Removed bytes: 0
Entry changed: false
Changed ranges:
  0x00000011..0x00000012
Only left:
  none
Only right:
  none
```

`inspect --json` and `diff --json` provide deterministic machine-readable output. Merge defaults to `--overlap reject`; `identical` and `overwrite` are available. Entry conflicts use `--entry-policy reject|first|last`.

## Library API

The root `SongYZZZ/moon-firmware` package exposes the high-level API:

- `parse_intel_hex`, `write_intel_hex`, `parse_srecord`, `write_srecord`
- `load_firmware`, `detect_format`, `convert`
- `FirmwareImage`, `MemoryMap`, `MemorySegment`, `AddressRange`
- `merge_images`, `extract_range`, `diff_images`, `inspect_image`
- `validate_layout`, `plan_flash_pages`
- `checksum_image`, `find_pattern`, `find_ascii_strings`, `inspect_cortex_m_vectors`

Protocol-level records, checksums, and writer options remain in `SongYZZZ/moon-firmware/ihex` and `SongYZZZ/moon-firmware/srec`. Both examples use the public root package:

```powershell
moon run examples/inspect
moon run examples/convert
```

The conversion example performs BIN → SREC → `FirmwareImage` and verifies memory and entry-point semantics.

## Supported records

| Format | Records | Parse | Write | Validation |
|---|---|---:|---:|---:|
| Intel HEX | 00 Data | yes | yes | length, address, checksum, overlap |
| Intel HEX | 01 EOF | yes | yes | uniqueness, ordering, missing EOF |
| Intel HEX | 02 Extended Segment | yes | parse only | length and HEX86 semantics |
| Intel HEX | 03 Start Segment | yes | yes | CS:IP entry |
| Intel HEX | 04 Extended Linear | yes | yes | 64 KiB boundaries |
| Intel HEX | 05 Start Linear | yes | yes | 32-bit entry |
| S-Record | S0/S1/S2/S3 | yes | yes | type, width, count, checksum |
| S-Record | S5/S6 | yes | yes | data-record count |
| S-Record | S7/S8/S9 | yes | yes | matching termination and entry |

The Intel writer canonicalizes addresses with Extended Linear Address records. Type 02 is parsed correctly but is not selected by the writer. S4 and unknown record types are explicit errors. See [FORMAT_SUPPORT.md](docs/FORMAT_SUPPORT.md) for strict/permissive behavior.

## Diagnostics and limits

The library raises `FirmwareError(Diagnostic)` with a typed `ErrorCode`, format, line, column, record type, address range, and message. A typical CLI error is:

```text
line 1, column 18: firmware.hex: checksum mismatch
```

User input produces diagnostics rather than panics. Checksums are mandatory in both parsing modes.

## Verification

```powershell
moon fmt --check
moon check
moon test
moon info
moon build
moon coverage analyze -- -f summary
moon bench --release benchmarks
moon package --list
```

The current local result is 231 test entries passed, including hundreds of fixed-seed generated cases. Coverage is 1,417 of 1,864 instrumented points, or 76.02%. See [BENCHMARKS.md](docs/BENCHMARKS.md) for measured performance. CI runs format, check, test, and build on Ubuntu native.

## Layout

```text
model/       sparse address model, diagnostics, policies
codec/       bounded hexadecimal and line infrastructure
ihex/        Intel HEX records, parser, writer, checksum
srec/        Motorola S-Record codec
firmware/    detection, conversion, merge, extract, diff, inspect
validation/  target layout and flash page plans
analysis/    checksums, search, word, and Cortex-M analysis
cli/         arguments, file I/O, command execution
cmd/         native moon-firmware entry
examples/    runnable Library API examples
benchmarks/  official MoonBit benchmarks
tests/       original minimal fixtures
docs/        design, format, tests, references, measurements
```

## Mooncakes status

The current `moon package` accepts the module name `SongYZZZ/moon-firmware` and produces the 0.1.0 archive with repository, license, description, keywords, and README metadata. The machine is logged into Mooncakes as `hjn0123`, so `moon publish` was deliberately not run under the wrong owner. Publication awaits the repository owner's correct Mooncakes login.

## Known limitations

- The CLI uses native file-system APIs from `moonbitlang/async` and `moonbitlang/x`; 0.1.0 is declared native-only. Parser and model code itself has no OS dependency.
- The S-Record parser handles one block and rejects S4. When an image has no entry, the writer emits a format-required zero termination address and reports a warning.
- BIN cannot retain entry points, S0 headers, or record provenance; conversion reports losses.
- All committed fixtures are original examples made from public format descriptions. No external-tool compatibility matrix has been recorded yet, so this project does not claim universal compatibility.
- Same-directory staging uses sync and rename, but does not promise directory-fsync power-loss durability or detect a same-size concurrent input rewrite.

The roadmap includes an external-tool compatibility matrix, multi-block S-Record input, optional target-profile files, streaming very-large-file input, and portable CLI backends when MoonBit I/O permits. [FORMAT_SUPPORT.md](docs/FORMAT_SUPPORT.md) is the source of truth for limitations.

Read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [REFERENCES.md](docs/REFERENCES.md), and [CHANGELOG.md](CHANGELOG.md). This implementation was written independently from public format descriptions; no source code from another language library was copied.
