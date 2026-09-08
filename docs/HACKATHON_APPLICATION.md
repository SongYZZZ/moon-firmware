# 2026 MoonBit 九月黑客松报名申请书

## 一、项目基本信息

| 项目 | 内容 |
|---|---|
| 项目名称 | MoonFirmware |
| 中文名称 | MoonFirmware：面向嵌入式固件的 Intel HEX / Motorola S-Record 解析、校验与转换工具库 |
| 参赛者 | 宋永振 |
| GitHub 用户 | SongYZZZ |
| GitHub 仓库 | <https://github.com/SongYZZZ/moon-firmware> |
| 参赛形式 | 个人原创开源项目 |
| 核心开发语言 | MoonBit |
| 开源许可证 | Apache-2.0 |
| 当前版本 | 0.1.0 |
| Mooncakes 模块名 | `SongYZZZ/moon-firmware` |
| 项目类型 | 基础软件、协议解析、嵌入式开发工具 |

报名平台要求的手机号、电子邮箱、身份证明等个人信息，应由参赛者在平台账户中直接填写，不写入公开 GitHub 仓库。

## 二、项目简介

MoonFirmware 是一个使用 MoonBit 独立实现的固件镜像工具库与原生命令行程序。项目支持 Intel HEX 和 Motorola S-Record 的解析、checksum 校验和确定性生成，并以稀疏地址模型统一表示固件内容。在此基础上，它能够执行 HEX、SREC、BIN 格式转换、固件合并、地址范围截取、地址级差异比较、目标内存布局验证和 flash page 规划。

项目定位是 firmware image toolkit，而不是 Hex Editor。Hex Editor 主要查看和修改文件偏移中的原始字节；MoonFirmware 处理的是 MCU、Bootloader 和烧录工具链中的地址语义、record type、entry point、checksum、空洞和地址冲突。

## 三、项目背景与问题

嵌入式固件常以 Intel HEX 或 Motorola S-Record 交付。这两类文件不是普通的十六进制文本：记录包含地址、长度、类型和 checksum，同一个镜像可以横跨多个不连续 flash 区域，并携带执行入口信息。

实际工具链需要解决以下问题：

- 判断文件是否被截断、篡改或产生 checksum 错误；
- 将扩展段地址、扩展线性地址和不同宽度的 S-Record 地址恢复为绝对地址；
- 发现两个固件写入同一地址时的数据冲突；
- 在 Bootloader、配置区和应用程序分离时保留稀疏地址；
- 在 HEX、SREC 和 BIN 之间转换，同时显式处理 BIN 的 base address 与 gap fill；
- 比较两个构建产物在地址空间中的真实变化；
- 在烧录前验证固件是否位于目标 MCU 允许的内存区域。

若直接建立长度等于最高地址的数组，一个仅有少量 payload、但地址接近 `0xFFFFFFFF` 的输入会导致巨量内存申请。MoonFirmware 因此使用排序且规范化的稀疏 segment，而不是以最大地址决定数组大小。

## 四、核心功能

### 1. Intel HEX

完整支持标准记录类型：

- Type 00：Data Record；
- Type 01：End Of File；
- Type 02：Extended Segment Address；
- Type 03：Start Segment Address；
- Type 04：Extended Linear Address；
- Type 05：Start Linear Address。

实现了独立的 two's complement checksum、HEX86 segment offset 回绕、32-bit 地址溢出检查、EOF 结构校验、跨 64 KiB 边界 writer 拆分和确定性输出。

### 2. Motorola S-Record

支持 S0、S1、S2、S3、S5、S6、S7、S8、S9，分别处理 header、16／24／32-bit data、record count 和 termination／entry。S-Record 使用独立的 ones' complement checksum 实现，没有复用 Intel HEX 算法。保留类型 S4 和未知类型会产生明确错误。

### 3. 统一稀疏固件模型

核心类型包括 `FirmwareImage`、`MemoryMap`、`MemorySegment`、`AddressRange`、`EntryPoint`、`Metadata` 和 `Diagnostic`。连续数据自动合并，地址 gap 只保存端点，存储开销主要取决于真实 payload 与 segment 数量。

插入和 merge 支持三种 overlap 策略：

- `Reject`：任何重叠都失败，作为安全默认值；
- `AllowIdentical`：只接受完全相同的重叠字节；
- `Overwrite`：用新数据覆盖旧数据。

