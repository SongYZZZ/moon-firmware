# MoonFirmware 终审自查（2026-09-29）

本页按九月黑客松提供的验收指南核对仓库现状，列出可复核的实现与运行证据；它是参赛项目的技术自查，不代表组委会的最终判定。仓库和本地代码状态应以本页日期之后的提交及 CI 结果为准。

## 验收清单

| 要求 | 结果与证据 |
|---|---|
| MoonBit 为主要语言，moonc 不低于 0.10.14 | 通过。使用隔离安装的官方 `moonc 0.10.14+7d59c7ec9` 与 `moon 0.1.20260920`，本地严格检查通过；CI 固定同一工具链。实现与测试主体均为 MoonBit。 |
| GitHub 仓库公开、提交清晰 | `SongYZZZ/moon-firmware`，公开仓库，`main` 分支；最新已推送提交 `a72bb09`，CI run `36588414072` 成功。 |
| 结构清晰、核心功能可用 | 通过。协议 codec、稀疏内存模型、Cortex-M 目标合同校验、烧录页计划、转换及 CLI 分层；功能边界见 `FORMAT_SUPPORT.md`、`DESIGN.md` 与 `PRIOR_ART_AND_BOUNDARY.md`。 |
| README 可复现 | 通过。中英文 README 给出安装、library 与 CLI 用法、fixture 示例及限制；示例命令已在当前工具链执行。 |
| CI 覆盖检查、构建、测试 | 通过。配置包含格式检查、严格 `moon check`、严格 `moon test`、`moon info`、`moon build` 和 CLI smoke checks；GitHub Actions run `36588414072` 成功。 |
| 至少一个可运行示例 | 通过。`examples/inspect` 与 `examples/convert` 均已在 MoonBit 0.10.14 下运行。 |
| 核心路径有测试 | 通过。`moon test --deny-warn`：241 passed，0 failed；`moon coverage analyze -- -f summary`：1,537／2,018 points，76.16%。另有 CLI 进程级 smoke checks。 |
| 发布到 Mooncakes.io | 0.1.0 已确认可检索；0.1.1 的发布接口返回 `Server status: 200 OK`，但搜索索引本次仍返回 0.1.0，故新版本可检索性尚待索引刷新确认。 |
| OSI 许可证与来源合规 | 通过。`LICENSE` 与 `moon.mod` 均为 Apache-2.0；`REFERENCES.md` 记录协议、工具链和交叉验证资料。Fixtures 为项目自行编写的最小样例，无第三方固件再分发。 |

## 本地验证记录

使用 `D:\Moonbit\moon-firmware\.tools\moon014\bin\moon.exe`，并将 `MOON_HOME` 指向 `D:\Moonbit`。0.1.1 代码提交 `a72bb09` 的验证结果：

```text
moon fmt --check       passed
moon check --deny-warn passed
moon test --deny-warn  passed: 241, failed: 0
moon info              passed
moon build             passed
moon package --list    passed for 0.1.1; rerun for 0.1.2 docs revision
```

CLI 真实进程检查包括 `inspect`、`verify`、HEX↔SREC、HEX→BIN、BIN→HEX／SREC、`merge`、`extract`、`diff` 与 `gate`，以及错误输入退出码；变化的 `diff` 按接口约定返回 1。两个示例均实际运行。`moon build` 在 Windows 下成功；MSVC 对依赖 C 文件的 `EINVAL` 宏重定义发出非致命警告。

测试覆盖率由当前工具链实际生成：1,537／2,018 instrumented points（76.16%）。统计未覆盖 CLI 进程入口，故额外执行了进程级 smoke checks。外部互操作实验见 `COMPATIBILITY_REPORT.md`；它验证格式读取与地址语义，不等同于目标 MCU 实机烧录验证。

## 项目边界

MoonFirmware 面向固件构建和发布流程，提供格式校验、稀疏地址重建、Cortex-M Flash／RAM 与向量表合同检查，以及受页大小约束的烧录页计划。Intel HEX／S-Record 的基础编解码与既有项目存在功能重叠；本项目的拓展边界和对照说明见 `PRIOR_ART_AND_BOUNDARY.md`。本仓库没有声称验证过具体 MCU 上电运行、调试探针或真实烧录器行为。

本自查不代替比赛资格或组委会验收结论，也不代替参赛者对项目说明内容及报名材料的核实。
