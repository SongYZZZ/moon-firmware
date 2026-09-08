# 0.1.0 Release Audit

审计日期：2026-09-08。

## Build 与格式

- `moon fmt --check`：通过。
- `moon check`：通过，无项目 warning。
- `moon build`：native debug 通过。
- `moon info`：通过；根包公开高层类型与 24 个操作，协议细节留在 `ihex`／`srec`。
- `moon package --list`：通过；生成 `SongYZZZ-moon-firmware-0.1.0.zip`。

Windows native 编译依赖 `moonbitlang/async` 时，MSVC 输出其 `fs.c` 与 Windows SDK 的 `EINVAL` 宏重复 warning。该 warning 来自缓存依赖 C stub，不是 MoonFirmware 源码 warning，也未导致失败。仓库未修改 vendor 内容来隐藏它。

## 测试与 coverage

- `moon test`：231 passed，0 failed。
- 固定 seed：512 个双 codec round-trip、512 个 malformed、256 个 diff oracle、96×128 个 sparse mutation，以及其他生成用例。
- `moon coverage analyze -- -f summary`：1,417／1,864 instrumented points，76.02%。
- `moon bench --release benchmarks`：3 个 benchmark group 通过；数字见 `BENCHMARKS.md`。

## CLI

以下命令已实际执行并检查退出码：help、version、inspect、verify、convert（HEX→SREC、SREC→HEX、HEX→BIN）、merge、extract、diff。变化 diff 返回 1；坏 checksum 返回 2。`moon install ./cmd/moon-firmware --bin ./artifacts/install` 实际生成并运行了 `moon-firmware.exe`。

## 文档

README 中的快速体验、CLI、example、测试、benchmark、coverage 和 package 命令均已执行。README 本地链接检查没有发现缺失目标。功能表与当前公开 `.mbti` 对照；未实现或未实测能力保留在限制／roadmap，不写成已完成。

## GitHub

- active GitHub identity：`SongYZZZ`。
- remote：`https://github.com/SongYZZZ/moon-firmware.git`。
- repository：public，default branch `main`，GitHub 识别许可证 Apache-2.0。
- Ubuntu native CI run 34192594210：所有 11 个步骤成功，包括 CLI inspect／verify。

## Code size

统计 tracked `*.mbt`，排除 `.tools`、`.mooncakes`、`_build`、`.mbti` 和所有生成／vendor 内容。有效行定义为非空且非纯 `//` 注释行。

| Category | Physical | Effective |
|---|---:|---:|
| Core | 4,666 | 4,063 |
| Tests | 2,896 | 2,400 |
| Benchmarks | 87 | 80 |
| Examples | 33 | 31 |
| Total | 7,682 | 6,574 |

Core 达到 4,000 有效 MoonBit 行门槛。新增代码来自协议、稀疏模型、转换、CLI、安全边界、target validation 和 image analysis，没有将测试或 benchmark 计入 core。

## Release identity

GitHub owner 与 remote 正确。当前 Mooncakes `moon whoami` 为 `hjn0123`，不是 `SongYZZZ`；因此只验证 package，没有执行 publish。此状态是 0.1.0 唯一的发布阻塞项，不影响源码、GitHub、CI 或本地安装。
