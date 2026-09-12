# 2026 MoonBit 九月黑客松报名申请书

| 项目 | 内容 |
|---|---|
| 名称 | MoonFirmware：面向 Cortex-M 发布门禁的固件布局验证与烧录计划工具 |
| 参赛者 | 宋永振（GitHub：SongYZZZ） |
| 仓库 | <https://github.com/SongYZZZ/moon-firmware> |
| 技术与许可 | MoonBit，Apache-2.0，版本 0.1.0 |

## 项目定位

MoonFirmware 是运行在开发主机和 CI 中的纯 MoonBit Library 与原生 CLI，处理来自 C／C++／Rust／MoonBit 或厂商工具链的 Intel HEX、Motorola S-Record 和 BIN 文件，不要求 MCU 程序本身由 MoonBit 编写。项目将格式记录恢复为稀疏地址空间，并在交付前按目标 MCU 合同判断固件能否发布。它为 MoonBit 生态提供可复用的固件地址模型和原生发布检查组件，后续 MoonBit 烧录器、IDE 插件或 CI 工具可以直接调用 Library API，无需另行包装 Python 工具。

## 核心功能

核心功能是 **Cortex-M 固件发布门禁**。用户明确提供 Flash、RAM、向量表地址、页大小和擦除值；工具检查 payload 是否越出 Flash、向量表是否完整、初始栈指针是否位于 RAM 且满足对齐、复位向量是否设置 Thumb 位并指向镜像内代码，最后生成只包含实际触及页的烧录计划。HEX／SREC／BIN 编解码、稀疏 `MemoryMap`、冲突检测、merge 和地址级 diff 是支撑该门禁的输入与装配能力。

## 验收边界

| 项目 | 0.1.0 验收标准 |
|---|---|
| 输入 | Intel HEX 00～05、S-Record S0／S1／S2／S3／S5／S6／S7／S8／S9、带显式基地址的 BIN |
| 通过条件 | record 与 checksum 正确；数据全部位于 Flash；Cortex-M 栈和复位向量满足目标合同；烧录页数与输出字节数不超过上限 |
| 输出 | 确定性验证报告、目标错误地址、实际触及页清单；CI 中通过返回 0、策略拒绝返回 1、工具错误返回 2 |
| 范围外 | 不解析 ELF／UF2，不维护芯片数据库，不猜测目标参数，不连接 SWD／JTAG／串口／USB，不执行真实擦除或烧录 |

## 应用场景

1. 发布检查：对 Cortex-M 镜像执行 `gate`，阻止 checksum 正确但栈地址、Thumb 位或 Flash 布局错误的文件进入发布目录。
2. 工厂装配：默认拒绝 overlap 地合并 bootloader 与 application，并只规划两个实际触及的 Flash 页区间，不展开中间 32 KiB 空洞。
3. OTA 评审：按 MCU 地址比较新旧固件，示例可定位 `0x08008008` 的单字节变化，避免把 HEX 记录换行或重排误判为固件变化。

## 既有项目与对照实验

[`Zzqy-yi/moonbit-firmware-image`](https://github.com/Zzqy-yi/moonbit-firmware-image) 已实现 HEX／SREC、稀疏镜像、合并、范围操作、比较、patch 和 layout audit。双方的协议与稀疏模型属于共同基础。MoonFirmware 聚焦可安装的本地 CLI、真实文件安全写入、Cortex-M 向量语义与 Flash／RAM 合同联合校验，以及可直接用于 CI 的发布结果；不把对方已有的 patch、batch 和 evidence report 列为差异。

使用 IntelHex 2.3.0 与 bincopy 20.1.1 完成了实际对照。MoonFirmware 生成的 HEX／SREC 均可被对应工具读取，外部工具重写后地址与入口语义一致。一个 checksum 正确但初始栈为 `0x10000004`、复位向量未设置 Thumb 位的 HEX 文件可被 IntelHex、bincopy 和本项目的格式校验读取；`gate` 会报告三项目标错误并返回 1。另一个 13 字节、跨 32 KiB 空洞的装配镜像转为连续 BIN 需要 32,777 字节，而门禁按 1 KiB 页只规划 2,048 字节。完整命令和结果见 [`COMPATIBILITY_REPORT.md`](COMPATIBILITY_REPORT.md)。

## 完成状态

核心实现全部为 MoonBit。239 项测试全部通过，覆盖率为 1,531／2,014（76.02%）；格式检查、编译、测试、API 检查、构建、打包和 GitHub Actions 均通过。项目包含原创 fixture、双语文档和 Apache-2.0 许可证。

参赛者：宋永振　　更新日期：2026-09-12