### 4. 固件操作

- HEX、SREC、BIN 全向转换；
- 多镜像 merge；
- 按包含端点的地址范围 extract；
- only-left、only-right、changed range 和 identical byte count 的地址级 diff；
- format、地址范围、payload、segment、gap、entry、checksum 和 record count 的 inspect；
- 目标 memory region、entry、alignment、payload／span budget 校验；
- 只生成已触及完整页的 bounded flash page plan。

### 5. 镜像分析

项目还提供 CRC-32、CRC-16、8／16／32-bit additive checksum、带 bit mask 的 pattern search、ASCII 字符串发现、大小端整数读写、word reference search 和 Cortex-M vector table 检查。这些能力直接服务于固件诊断与 Bootloader 集成，不是为增加代码量添加的无关功能。

## 五、技术架构

```text
输入文件
   │
   ▼
内容格式识别 ──► Intel HEX parser
   │             Motorola S-Record parser
   │             Raw BIN loader
   ▼
FirmwareImage + sparse MemoryMap
   │
   ├── convert / merge / extract / diff / inspect
   ├── target layout validation / flash page plan
   └── checksum / pattern / word / Cortex-M analysis
   │
   ▼
Intel HEX writer / S-Record writer / bounded BIN output
```

包职责如下：

- `codec`：有界行扫描、ASCII hex 编解码和输出容量检查；
- `ihex`、`srec`：相互隔离的协议规则与 checksum；
- `model`：不依赖文件系统的统一地址模型；
- `firmware`：跨格式操作；
- `validation`、`analysis`：烧录前校验与镜像分析；
- `cli`：参数、文件 IO、退出码和结果展示；
- `cmd/moon-firmware`：native 可执行入口。

Library API 与 CLI 分离，其他 MoonBit 项目可以直接 import 根包或协议子包。

## 六、技术创新与差异化

1. **MoonBit 基础软件实践**：核心 parser、writer、memory model、转换和 diff 均用 MoonBit 实现，展示 MoonBit 在协议解析与嵌入式工具链领域的能力。
2. **统一地址语义**：不是停留在字符串 record 层，而是把 Intel HEX 的 segment／linear 地址和 SREC 不同宽度地址恢复为统一的绝对地址空间。
3. **真正的稀疏模型**：高地址不会触发按最大地址分配内存，4 GiB 地址跨度的 benchmark 只保存实际 payload。
4. **保守的数据安全策略**：默认拒绝 overlap 和已有输出文件；BIN gap、segment entry flatten、overwrite 与 force 都必须显式选择。
5. **可复现的正确性验证**：除协议 fixture 外，包含固定 seed 的 round-trip、dense oracle、diff oracle、malformed input 和 checksum bit corruption 测试。
6. **面向烧录流程**：目标内存布局与完整 flash page 计划使项目能够服务 MCU 工具链，而不只是格式转换。

## 七、原创性说明

MoonFirmware 是参赛者宋永振原创的 MoonBit 开源项目。实现依据公开的 Intel HEX、Motorola S-Record 和 MoonBit 官方资料独立完成，没有复制其他语言库代码，没有将 Python、Rust、Go 或 JavaScript 实现包装成 MoonBit 项目，也没有改名复用现有 MoonBit 项目。

仓库中的九个测试 fixture 均依据公开格式说明人工编写，不包含来源不明的第三方固件。参考资料、用途和依赖许可证记录在 `docs/REFERENCES.md`。

## 八、完成度与质量数据

截至 0.1.0：

| 项目 | 实际结果 |
|---|---:|
| MoonBit 测试入口 | 231 |
| 通过 | 231 |
| 失败 | 0 |
| Coverage 插桩点 | 1,417／1,864，76.02% |
| Core MoonBit 物理行 | 4,666 |
| Core MoonBit 有效行 | 4,063 |
| 全部 MoonBit 物理行 | 7,682 |
| 固定 seed HEX／SREC round-trip | 512 组 |
| Git commits | 15 |

有效代码统计排除空行、纯注释、测试、benchmark、example、`.mbti`、构建产物、依赖缓存和自动生成文件。

本地以下质量门全部通过：

```powershell
moon fmt --check
moon check
moon test
moon info
moon build
moon package
```

