# Contributing to MoonFirmware

感谢你改进 MoonFirmware。项目优先级依次为正确性、可测试性、实际用途、API 清晰度、可维护性和性能。

## 开发环境

使用 MoonBit moon 0.1.20260827／moonc 0.10.11 或更新的兼容稳定版本，安装 native 编译环境，然后在仓库根目录运行：

```powershell
moon update
moon fmt --check
moon check
moon test
moon build
```

提交前执行 `moon fmt`，并保证上述质量门通过。若改变公开 API，运行 `moon info` 并检查生成接口；`.mbti` 是本地生成文件，不提交。

## 代码与测试

- MoonBit 是核心实现语言。不要用外部语言代理 parser、writer、memory model 或固件操作。
- 公共类型和函数使用 `///|` doc comments。协议规则放在对应包，CLI 只处理参数、IO 和展示。
- 用户输入错误返回 `FirmwareError(Diagnostic)`；除内部不变量外，不使用 panic。
- 为行为写有意义的边界测试，包括失败位置、事务性和资源预算。随机测试固定 seed，并显示可复现 trial。
- 不删除困难测试来获得绿色结果，不提交生成产物、依赖缓存或 benchmark 猜测值。
- fixture 优先依据公开规范原创。引入第三方样例前确认再分发许可，并更新 `docs/REFERENCES.md`。

## 协议修改

协议 edge case 必须有公开格式资料或可复现的互操作证据。Intel HEX 与 SREC checksum 保持独立实现。修改地址算法时至少增加 parser、writer 和 semantic round-trip 测试；不要只比较文本。

Permissive 只容忍文档化的非关键表示差异。任何放宽都必须产生 warning，并且不能放过 checksum corruption、截断 data、地址溢出或未知类型。

## Commit 与 PR

使用描述实际变化的提交，例如 `feat: validate target flash page bounds`、`fix: preserve overlap failure atomicity`。PR 说明应给出触发条件、修复后的行为、验证命令和兼容性影响。一个提交不必只改一个文件，但应保持可审查的开发阶段。

贡献即表示你有权以 Apache-2.0 提供该代码。安全问题请按 `SECURITY.md` 报告。
