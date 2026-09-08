# 2026 MoonBit 九月黑客松报名申请书

## 基本信息

| 项目 | 内容 |
|---|---|
| 名称 | MoonFirmware：面向嵌入式固件的 Intel HEX／Motorola S-Record 工具库 |
| 参赛者 | 宋永振（GitHub：SongYZZZ） |
| 仓库 | <https://github.com/SongYZZZ/moon-firmware> |
| 技术与许可 | MoonBit，Apache-2.0，版本 0.1.0 |

## 项目说明

MoonFirmware 是使用 MoonBit 独立实现的固件镜像 Library 与原生 CLI，面向 MCU、Bootloader 和烧录工具链。项目解析、校验并生成 Intel HEX 与 Motorola S-Record，以稀疏地址模型重建固件，并完成 HEX、SREC、BIN 转换、合并、截取、验证、检查和地址级 diff。

它不是 Hex Editor。Hex Editor 关注文件偏移中的原始字节；MoonFirmware 关注 firmware address、record type、checksum、entry point、地址冲突、空洞和目标烧录布局。

## 核心能力与亮点

- 支持 Intel HEX Type 00～05，以及 S-Record S0／S1／S2／S3／S5／S6／S7／S8／S9；两种格式拥有相互独立的 checksum 实现。
- `FirmwareImage` 使用排序、规范化的稀疏 `MemoryMap`，内存随真实 payload 增长，不按最高地址建立巨型数组。
- 提供 `Reject`、`AllowIdentical`、`Overwrite` overlap 策略；BIN gap、数据覆盖和入口转换必须显式选择。
- 提供目标内存区域与入口校验、bounded flash page plan、CRC、掩码搜索、大小端整数和 Cortex-M vector table 分析。
- 核心 parser、writer、memory model、转换、merge 和 diff 全部由 MoonBit 实现；Library API 与 CLI 分离。
- 固定 seed property tests 覆盖稀疏镜像 round-trip、diff oracle、malformed input 和 checksum bit corruption。

## 完成度

| 指标 | 结果 |
|---|---:|
| 测试 | 231 passed，0 failed |
| Coverage | 1,417／1,864，76.02% |
| Core MoonBit | 4,666 物理行，4,063 有效行 |
| 全部 MoonBit | 7,682 物理行 |
| 生成式 round-trip | 512 组固定 seed |
| GitHub Actions | native CI 全部通过 |

`moon fmt --check`、`moon check`、`moon test`、`moon info`、`moon build` 和 `moon package` 均已实际通过。100 KiB、1 MiB、4 GiB 稀疏地址跨度和 102,400 条小记录 benchmark 已真实运行。模块 `SongYZZZ/moon-firmware` 的 0.1.0 包已成功生成。

## 原创与开源声明

MoonFirmware 为宋永振原创项目，依据公开格式规范独立实现，没有复制其他语言库代码，也没有用其他语言替代 MoonBit 核心逻辑。测试 fixture 均为根据规范编写的最小样例。项目以 Apache-2.0 开源，并提供中英文 README、设计、测试、安全、benchmark 和贡献文档。

参赛者：宋永振　　申请日期：2026-09-08
