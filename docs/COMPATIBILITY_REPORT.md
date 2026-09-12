# 成熟工具对照实验

实验日期：2026-09-12。环境：Windows 10、MoonBit `moon 0.1.20260827`／`moonc 0.10.11`、IntelHex 2.3.0、bincopy 20.1.1。IntelHex 与 bincopy 只用于交叉验证，不是 MoonFirmware 的依赖。

## 实验目的

实验分为两个问题：MoonFirmware 生成的文件能否被已有工具读取；格式正确是否足以判断固件可以交付给目标 MCU。前者检验互操作性，后者检验发布门禁的必要性。

## 结果

| 实验 | 输入与操作 | 实际结果 |
|---|---|---|
| MoonFirmware HEX → IntelHex | 将 SREC32 转为 HEX，使用 IntelHex 2.3.0 读取 | 接受；4 字节，范围 `0x08000010..0x08000013`，入口 `0x08000010` |
| MoonFirmware SREC → bincopy | 将 extended-linear HEX 转为 SREC，使用 bincopy 20.1.1 读取 | 接受；4 字节，范围 `0x08000010..0x08000013` |
| IntelHex 重写 → MoonFirmware | IntelHex 重写 `extended_linear.hex`，再执行地址级 `diff` | 0 个变化，入口一致，退出码 0 |
| bincopy HEX → SREC → MoonFirmware | bincopy 转换 `cortex_m_release.hex`，再解析和比较 | bincopy 未生成 termination；Strict 按规范拒绝，Permissive 给出明确 warning 后接受；9 字节语义一致，退出码 0 |
| 格式校验与目标校验 | IntelHex、bincopy 和 `moon-firmware verify` 读取 `cortex_m_bad_target.hex` | 三者均确认记录可解析、checksum 正确；`moon-firmware gate` 进一步以退出码 1 拒绝，报告栈指针不在 RAM、未按 8 字节对齐、复位向量未设置 Thumb 位 |
| 稀疏镜像输出 | bootloader 位于 `0x08000000`，application 位于 `0x08008000` | bincopy 的连续 `as_binary()` 为 32,777 字节；MoonFirmware 的 1 KiB touched-page plan 为 2,048 字节，仅列出两个实际触及页 |

最后一项比较的是两种不同输出语义，不表示 bincopy 转换错误。连续 BIN 必须覆盖最低至最高地址；烧录页计划只表示需要处理的完整页。结果说明固件发布还需要目标布局、向量语义和页粒度信息，不能由 HEX／SREC checksum 单独替代。

## 关键命令

外部工具安装在仓库忽略的 `.tools/compat` 目录：

```powershell
python -m pip install --target .tools/compat intelhex==2.3.0 bincopy==20.1.1
python .tools/compat/bincopy.py --version
```

互操作检查使用以下输入与输出链：

```powershell
moon run cmd/moon-firmware -- convert tests/fixtures/extended_linear.hex artifacts/moon-extended.srec --force
moon run cmd/moon-firmware -- convert tests/fixtures/srec32.srec artifacts/moon-srec32.hex --force
python .tools/compat/bincopy.py info artifacts/moon-extended.srec
python -c "import sys; sys.path.insert(0, r'.tools/compat'); from intelhex import IntelHex; print(IntelHex(r'artifacts/moon-srec32.hex').segments())"

python .tools/compat/bincopy.py convert -i ihex -o srec tests/fixtures/cortex_m_release.hex artifacts/bincopy-cortex.srec
moon run cmd/moon-firmware -- diff tests/fixtures/cortex_m_release.hex artifacts/bincopy-cortex.srec --permissive

python -c "import sys; sys.path.insert(0, r'.tools/compat'); from intelhex import IntelHex; image=IntelHex(r'tests/fixtures/extended_linear.hex'); image.write_hex_file(r'artifacts/intelhex-extended.hex', byte_count=16)"
moon run cmd/moon-firmware -- diff tests/fixtures/extended_linear.hex artifacts/intelhex-extended.hex
```

目标错误对照：

```powershell
moon run cmd/moon-firmware -- verify tests/fixtures/cortex_m_bad_target.hex
moon run cmd/moon-firmware -- gate tests/fixtures/cortex_m_bad_target.hex --flash-start 0x08000000 --flash-end 0x0800FFFF --ram-start 0x20000000 --ram-end 0x2000FFFF --page-size 0x400
```

第一条命令退出 0，因为文件格式与 checksum 正确；第二条命令退出 1，因为它不满足目标 MCU 合同。输入损坏、参数错误或 I/O 错误使用退出码 2，以便 CI 区分“发布策略拒绝”和“工具执行失败”。

稀疏镜像对照使用同一份合并结果：

```powershell
moon run cmd/moon-firmware -- merge tests/fixtures/cortex_m_boot.hex tests/fixtures/cortex_m_app.hex -o artifacts/cortex-m-release.hex --force
python -c "import sys; sys.path.insert(0, r'.tools/compat'); import bincopy; image=bincopy.BinFile(r'artifacts/cortex-m-release.hex'); print(len(image.as_binary()))"
moon run cmd/moon-firmware -- gate artifacts/cortex-m-release.hex --flash-start 0x08000000 --flash-end 0x0800FFFF --ram-start 0x20000000 --ram-end 0x2000FFFF --vector-address 0x08008000 --page-size 0x400
```

## 可复核材料

- `tests/fixtures/cortex_m_bad_target.hex`：checksum 正确、目标语义错误的对照输入。
- `tests/fixtures/cortex_m_boot.hex`、`cortex_m_app.hex`：稀疏装配输入。
- `docs/APPLICATION_SCENARIOS.md`：MoonFirmware 发布门禁、装配和 diff 的完整命令与输出。

实验没有连接真实芯片或调试探针，因此结论限于文件互操作、地址语义、目标合同和烧录数据计划，不包含设备通信可靠性。
