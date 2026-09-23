# MoonFirmware 终审自查（2026-09-23）

本页是对仓库 `SongYZZZ/moon-firmware` 的可复核技术自查，不代表组委会已经通过报名或验收。核对依据为 [九月黑客松官网](https://moonbitlang.github.io/Hackathon2026/)、[大赛官网](https://moonbitlang.github.io/OSC2026/)及仓库当前代码。九月官网列出公开仓库、可运行示例、测试、持续提交和一页项目说明；大赛官网还明确列出 CI 与 mooncakes.io 发布。若组委会单独通知有更严格要求，以该通知为准。

## 验收结果与证据

| 检查 | 本次结果 |
|---|---|
| 项目与许可证 | `moon.mod` 为 `SongYZZZ/moon-firmware` 0.1.0，仓库指向同名 GitHub；根目录 `LICENSE` 为 Apache-2.0。仓库公开，默认分支 `main`。 |
| 工具链 | `moon 0.1.20260827`、`moonc 0.10.11+6ff76a5f9`、native。 |
| 质量门 | `moon fmt --check`、`moon check --deny-warn`、`moon test --deny-warn`、`moon info`、`moon build` 均通过；241 passed，0 failed。CI 同步运行严格检查与 API 检查。 |
| 测试覆盖 | `moon coverage analyze -- -f summary` 为 1,537／2,018 instrumented points（76.16%）；CLI 进程与示例入口未被此测试覆盖率统计覆盖，另外执行了真实进程测试。 |
| CLI 正常路径 | `inspect`、`verify`、HEX↔SREC、HEX→BIN、BIN→HEX/SREC、`merge`、`extract`、`diff`、`gate` 共 11 条 README 主流程实际执行；除变化 `diff` 按约定返回 1 外均返回 0。两个 `examples` 均实际运行。 |
| CLI 拒绝路径 | 损坏 checksum 返回 2；目标合同不合格返回 1；错误页大小返回 2。 |
| 打包与发布 | `moon package --list` 生成 `SongYZZZ-moon-firmware-0.1.0.zip`。94 个条目；包清单未包含 `.tools`、本地凭据、构建目录或临时输出。`moon publish` 经提取包再次 `moon check` 后返回 `Server status: 200 OK`；随后 `moon search SongYZZZ/moon-firmware --json` 返回 0.1.0。 |
| 外部兼容性 | 本次重新用 IntelHex 2.3.0 读取本项目 HEX，用 bincopy 20.1.1 读取本项目 SREC；bincopy 生成无终止记录 SREC 后，本项目宽松模式给出 warning，地址级 diff 为 0。完整命令和语义限制见 `COMPATIBILITY_REPORT.md`。 |
| 开发记录 | 检查前已有 21 个连续 Git commit；本次修复和审查另行提交。 |

统计 `git ls-files '*.mbt'`，有效行定义为非空且非纯 `//` 注释行，排除生成文件、缓存、测试和示例：核心 5,094 物理行／4,414 有效行；测试 3,047／2,529；benchmark 87／80；示例 33／31。总计 8,261 物理行／7,054 有效行。行数只作为可复查规模，不代替功能质量判断。

GitHub Actions 已在提交 `82e4b98` 完整通过：[CI run 35882612226](https://github.com/SongYZZZ/moon-firmware/actions/runs/35882612226)。Mooncakes 0.1.0 发布源码对应提交 `0a9ed0b`；之后仅更新 CI 配置与审查、发布文档，MoonBit 实现未变。

## 本次发现并修复

1. `CortexMReleaseOptions` 原先可接受空 RAM 区间。这使无效的目标合同有机会进入向量校验；现在每个 RAM 区间必须非空。
2. 向量地址范围检查原先先执行 `vector_address + 8`，极端 `Int64` 参数会溢出。现在使用 `vector_address > flash.end - 8`，并以最大 `Int64` 参数新增回归测试。
3. CI 原先未以 warning 为错误，也未执行 `moon info`。现在执行 `check --deny-warn`、`test --deny-warn` 和 `info`。
4. 首次推送的严格 CI 在 runner 的最新 MoonBit 上因 `implicit_impl_as_method` 弃用告警失败；该告警在本地 `moonc 0.10.11` 尚未出现。CI 现通过已验证存在的 `hustcer/setup-moonbit@v1.22` 参数固定同版本工具链与 core，待后续升级时再单独迁移弃用 API。

## 能力与差异边界

项目的重点是 Cortex-M 固件发布门禁：读取 HEX／SREC／BIN，重建稀疏地址空间，校验目标 Flash／RAM 合同与向量表，规划触及的烧录页，并为 CI 提供确定的结果和退出码。与已公开的 [`Zzqy-yi/moonbit-firmware-image`](https://github.com/Zzqy-yi/moonbit-firmware-image) 共有格式解析、稀疏镜像、合并、范围和比较能力；差异在于本地文件 CLI、目标向量语义、可检查的 Flash 页计划和有界 BIN 输出。详细核查见 `PRIOR_ART_AND_BOUNDARY.md`，不以对方项目完成度或基础 codec 本身作为差异论证。

对照实验仅证明文件互操作与静态目标合同的实用性。没有连接真实 MCU、调试探针或烧录器；因此不能据此声称固件可在具体硬件上启动，也不能证明真实设备烧录可靠性。页计划中的擦除填充值不保留设备原有页内容，使用者仍须按具体芯片的擦除和写入规则处理。

## 验收仍需外部确认

- 九月赛资格审核与最终验收属于组委会决定，仓库自查不能替代。官网所示截止时间与个别审核邮件的补交时间可能不同，应按发给参赛者的通知办理。
- 组委会曾明确要求申报书不得由 AI 撰写。参赛者需亲自撰写、核实并提交符合该要求的一页说明；本自查不对现有申报文档的作者归属作保证。
- 申请书中的应用场景使用可复现的小型样例，不等于已有真实生产用户；如有目标板实测或第三方使用证据，应由参赛者补充来源和结果。
