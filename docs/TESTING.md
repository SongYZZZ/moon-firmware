# 测试与验收

## 本地基线

验收使用项目内隔离工具链：

```text
moon 0.1.20260827 (d0aaa07 2026-08-27)
moonc v0.10.11+6ff76a5f9 (2026-08-28)
moonrun 0.1.20260827
native backend
```

Windows 版本为 Microsoft Windows NT 10.0.22621.0。项目不要求提交 `.tools`；贡献者可以使用同版本或更新的兼容稳定工具链。

## 质量门

仓库根目录执行：

```powershell
moon update
moon fmt --check
moon check
moon test
moon info
moon build
moon coverage analyze -- -f summary
moon bench --release benchmarks
moon package --list
```

当前完整测试结果为 239／239 通过。`moon coverage analyze -- -f summary` 报告 1,531／2,014 个可插桩点命中，即 76.02%。CLI 和 example main 不由普通 test runner 调用，因此还执行独立 smoke tests。

## 测试构成

- Intel HEX：types 00～05、checksum 单 bit 破坏、长度／地址／type 变化、大小写、LF／CRLF、BOM、非法 digit、EOF 结构、段／线性扩展、64 KiB 边界、稀疏地址、entry、writer 稳定性。
- SREC：S0／S1／S2／S3／S5／S6／S7／S8／S9、S4 拒绝、count、address width、checksum、终止顺序、稀疏记录、writer 自动／强制宽度。
- MemoryMap：事务性 insert、相邻规范化、三种 overlap、gap、slice、binary fill、最高地址、segment／payload 上限、快照隔离。
- 固件操作：所有转换方向、semantic round-trip、merge、extract、relocate、remove、fill、diff 独立 oracle、inspect。
- 安全：超长行、超长文档、record／payload／warning 预算、整数和地址溢出、BIN 上限、临时文件覆盖策略、Unicode path、checksum corruption。
- Target：具名区域、entry、Thumb bit、alignment、预算、完整 flash page、最高 32-bit page、页数／输出预检查。
- Analysis：标准 CRC 向量、稀疏 fill、掩码搜索、ASCII、大小端 word、Cortex-M vector。

## 固定 seed 生成测试

`firmware/property_test.mbt` 的 generator 完全用 MoonBit 编写且 seed 固定。它运行 512 个稀疏 image 的 HEX 与 SREC round-trip／交叉转换、128 个 CS:IP entry 用例、256 个 diff oracle 用例、128 个 extract／remove／fill 用例和 512 个 malformed document 用例。`model/property_test.mbt` 另执行 96×128 次随机化稀疏 mutation 并与固定 256-byte dense oracle 对照，以及 512 次 interval membership 对照。

固定 seed 保证 CI 可复现；失败 trial 能由测试中的 trial index 定位。测试比较 `FirmwareImage` 的地址和 entry 语义，不要求 canonical writer 与原始文本相同。

## Fixture

| 文件 | 用途 |
|---|---|
| `basic.hex` | 基本 data 与 EOF |
| `extended_linear.hex` | Type 04 与 Type 05 |
| `segment_address.hex` | Type 02 与 Type 03 |
| `bad_checksum.hex` | 必须失败的 checksum |
| `srec16.srec` | S1／S5／S9 |
| `srec24.srec` | S2／S5／S8 |
| `srec32.srec` | S3／S5／S7 |
| `sparse.hex` | 两段不连续地址 |
| `changed.hex` | CLI diff |
| `cortex_m_release.hex` | Cortex-M vector and release-gate smoke test |
| `cortex_m_boot.hex` | Sparse bootloader assembly scenario |
| `cortex_m_app.hex` | Application vector table at `0x08008000` |
| `cortex_m_app_v2.hex` | One-byte OTA diff scenario |

这些文件均为原创最小 fixture，来源与许可记录在 `REFERENCES.md`。

## CLI smoke tests

实际执行了 help、version、inspect、verify、HEX→SREC、SREC→HEX、HEX→BIN、merge、extract、diff、Cortex-M `gate`，以及两个 Library API example。diff 的预期变化退出码为 1；有效固件的 gate 为 0；策略拒绝返回 1；输入或 I/O 错误返回 2。还使用 `moon install ./cmd/moon-firmware --bin ./artifacts/install` 构建并运行了名为 `moon-firmware.exe` 的 release 可执行文件。

## CI

`.github/workflows/ci.yml` 使用已核实存在的 `hustcer/setup-moonbit@v1.22`。干净 Ubuntu runner 先 `moon update` 初始化 registry，再运行 version、format、check、test 和 build。CI 不运行外部兼容工具，也不伪造 benchmark 或 coverage。
