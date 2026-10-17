# MoonFirmware

MoonFirmware 是基于既有镜像库构建的 NOR Flash 更新安全规划工具库与原生 CLI。0.2.0 的核心输入是旧设备快照、稀疏更新镜像和目标合同，输出经过离线模拟的擦除／编程／校验计划，重点处理未修改字节保留、非等长扇区、保护区连带擦除及旧基线不一致。

作者：宋永振（[SongYZZZ](https://github.com/SongYZZZ)）　许可证：Apache-2.0　源码版本：0.2.0

[English README](README_EN.md) · [十月报名申请书](docs/HACKATHON_APPLICATION.md) · [复审补充说明](docs/RESUBMISSION_RESPONSE.md) · [更新案例与验收](docs/UPDATE_PLAN_CASES.md) · [既有项目边界](docs/PRIOR_ART_AND_BOUNDARY.md)

## 0.2.0：复用镜像库后的新增贡献

更新路径实际依赖 [`Zzqy-yi/firmware-image-toolkit@0.1.0`](https://github.com/Zzqy-yi/moonbit-firmware-image)（Apache-2.0），调用其 HEX／SREC parser、稀疏镜像和 CRC。新入口不使用本仓库旧解析器；原有格式／合并／转换 API 保留兼容，不作为本次参赛新增贡献。

新增 `SongYZZZ/moon-firmware/update` 提供：

- 版本化 JSON 目标合同：非等长擦除扇区、编程单元、可写区与保护区。
- 基于旧快照重建受影响扇区，保留更新中未出现的字节；未知旧内容不能假定为 `0xFF`。
- 根据 NOR 0→1 位变化决定是否擦除；仅清位的更新可以免擦除。
- 检查整个擦除扇区及对齐编程单元，拒绝触碰保护区或越出可写范围。
- 在首次模拟写入前检查全部受影响扇区的前置内容，再回放并核对最终字节。
- 输出确定性 JSON 操作清单，含完整前后字节、CRC、操作顺序和统计。

```powershell
moon update
moon run cmd/moon-firmware -- plan-update tests/fixtures/update/baseline.hex tests/fixtures/update/erase-overlay.hex --profile tests/fixtures/update/target.json
moon run examples/update
moon build --release
pwsh -File scripts/review-update.ps1
```

原创 16／64／16 KiB 案例只改动应用扇区 1 字节，验证其余 65,535 字节保留；共享校准区擦除、旧基线过期和缺失旧内容均被拒绝。完整说明见[案例](docs/UPDATE_PLAN_CASES.md)。工具是主机侧通用 NOR 模型，不连接硬件；快照可靠性、具体芯片 ECC／重复编程限制和断电恢复需调用方另行处理。0.2.0 新功能以本仓库源码为准；已发布的 0.1.x 包不包含更新规划器。

## 原有格式与静态检查功能（兼容接口）

HEX 和 SREC 不是普通的十六进制文本：每条记录都带地址、类型、长度和 checksum，镜像还可能分布在相距很远的 flash 区域。MoonFirmware 将记录恢复为 `FirmwareImage`，因此能够发现地址冲突和空洞，并在格式转换时保留真正的地址与入口点语义。

MoonFirmware 不是 Hex Editor。Hex Editor 主要查看和修改文件偏移处的原始字节；MoonFirmware 处理 MCU/Bootloader 工具链中的带地址固件镜像、record validation、checksum、稀疏内存重建、转换、合并、截取和比较。

## 三分钟发布场景

下面的原创 fixture 模拟一个 Cortex-M 应用。命令同时检查 Flash 占用、RAM 栈顶、向量表、Thumb 复位地址与实际烧录页：

```powershell
moon run cmd/moon-firmware -- gate tests/fixtures/cortex_m_release.hex --flash-start 0x08000000 --flash-end 0x0800FFFF --ram-start 0x20000000 --ram-end 0x2000FFFF --page-size 0x400
```

实际结果：

```text
Release gate: passed
Flash: 0x08000000..0x0800FFFF
Vector table: 0x08000000
Initial stack pointer: 0x20010000
Reset handler: 0x08000008
Flash pages: 1
Page size: 1024 bytes
Payload: 9 bytes
Output: 1024 bytes
Erase padding: 1015 bytes
Erase value: 0xFF
0x08000000..0x080003FF: 9 payload bytes
```

bootloader＋application 装配和 OTA 地址差异的完整可运行流程见[应用场景](docs/APPLICATION_SCENARIOS.md)。

## 原有接口支持范围

- Intel HEX：00、01、02、03、04、05，全记录 checksum、HEX86 段地址回绕、跨 64 KiB 线性地址切换、确定性 writer。
- Motorola S-Record：S0、S1、S2、S3、S5、S6、S7、S8、S9，独立 checksum、计数与终止记录校验、地址宽度自动选择。
- 稀疏 `MemoryMap`：内存主要随 payload 增长；排序 segment、相邻合并、gap 查询、切片和有上限的 BIN 展开。
- overlap 策略：`Reject`、`AllowIdentical`、`Overwrite`；默认拒绝任何重叠。
- HEX、SREC、BIN 全向转换；BIN 输入要求 base address，BIN 空洞要求显式 fill。
- 多镜像 merge、范围 extract、地址级 diff、inspect、verify。
- 目标内存布局校验、入口点检查和仅包含已触及页的 flash page plan。
- Cortex-M release gate：联合检查 Flash／RAM 合同、向量表、初始栈、Thumb 复位地址与烧录页。
- 镜像 CRC-32/CRC-16/additive checksum、掩码模式搜索、ASCII 字符串、字节序整数和 Cortex-M 向量表检查。
- Strict 与 Permissive 解析；宽松模式仍拒绝 checksum 损坏。
- 原生 CLI 安全限制：普通文件检查、输入与输出上限、默认拒绝覆盖、同目录排他临时文件、`sync` 后 rename。

## 快速体验

当前最低验证工具链为 MoonBit `moon 0.1.20260920`、`moonc 0.10.14`，CLI 使用 native 后端。源码运行：

```powershell
moon update
moon run cmd/moon-firmware -- inspect tests/fixtures/basic.hex
```

在 MoonBit Library 项目中添加依赖：

```powershell
moon add SongYZZZ/moon-firmware
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
./artifacts/install/moon-firmware.exe inspect tests/fixtures/basic.hex
```

## CLI

所有命令支持 `--help`。数值接受十进制或 `0x` 十六进制；`--start`、`--end` 均为包含端点。格式优先由内容识别，扩展名只作提示。

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
moon run cmd/moon-firmware -- gate tests/fixtures/cortex_m_release.hex --flash-start 0x08000000 --flash-end 0x0800FFFF --ram-start 0x20000000 --ram-end 0x2000FFFF --page-size 0x400
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
- `validate_cortex_m_release`
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

当前本地结果：286 个测试入口全部通过，新增更新规划测试包含 64 组生成用例、3,072 次最终字节断言；另有 7 项真实更新 CLI 案例。CI 在 Ubuntu native 环境执行标准质量门、原有 release gate 和更新案例脚本。0.1.x 的历史覆盖率及性能数字见旧报告，不代表 0.2.0 的覆盖率或性能结论。

## 项目结构

```text
model/       稀疏地址模型、诊断与策略
codec/       安全的公共十六进制与文本行基础设施
ihex/        Intel HEX record、parser、writer、checksum
srec/        Motorola S-Record codec
firmware/    检测、转换、merge、extract、diff、inspect
validation/  目标布局与 flash page plan
update/      上游镜像库之上的 NOR 更新安全规划、配置与模拟
analysis/    镜像 checksum、搜索、word 与 Cortex-M 分析
cli/         参数、文件 IO、命令执行
cmd/         moon-firmware 原生入口
examples/    可运行 Library API 示例
benchmarks/  官方 MoonBit benchmark
tests/       原创最小 fixture
docs/        设计、格式、测试、参考与实测记录
```

## Mooncakes 包元数据

`moon.mod` 中已填写模块名、版本、仓库、许可证、描述、关键词和 README。已发布版本为 0.1.x；0.2.0 更新规划器目前通过仓库源码使用，尚未发布。`moon add SongYZZZ/moon-firmware` 获取的是已发布版本，见 [Mooncakes 包页面](https://mooncakes.io/docs/SongYZZZ/moon-firmware)。

## 兼容性与限制

- CLI 依赖 `moonbitlang/async` 与 `moonbitlang/x` 的原生文件系统 API，因此当前发布声明 native-only；纯解析／模型代码没有绑定 OS API。
- SREC parser 当前处理单个记录块；不接受 S4。writer 没有入口点时按格式需要输出地址 0 的终止记录并产生 warning。
- BIN 不保存入口、header 或 record provenance；转换时会产生相应 warning。
- 当前仓库 fixture 均根据公开格式资料原创。IntelHex 2.3.0 与 bincopy 20.1.1 的实测结果见 [COMPATIBILITY_REPORT.md](docs/COMPATIBILITY_REPORT.md)；有限样例通过不代表兼容全部供应商方言。
- 文件写入采用同目录临时文件、`sync` 与 rename；未提供目录 `fsync` 的断电事务保证，也不检测同长度并发改写。

路线图包括：使用 SRecord／objcopy 扩展兼容矩阵、多 block S-Record、旧 gate 命令的 target profile 文件、流式超大文件输入，以及在 MoonBit 多后端 IO 成熟后拆分可移植 CLI。当前限制和明确不支持项以 [FORMAT_SUPPORT.md](docs/FORMAT_SUPPORT.md) 为准。

## 参与开发

请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。旧格式实现依据公开规范编写；0.2.0 更新路径实际复用上游镜像库。来源和许可证见 [REFERENCES.md](docs/REFERENCES.md) 与 [NOTICE](NOTICE)。变更记录见 [CHANGELOG.md](CHANGELOG.md)。
