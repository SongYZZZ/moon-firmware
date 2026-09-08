# Security Policy

## Supported version

当前维护分支为 0.1.x。解析器面向不可信固件文本，但 MoonFirmware 不是签名验证器、安全启动实现或设备烧录授权系统。

## 报告问题

请不要在公开 issue 中附带敏感固件、密钥、设备序列号或未公开漏洞细节。通过 GitHub 仓库的私密安全报告功能联系维护者 SongYZZZ；若该功能不可用，可先创建不含利用细节的 issue，请求私密沟通渠道。

报告应包含受影响版本、最小复现输入、预期与实际结果、平台和 MoonBit 工具链版本。不要发送来源或授权不明的完整商业固件。

## 当前防护

- 文本、单行、record 数、payload、warning、segment 数和生成文本均有明确上限。
- address arithmetic 在构造 range 时检查 32-bit 边界和溢出。
- 稀疏高地址不按最高地址申请内存；BIN 展开和 checksum window 需要显式范围与预算。
- checksum corruption 在 Strict 和 Permissive 中都失败。
- overlap 默认拒绝，失败插入在修改 map 前完成验证。
- CLI 只读取普通文件，路径拒绝 NUL；读取前后检查同一 handle 的 size。
- 输出默认不覆盖，使用同目录随机 staging、排他创建、`sync`、关闭和 rename；创建失败时不会清理他人碰撞文件。

## 安全限制

256 MiB 文本和 64 MiB payload 的合法输入仍可能消耗显著 CPU 与内存。文本当前整体载入内存。读取 size 两次无法识别同长度的并发改写。rename 前同步文件内容，但未同步目录，因而不承诺断电后的目录项持久性。

`Overwrite` overlap、`--force`、BIN fill 和 flash erase value 都是显式的潜在数据改变选项。flash plan 只生成 bytes，不访问设备；调用者仍需验证 MCU 型号、region 权限、擦除粒度和签名。

CRC 与 record checksum 用于错误检测，不提供真实性或抗篡改保证。安全启动场景必须使用设备支持的密码学签名与可信密钥流程。
