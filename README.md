# MoonFirmware

MoonFirmware 是用 MoonBit 独立实现的嵌入式固件镜像工具库与原生 CLI。它解析、校验并生成 Intel HEX 和 Motorola S-Record，在统一的稀疏地址空间中完成 HEX、SREC、BIN 转换、合并、截取和地址级 diff。

作者：宋永振（[SongYZZZ](https://github.com/SongYZZZ)）　许可证：Apache-2.0　版本：0.1.0

[English README](README_EN.md) · [设计](docs/DESIGN.md) · [格式支持](docs/FORMAT_SUPPORT.md) · [测试](docs/TESTING.md) · [0.1.0 审计](docs/RELEASE_AUDIT.md)

## 它解决什么问题

HEX 和 SREC 不是普通的十六进制文本：每条记录都带地址、类型、长度和 checksum，镜像还可能分布在相距很远的 flash 区域。MoonFirmware 将记录恢复为 `FirmwareImage`，因此能够发现地址冲突和空洞，并在格式转换时保留真正的地址与入口点语义。

MoonFirmware 不是 Hex Editor。Hex Editor 主要查看和修改文件偏移处的原始字节；MoonFirmware 处理 MCU/Bootloader 工具链中的带地址固件镜像、record validation、checksum、稀疏内存重建、转换、合并、截取和比较。

## 已实现功能

- Intel HEX：00、01、02、03、04、05，全记录 checksum、HEX86 段地址回绕、跨 64 KiB 线性地址切换、确定性 writer。
- Motorola S-Record：S0、S1、S2、S3、S5、S6、S7、S8、S9，独立 checksum、计数与终止记录校验、地址宽度自动选择。
- 稀疏 `MemoryMap`：内存主要随 payload 增长；排序 segment、相邻合并、gap 查询、切片和有上限的 BIN 展开。
- overlap 策略：`Reject`、`AllowIdentical`、`Overwrite`；默认拒绝任何重叠。
- HEX、SREC、BIN 全向转换；BIN 输入要求 base address，BIN 空洞要求显式 fill。
- 多镜像 merge、范围 extract、地址级 diff、inspect、verify。
- 目标内存布局校验、入口点检查和仅包含已触及页的 flash page plan。
- 镜像 CRC-32/CRC-16/additive checksum、掩码模式搜索、ASCII 字符串、字节序整数和 Cortex-M 向量表检查。
- Strict 与 Permissive 解析；宽松模式仍拒绝 checksum 损坏。
- 原生 CLI 安全限制：普通文件检查、输入与输出上限、默认拒绝覆盖、同目录排他临时文件、`sync` 后 rename。

## 快速体验

当前工具链基线为 MoonBit `moon 0.1.20260827`、`moonc 0.10.11`，CLI 使用 native 后端。源码运行：

```powershell
moon update
moon run cmd/moon-firmware -- inspect tests/fixtures/basic.hex
```

实际输出：

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

安装一个名为 `moon-firmware` 的 release 可执行文件到指定目录：

```powershell
moon install ./cmd/moon-firmware --bin ./artifacts/install
./artifacts/install/moon-firmware.exe --version
```

## CLI

所有命令支持 `--help`。数值接受十进制或 `0x` 十六进制；`--start`、`--end` 均为包含端点。格式优先由内容识别，扩展名只作提示。

```powershell
moon run cmd/moon-firmware -- verify tests/fixtures/basic.hex
moon run cmd/moon-firmware -- convert tests/fixtures/basic.hex artifacts/basic.srec --force
moon run cmd/moon-firmware -- convert artifacts/basic.srec artifacts/basic-round.hex --force
moon run cmd/moon-firmware -- convert tests/fixtures/basic.hex artifacts/basic.bin --force
moon run cmd/moon-firmware -- merge tests/fixtures/basic.hex tests/fixtures/extended_linear.hex -o artifacts/merged.hex --force
moon run cmd/moon-firmware -- extract tests/fixtures/extended_linear.hex --start 0x08000001 --end 0x08000002 -o artifacts/extracted.hex --force
moon run cmd/moon-firmware -- diff tests/fixtures/basic.hex tests/fixtures/changed.hex
```

转换到有 gap 的 BIN 时提供 `--fill 0xFF`，也可用 `--start`、`--end` 明确输出窗口；默认最大 BIN 为 16 MiB，硬上限为 64 MiB。写入已有路径必须显式给出 `--force`。diff 相同返回 0，有变化返回 1，使用错误返回 2。

实际 diff 输出：

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

`inspect --json` 和 `diff --json` 提供稳定的机器可读输出。`merge` 默认 `--overlap reject`，也可选择 `identical` 或 `overwrite`；入口冲突使用 `--entry-policy reject|first|last`。

## Library API

模块根包 `SongYZZZ/moon-firmware` 提供高层 API：

- `parse_intel_hex`、`write_intel_hex`、`parse_srecord`、`write_srecord`
- `load_firmware`、`detect_format`、`convert`
- `FirmwareImage`、`MemoryMap`、`MemorySegment`、`AddressRange`
- `merge_images`、`extract_range`、`diff_images`、`inspect_image`
- `validate_layout`、`plan_flash_pages`
- `checksum_image`、`find_pattern`、`find_ascii_strings`、`inspect_cortex_m_vectors`

协议级 `Record`、checksum 与 writer options 位于 `SongYZZZ/moon-firmware/ihex` 和 `SongYZZZ/moon-firmware/srec`。可运行示例：

```powershell
moon run examples/inspect
moon run examples/convert
```

示例使用根包 API，第二个示例实际执行 BIN → SREC → `FirmwareImage`，并检查内存和入口点语义相等。

## 格式支持

| 格式 | 记录 | 解析 | 生成 | 结构校验 |
|---|---|---:|---:|---:|
| Intel HEX | 00 Data | ✓ | ✓ | 长度、地址、checksum、overlap |
| Intel HEX | 01 EOF | ✓ | ✓ | 唯一性、位置、缺失 |
| Intel HEX | 02 Extended Segment | ✓ | 解析 | 长度、HEX86 语义 |
| Intel HEX | 03 Start Segment | ✓ | ✓ | CS:IP 入口 |
| Intel HEX | 04 Extended Linear | ✓ | ✓ | 64 KiB 边界 |
| Intel HEX | 05 Start Linear | ✓ | ✓ | 32-bit 入口 |
| S-Record | S0、S1、S2、S3 | ✓ | ✓ | 类型、地址宽度、count、checksum |
| S-Record | S5、S6 | ✓ | ✓ | data record 总数 |
| S-Record | S7、S8、S9 | ✓ | ✓ | 与数据宽度匹配、入口 |

Intel HEX writer 统一输出 Extended Linear Address；Type 02 仍能正确解析，但不会作为 writer 的地址策略输出。S4 和未知记录类型明确报错。完整严格／宽松规则见 [FORMAT_SUPPORT.md](docs/FORMAT_SUPPORT.md)。

## 错误诊断

库统一抛出带 `ErrorCode` 的 `FirmwareError(Diagnostic)`，包括格式、行、列、记录类型、地址范围和消息。典型 CLI 错误：

```text
line 1, column 18: firmware.hex: checksum mismatch
```

用户输入导致的格式、范围、冲突和资源错误均返回诊断，不依靠 panic。checksum 在 Strict 和 Permissive 中都必须正确。

## 测试与质量门

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

当前本地结果：231 个测试入口全部通过；其中包含数百组固定 seed 生成用例。覆盖工具报告 1,417／1,864 个可插桩点命中（76.02%）。性能数字与环境见 [BENCHMARKS.md](docs/BENCHMARKS.md)。CI 在 Ubuntu native 环境运行 format、check、test 和 build。

## 项目结构

```text
model/       稀疏地址模型、诊断与策略
codec/       安全的公共十六进制与文本行基础设施
ihex/        Intel HEX record、parser、writer、checksum
srec/        Motorola S-Record codec
firmware/    检测、转换、merge、extract、diff、inspect
validation/  目标布局与 flash page plan
analysis/    镜像 checksum、搜索、word 与 Cortex-M 分析
cli/         参数、文件 IO、命令执行
cmd/         moon-firmware 原生入口
examples/    可运行 Library API 示例
benchmarks/  官方 MoonBit benchmark
tests/       原创最小 fixture
docs/        设计、格式、测试、参考与实测记录
```

## Mooncakes 与发布状态

`moon.mod` 中的模块名已由当前 `moon package` 接受为 `SongYZZZ/moon-firmware`，版本、仓库、许可证、描述、关键词和 README 均已填写。0.1.0 包已能生成。当前机器的 Mooncakes 身份是 `hjn0123`，因此没有以错误身份执行 `moon publish`；仓库所有者登录正确 Mooncakes 账号后即可发布。

## 兼容性与限制

- CLI 依赖 `moonbitlang/async` 与 `moonbitlang/x` 的原生文件系统 API，因此 0.1.0 声明 native-only；纯解析／模型代码没有绑定 OS API。
- SREC parser 当前处理单个记录块；不接受 S4。writer 没有入口点时按格式需要输出地址 0 的终止记录并产生 warning。
- BIN 不保存入口、header 或 record provenance；转换时会产生相应 warning。
- 当前仓库 fixture 均根据公开格式资料原创。尚未记录第三方工具的交叉兼容实测，因此不声称“100% compatible”。
- 文件写入采用同目录临时文件、`sync` 与 rename；未提供目录 `fsync` 的断电事务保证，也不检测同长度并发改写。

路线图包括：外部工具交叉兼容矩阵、多 block S-Record、可选 target profile 文件、流式超大文件输入，以及在 MoonBit 多后端 IO 成熟后拆分可移植 CLI。当前限制和明确不支持项以 [FORMAT_SUPPORT.md](docs/FORMAT_SUPPORT.md) 为准。

## 参与开发

请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。实现依据公开格式规范独立编写，没有复制其他语言库代码；参考资料和依赖许可证见 [REFERENCES.md](docs/REFERENCES.md)。变更记录见 [CHANGELOG.md](CHANGELOG.md)。
