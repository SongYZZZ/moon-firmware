name = "SongYZZZ/moon-firmware"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/SongYZZZ/moon-firmware"

license = "Apache-2.0"

keywords = [
  "firmware",
  "intel-hex",
  "srecord",
  "cortex-m",
  "release-validation",
]

preferred_target = "native"

supported_targets = "native"

description = "MCU firmware release validation: HEX, S-record, Cortex-M gates and flash plans"

import {
  "moonbitlang/x@0.5.1",
  "moonbitlang/async@0.21.2",
}
