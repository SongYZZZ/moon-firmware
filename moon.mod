name = "SongYZZZ/moon-firmware"

version = "0.2.0"

readme = "README.md"

repository = "https://github.com/SongYZZZ/moon-firmware"

license = "Apache-2.0"

keywords = [
  "firmware",
  "intel-hex",
  "srecord",
  "cortex-m",
  "release-validation",
  "nor-flash",
  "update-planning",
]

preferred_target = "native"

supported_targets = "native"

description = "NOR update safety planning on firmware-image-toolkit: sector preservation, protection and preimage checks"

import {
  "moonbitlang/x@0.5.1",
  "moonbitlang/async@0.21.2",
  "Zzqy-yi/firmware-image-toolkit@0.1.0",
}
