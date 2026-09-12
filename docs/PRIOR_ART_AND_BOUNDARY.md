# 既有项目核查与互补边界

本文记录 MoonFirmware 的既有项目调研、功能边界与取舍。核查日期为 2026-09-12，比较对象为 [`Zzqy-yi/moonbit-firmware-image`](https://github.com/Zzqy-yi/moonbit-firmware-image)。该仓库创建于 2026-08-10，默认分支为 `master`；本页只陈述核查日公开 README、目录与接口能够支持的结论。

## 共同基础

两个项目都以 MoonBit 独立处理 Intel HEX 和 Motorola S-Record，并建立稀疏的带地址固件镜像。双方公开功能都包括 checksum／结构校验、确定性编码、overlap 策略、格式转换、合并、范围操作、比较和目标内存布局。因此，MoonFirmware 不再把这些共同能力单独作为参赛创新点，也不以“对方完成度较低”作为项目成立的理由。

## 公开能力对照

| 范围 | `Zzqy-yi/moonbit-firmware-image` | MoonFirmware |
|---|---|---|
| HEX／SREC codec 与稀疏镜像 | 已公开实现 | 已公开实现 |
| 合并、截取、比较、布局 | 已公开实现 | 已公开实现 |
| 补丁、batch、evidence report | 已公开实现 | 不作为 0.1.0 范围 |
| 原始 BIN 双向转换与安全展开上限 | 公开 README 未列出 | 已实现 |
| 可安装的最终用户 CLI | 公开仓库提供 Library 示例 | `inspect`、`verify`、`convert`、`merge`、`extract`、`diff`、`gate` |
| 文件系统工作流 | README 明确排除文件系统 I/O | 普通文件检查、大小上限、默认拒绝覆盖、同目录临时文件、同步后替换 |
| Cortex-M 发布语义 | 公开 README 与源文件清单未列出 | 栈指针、Thumb 位、复位处理器映射、Flash／RAM 目标合同 |
| 烧录页计划 | 公开 README 与源文件清单未列出 | 只展开实际触及页，显式擦除值、页数／字节数／地址边界上限 |
| CI 集成结果 | Library 可在 CI 调用 | 稳定文本／JSON、差异或门禁失败返回 1、输入或 I/O 错误返回 2 |

“未列出”仅表示在核查日的公开材料中未找到，不是对未来版本或未公开工作的判断。

## MoonFirmware 的参赛问题

MoonFirmware 0.1.0 将格式 codec 视为必要的读取层，重点解决以下发布问题：

1. 编译生成的 HEX／SREC 是否真的只占用目标 MCU 允许烧录的 Flash；
2. Cortex-M 向量表是否完整，初始栈指针是否落在 RAM，复位向量是否为 Thumb 地址并指向镜像内代码；
3. bootloader、application 和配置镜像合并时是否发生地址冲突；
4. 稀疏镜像实际触及哪些 Flash 页，整页烧录需要多少擦除填充；
5. 新旧版本在 MCU 地址空间中改动了哪些范围，CI 是否应阻止发布；
6. 面向旧烧录器导出 BIN 时，如何避免地址空洞意外产生数 GiB 文件。

这组问题组成一个可以直接放入本地构建与 CI 的发布门禁，而不是单独的记录格式 API。当前 `gate` 命令只生成验证报告和数据计划，不连接调试探针，也不执行擦除或烧录。

## 独立实现与后续边界

MoonFirmware 的提交始于 2026-09-07，晚于比较对象的公开创建日期。本项目没有复制该仓库代码；协议算法依据 `REFERENCES.md` 中列出的公开格式资料实现。

后续版本会继续围绕发布验证扩展，例如可版本化的目标板描述、烧录页 manifest 输出和发布策略组合。不会为了竞争而复刻对方的 patch、batch 或 evidence-report API；若未来功能边界再次接近，将继续在本页记录来源、差异与取舍。
