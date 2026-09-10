# 2026 MoonBit 九月黑客松报名申请书

| 项目 | 内容 |
|---|---|
| 名称 | MoonFirmware：面向 Cortex-M 发布门禁的固件布局验证与烧录计划工具 |
| 参赛者 | 宋永振（GitHub：SongYZZZ） |
| 仓库 | <https://github.com/SongYZZZ/moon-firmware> |
| 技术与许可 | MoonBit，Apache-2.0，版本 0.1.0 |

## 项目与应用场景

MoonFirmware 是纯 MoonBit Library 与原生 CLI。Intel HEX、Motorola S-Record 和 BIN 编解码是输入层；项目的主要目标是把编译产物变成**可验证的 MCU 发布对象**，在烧录前检查地址、入口、目标内存和实际触及的 Flash 页。

具体场景一是 Cortex-M 固件发布门禁。以 Flash `0x08000000..0x0800FFFF`、RAM `0x20000000..0x2000FFFF`、1 KiB 页为例，`gate` 会检查所有 payload 是否位于 Flash、向量表是否完整、初始栈指针是否落在 RAM、复位向量是否设置 Thumb 位并指向已映射代码，再输出只包含触及页的烧录清单。仓库中的 `cortex_m_release.hex` 可直接运行，结果为 1 个烧录页、9 字节 payload、1015 字节擦除填充。

具体场景二是工厂镜像装配。先用默认拒绝冲突的 `merge` 合并 bootloader 与 application，再以 application 的向量表地址运行 `gate`；示例会得到两个相距 32 KiB 的实际烧录页，不会把中间空洞扩展成巨大数组或 BIN。具体场景三是 OTA／版本评审：`diff` 按 MCU 地址报告新增、删除和变更范围，示例能够定位 `0x08008008` 的单字节变更；需要交付旧烧录器时，再确定性转换为 HEX／SREC／有界 BIN。

## 与既有项目的边界

收到初审意见后，我核查了组委会提到的项目，其当前公开仓库为 [`Zzqy-yi/moonbit-firmware-image`](https://github.com/Zzqy-yi/moonbit-firmware-image)。双方确有 Intel HEX／S-Record、稀疏镜像、合并、截取和比较等共同基础，申报材料不回避这部分重叠。对方公开版本还包含 patch、batch、CRC manifest、layout audit 和 evidence report，这些不是 MoonFirmware 的差异化主张。

MoonFirmware 的扩展边界是端到端的本地发布工作流：可安装的 `moon-firmware` 原生程序、内容识别与 BIN 双向转换、真实文件读写及安全替换、结构化诊断、Cortex-M 向量语义与 Flash／RAM 合同联合校验、受限的整页烧录计划，以及可用于 CI 的退出码。对方 README 将 0.1.0 边界明确为调用者提供文本／字节数组且不执行文件系统和设备 I/O；因此两者可形成“可嵌入格式库”与“面向发布门禁的命令行工具链”的互补。完整逐项说明见 [`PRIOR_ART_AND_BOUNDARY.md`](PRIOR_ART_AND_BOUNDARY.md)。本项目依据公开格式资料独立实现，未复制对方源码。

## 当前完成度

Intel HEX 00～05、S-Record S0／S1／S2／S3／S5／S6／S7／S8／S9、独立 checksum、稀疏 `MemoryMap`、三种 overlap 策略、转换、merge、extract、diff、inspect、verify 和 `gate` 均已实现。全部核心逻辑为 MoonBit；测试、固定 seed 生成用例、原创 fixture、双语文档、CI 和 Apache-2.0 许可证已提交。`moon fmt --check`、`moon check`、`moon test`、`moon info`、`moon build` 和 `moon package` 均作为发布质量门实际执行。

参赛者：宋永振　　更新日期：2026-09-10
