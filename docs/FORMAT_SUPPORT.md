# 格式支持与兼容性

## Intel HEX

| Type | 含义 | Parser | Writer | 说明 |
|---:|---|---:|---:|---|
| 00 | Data | 支持 | 支持 | 结合当前 segment／linear base；校验 32-bit 边界和 overlap |
| 01 | End Of File | 支持 | 支持 | 地址 `0000`、data length 0；writer 唯一且最后输出 |
| 02 | Extended Segment Address | 支持 | 不选择 | 长度 2，base=`value << 4`，HEX86 offset 可回绕 |
| 03 | Start Segment Address | 支持 | 支持 | 长度 4，保存 CS:IP，不当作 data |
| 04 | Extended Linear Address | 支持 | 支持 | 长度 2，base=`value << 16` |
| 05 | Start Linear Address | 支持 | 支持 | 长度 4，保存 32-bit execution address |

每条记录必须以 `:` 开始，byte count 必须与文本长度一致。checksum 覆盖 count、地址高低字节、type 和 data；所有相关字节加 checksum 的低 8 位必须为 0。单行最大长度、record 数、payload、文本与 warning 数都有上限。

Intel writer 默认 16 data bytes／record，可配置 1～255。它使用 Extended Linear Address canonical 输出，并在 64 KiB 边界前拆分记录；相同 image 和 options 产生相同文本。

## Motorola S-Record

| Type | 含义 | Parser | Writer | 约束 |
|---|---|---:|---:|---|
| S0 | Header | 支持 | 支持 | 16-bit 地址且地址为 0，至多一次且位于开头 |
| S1 | Data | 支持 | 支持 | 16-bit 地址 |
| S2 | Data | 支持 | 支持 | 24-bit 地址 |
| S3 | Data | 支持 | 支持 | 32-bit 地址 |
| S5 | Count | 支持 | 支持 | 16-bit data record count |
| S6 | Count | 支持 | 支持 | 24-bit data record count |
| S7 | Termination | 支持 | 支持 | 32-bit entry，与 S3 匹配 |
| S8 | Termination | 支持 | 支持 | 24-bit entry，与 S2 匹配 |
| S9 | Termination | 支持 | 支持 | 16-bit entry，与 S1 匹配 |
| S4 | Reserved | 拒绝 | 不生成 | 清晰的 `UnsupportedRecord` 诊断 |

count 表示 address、data 和 checksum 的总字节数。checksum 是这些字节总和的 ones' complement；它与 Intel HEX checksum 是独立实现和独立测试。Strict 模式要求一个 block 中 S1/S2/S3 data width 一致，count 位于 data 后，termination 与 data width 匹配，termination 后无记录。

writer 自动选择容纳 payload 最高地址和 entry 的最小宽度，也可显式要求 16／24／32 bit。data record 数不超过 65,535 时生成 S5，否则生成 S6；超过 S6 容量时报错。没有 entry 的 image 会用地址 0 生成格式所需 termination，并返回 warning。CS:IP 只能在显式 `flatten_segment_entry` 时转换为线性地址。

## Strict 与 Permissive

| 情况 | Strict | Permissive |
|---|---:|---:|
| LF／CRLF | 接受 | 接受 |
| 大小写 hex digit | 接受 | 接受 |
| UTF-8 BOM（首行） | 拒绝 | warning 后接受 |
| ASCII 外围空白 | 拒绝 | warning 后接受 |
| 空行、`#`／`;` 整行注释 | 拒绝 | warning 后跳过 |
| 缺少 EOF／termination | 拒绝 | 非空文档 warning 后接受 |
| 重复 Intel EOF | 拒绝 | warning 后接受 |
| 相同重复 entry | 拒绝 | warning 后接受 |
| S1/S2/S3 混合 | 拒绝 | warning 后接受，并要求最大宽度对应 termination |
| checksum corruption | 拒绝 | 拒绝 |
| terminator 后有效记录 | 拒绝 | 拒绝 |
| SREC count mismatch | 拒绝 | 拒绝 |
| 地址溢出／非法 digit | 拒绝 | 拒绝 |

Permissive 不是数据修复模式，不会猜 checksum、忽略截断 data 或接受未知 record type。

## 格式检测

检测跳过有限的前导 ASCII whitespace、BOM 与注释，然后按内容签名识别 `:` 或 `S` 加十进制 type。不可打印或非 ASCII bytes 识别为 RawBinary；可打印但没有可靠签名的内容为 Unknown。扩展名只在内容无法决定时作 hint。显式 hint 不能覆盖明确且不同的内容签名。

## 转换语义

| 输入 | HEX | SREC | BIN |
|---|---:|---:|---:|
| HEX | 支持、canonical | 支持 | 支持，gap 需 fill |
| SREC | 支持 | 支持、canonical | 支持，gap 需 fill |
| BIN | 需要 base address | 需要 base address | 支持 |

转换比较的是 `FirmwareImage` 的地址与 entry 语义，不要求输出文本与原文的 record 切分、大小写或扩展地址选择相同。S0 header 转为 HEX 会丢失并 warning；BIN 会丢失 entry、header 和 record provenance。

## 实测范围

仓库 fixture 均为本项目根据公开格式说明人工制作，包括基本与扩展 HEX、16／24／32-bit SREC、稀疏镜像、Cortex-M 发布镜像和 checksum 正确但目标语义错误的对照文件。它们经过本项目 parser、writer、round-trip、CLI 文件 IO 和 checksum 测试。

2026-09-12 使用 IntelHex 2.3.0 和 bincopy 20.1.1 完成外部兼容实验。MoonFirmware 生成的 HEX 可由 IntelHex 读取，生成的 HEX／SREC 可由 bincopy 读取；IntelHex 重写后的文件与原镜像地址、数据和入口一致。bincopy 20.1.1 的 HEX→SREC 输出没有 termination，MoonFirmware Strict 按规范拒绝，Permissive 给出 warning 后接受且地址数据一致。工具版本、命令和目标语义对照结果见 `COMPATIBILITY_REPORT.md`。这些结果不构成对所有供应商方言的完全兼容声明。

## 已知限制

- 单次 SREC 输入只处理一个 block，不连接多个 termination 分隔的 block。
- Intel writer 不输出 Type 02；parse 后的 Type 02 数据会以 Type 04 canonical 化。
- 不支持厂商私有 record type 或 S4。
- 文本一次载入内存；输入上限为 256 MiB，payload 上限为 64 MiB。
- CLI 0.1.0 为 native-only。
