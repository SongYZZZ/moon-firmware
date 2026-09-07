// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "SongYZZZ/moon-firmware"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/SongYZZZ/moon-firmware"

license = "Apache-2.0"

keywords = [ "firmware", "intel-hex", "srecord", "embedded" ]

preferred_target = "native"

supported_targets = "native"

description = "Sparse firmware image toolkit: Intel HEX, Motorola S-Record and binary"

import {
  "moonbitlang/x@0.5.1",
  "moonbitlang/async@0.21.2",
}