GitHub Actions 最终运行成功：<https://github.com/SongYZZZ/moon-firmware/actions/runs/34193116836>。

## 九、性能实测

使用 MoonBit 官方 benchmark 机制和 native release backend 实测：

| 场景 | 平均时间 |
|---|---:|
| HEX parse 100 KiB | 5.74 ms |
| SREC parse 100 KiB | 6.58 ms |
| HEX parse 1 MiB | 60.71 ms |
| SREC parse 1 MiB | 74.39 ms |
| 1024 segments、接近 4 GiB 地址跨度的 HEX parse | 6.71 ms |
| 102,400 条 one-byte HEX record parse | 59.03 ms |

数据来自 2026-09-08 的真实运行，不作为跨机器性能保证。完整环境、方差和区间见 `docs/BENCHMARKS.md`。

## 十、演示流程

评委可以在仓库根目录执行：

```powershell
moon update
moon run cmd/moon-firmware -- inspect tests/fixtures/basic.hex
moon run cmd/moon-firmware -- verify tests/fixtures/basic.hex
moon run cmd/moon-firmware -- convert tests/fixtures/basic.hex artifacts/basic.srec --force
moon run cmd/moon-firmware -- diff tests/fixtures/basic.hex tests/fixtures/changed.hex
```

`inspect` 会展示格式、payload、segment、地址范围、gap、entry、checksum 和 record count。`diff` 会输出真实变化地址范围，而不是比较文本行。

安装可执行文件：

```powershell
moon install ./cmd/moon-firmware --bin ./artifacts/install
./artifacts/install/moon-firmware.exe --version
```

上述命令均已在项目验收中实际执行。

## 十一、安全与可靠性

- 文本、行、record、payload、warning、segment 和输出均有上限；
- 所有地址计算检查 32-bit overflow；
- BIN 输出默认限制 16 MiB，硬上限 64 MiB；
- parser 对 checksum corruption 在 Strict 和 Permissive 中都失败；
- overlap 插入先校验后修改，错误不会留下部分写入；
- CLI 只接受普通输入文件；
- 输出使用同目录排他 staging 文件、`sync`、关闭和 rename；
- 用户输入错误返回带行、列、记录类型和地址的结构化诊断。

项目不把 record checksum 或 CRC 描述为密码学签名。安全启动仍需要设备支持的签名与可信密钥流程。

## 十二、开源与维护计划

项目使用 Apache-2.0，提供中英文 README、设计文档、格式支持矩阵、测试说明、安全策略、贡献指南、benchmark 和 changelog。后续计划包括：

- 使用 `srec_cat`、GNU／LLVM `objcopy` 建立有工具版本和命令记录的交叉兼容矩阵；
- 支持多 block S-Record；
- 提供可复用的 MCU target profile；
- 为超大输入增加流式 parser；
- MoonBit 多后端 IO 稳定后扩展 CLI backend。

当前未完成的 roadmap 不会在 README 中宣称为已实现功能。

## 十三、已知限制与发布状态

- CLI 0.1.0 使用 `moonbitlang/async` 和 `moonbitlang/x` 的原生文件系统能力，声明为 native-only；
- SREC 当前处理单个 block，不支持 S4 和厂商私有 record；
- Intel writer canonicalize 为 Type 04，不生成 Type 02；
- 尚未完成第三方工具交叉兼容实测，因此不声称兼容所有供应商方言。

GitHub 仓库已公开并推送到 `SongYZZZ/moon-firmware`。`moon package` 已生成 0.1.0 包并验证模块名。当前机器的 Mooncakes 身份为 `hjn0123`，不是 `SongYZZZ`，因此没有使用错误身份执行 `moon publish`；参赛者使用正确 Mooncakes 身份登录后即可发布。

## 十四、参赛声明

本人宋永振确认：

1. MoonFirmware 为本人原创 MoonBit 开源项目；
2. 项目核心功能由 MoonBit 实现；
3. 项目没有复制来源不明或许可证不兼容的第三方源码；
4. 本申请书中的测试、coverage、benchmark、Git、CI 和发布状态均来自实际执行结果；
5. 项目以 Apache-2.0 许可证公开，愿意接受社区审查与贡献。

参赛者：宋永振

项目地址：<https://github.com/SongYZZZ/moon-firmware>

申请日期：2026-09-08
