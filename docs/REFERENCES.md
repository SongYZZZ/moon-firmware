# 参考资料与来源说明

MoonFirmware 依据公开格式说明独立实现，没有复制其他语言 Intel HEX／S-Record 库的实现代码。以下资料用于确认 wire format、地址计算、记录含义和 MoonBit 当前工具行为。

## Intel HEX

- Arm Keil，《General: Intel HEX File Format》：<https://www.keil.com/support/docs/1584/_hlp_hexfile.htm>。用于确认记录结构、two's complement checksum、Data／EOF／Extended Segment／Extended Linear／Start Linear 类型与地址基值。
- Renesas CS+，《Hexadecimal file》：<https://tool-support.renesas.com/autoupdate/support/onlinehelp/csp/V8.06.00/CS%2B.chm/Compiler-CCRL.chm/Output/ccrl03c0501y.html>。用于核对包含 Start Segment Address 的六种 Intel HEX record。
- Microchip 在线文档，《Intel HEX File Format》：<https://onlinedocs.microchip.com/oxy/GUID-C3F66E96-7CDD-47A0-9AB7-9068BADB46C0-en-US-4/GUID-DF9E479D-6BA8-49E3-A2A5-997BBA49D34D.html>。用于交叉核对字段和 checksum 描述。

关于 HEX86 data offset 跨过 `0xFFFF` 后在同一 segment base 回绕的边缘情况，额外阅读了 hex2bin issue #26 的互操作讨论：<https://sourceforge.net/p/hex2bin/bugs/26/>。该页面用于理解标准边缘行为，未复制其中任何 C 代码。页面所涉 hex2bin／SRecord 仅作为行为讨论，不作为项目运行依赖或 fixture 来源。

## Motorola S-Record

- SRecord 项目维护的 `srec_motorola(5)` 手册：<https://manpages.debian.org/experimental/srecord/srec_motorola.5.en.html>。用于确认 count、address width、ones' complement checksum、S0～S9 记录用途与限制。本文档是协议资料；MoonFirmware 没有复制 SRecord 项目源码。

## MoonBit

- MoonBit 包配置：<https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html>。用于确认现代 `moon.pkg`、`pkgtype(kind: "executable")` 和 package 名由目录决定。
- MoonBit 模块配置：<https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html>。用于确认 `moon.mod` metadata。
- MoonBit package 与 `pub using`：<https://docs.moonbitlang.com/en/latest/language/packages.html>。用于设计根包 re-export。
- MoonBit 命令：<https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html>。实际机器上的 `moon --help` 与各子命令 help 仍是最终依据。
- `hustcer/setup-moonbit@v1.22`：<https://github.com/hustcer/setup-moonbit>。2026-09-07 检查上游 README 与 action metadata 后用于 GitHub Actions。

## 依赖与许可证

- `moonbitlang/async@0.21.2`：CLI 原生异步文件 IO。Mooncakes package 中声明的许可证为 Apache-2.0。
- `moonbitlang/x@0.5.1`：原生退出码与系统接口。Mooncakes package 中声明的许可证为 Apache-2.0。
- MoonBit core：编译器随附标准库，许可证见其官方发行内容。

所有提交的 `tests/fixtures` 都是本项目根据上述格式描述编写的最小样例，没有再分发第三方固件。若未来引入外部 fixture，必须先确认许可证，并在这里记录项目、仓库、版本、文件、许可证和用途。

## 既有项目核查

- `Zzqy-yi/moonbit-firmware-image`：<https://github.com/Zzqy-yi/moonbit-firmware-image>，Apache-2.0。2026-09-10 因黑客松初审意见核查其公开 README、目录和接口，用于说明参赛项目的重叠与互补边界；未复制其实现代码。核查结果见 `PRIOR_ART_AND_BOUNDARY.md`。
