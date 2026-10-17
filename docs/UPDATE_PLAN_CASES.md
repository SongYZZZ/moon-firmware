# 更新安全规划：可复现案例与验收

核验日期：2026-10-17。依赖：`Zzqy-yi/firmware-image-toolkit@0.1.0`。
工具链沿用 CI 固定的 `moonc 0.10.14+7d59c7ec9`、`moon 0.1.20260920`，native 后端。

## 输入与语义

- `tests/fixtures/update/baseline.hex`：原创合成的 96 KiB 旧设备快照，boot／application／calibration 分别为 16／64／16 KiB，内容分别为 `0x5A`／`0xA5`／`0x33`。
- `target.json`：显式非等长擦除几何、8 字节编程粒度，仅应用分区可写，boot 和独立校准区受保护。
- `erase-overlay.hex`：只将 `0x08004008` 从 `0xA5` 改成 `0xFF`，需要恢复 0 位，因此必须擦除；未出现的地址均保留旧内容。
- `program-overlay.hex`／`.srec`：同一地址改成 `0xA4`，只清除位，可以免擦除。HEX 和 SREC 均经上游实际解析；更新文件的入口元数据不改变旧镜像入口。
- `shared-calibration.json`：另将应用擦除扇区最后 16 字节标为保护区，验证擦除连带破坏的拒绝行为。
- `stale-device.hex`：受影响扇区内另一字节与基线不同；`incomplete-baseline.hex` 则缺少完整扇区旧内容。

样例由 `scripts/generate-update-fixtures.ps1` 确定性生成，没有使用第三方二进制或芯片厂商固件。配置描述通用 NOR 模型，不对应特定芯片型号。完整旧快照并非由“旧发布文件的空洞补 FF”得到。

## 一次复现全部结果

在仓库根目录执行：

```powershell
moon update
moon check --deny-warn
moon test --deny-warn
moon build --release
pwsh -File scripts/review-update.ps1
```

脚本从真实 native 可执行文件取得 JSON 和退出码，同时把清单的 `verify.expected_hex` 与模拟返回镜像的 `simulation_evidence[].actual_hex` 同独立构造的完整 64 KiB 期望进行比较；实际后像由 `verify_result` 从模拟镜像读取并核验，未仅检查清单自身。完整输出位于 `artifacts/update-review`，该目录不提交仓库。CI 运行相同脚本。

| 案例 | 预期退出码 | 实际检查 |
|---|---:|---|
| preserve-sector | 0 | 1 个受影响扇区、1 次擦除、1 字节修改、65,535 字节保留；整个 64 KiB 校验结果与独立期望一致 |
| program-without-erase | 0 | 0 次擦除，仅 8 字节对齐编程 |
| srec-upstream-input | 0 | SREC 经上游解析，规划结果同样为 8 字节免擦除编程 |
| protected-collateral | 1 | `ProtectedErase`，禁止擦除受保护的共享校准区 |
| stale-device | 1 | `StaleBaseline`，前置比较失败，不能进入模拟写入 |
| unknown-baseline | 1 | `MissingBaseline`，拒绝用假设值补未知旧内容 |
| checksum-error | 2 | `InputFormat`，上游 checksum 诊断，不生成更新计划 |

精简结果记录见 [update-review-results.json](update-review-results.json)。

## 单独体验

```powershell
moon run cmd/moon-firmware -- plan-update tests/fixtures/update/baseline.hex tests/fixtures/update/erase-overlay.hex --profile tests/fixtures/update/target.json
moon run cmd/moon-firmware -- plan-update tests/fixtures/update/baseline.hex tests/fixtures/update/program-overlay.hex --profile tests/fixtures/update/target.json --json
moon run cmd/moon-firmware -- plan-update tests/fixtures/update/baseline.hex tests/fixtures/update/erase-overlay.hex --profile tests/fixtures/update/shared-calibration.json
moon run cmd/moon-firmware -- plan-update tests/fixtures/update/baseline.hex tests/fixtures/update/erase-overlay.hex --profile tests/fixtures/update/target.json --observed tests/fixtures/update/stale-device.hex
moon run examples/update
```

首条命令结果为：

```text
Update plan: accepted; simulation verified
Affected sectors: 1
Erase operations: 1
Changed bytes: 1
Program bytes: 65536
```

使用 `-o artifacts/update-plan.json` 可将接受并模拟通过的计划安全写出；已有文件需显式 `--force`。拒绝时不会写出计划文件。退出 1 表示策略拒绝，退出 2 表示参数、格式、目标配置或 IO 错误。

独立设备快照核验必须显式提供 `--observed`。省略时使用输入基线进行离线回放，不证明另一份设备内容一致；JSON 的 `baseline_source` 明确区分 `supplied_baseline_only` 与 `separate_observed_snapshot`。

## 算法与安全边界

1. 校验目标配置，按地址排序扇区、归并策略区间，检查几何／预算和更新字节的可写范围。
2. 对发生变化的扇区要求完整旧字节，叠加稀疏更新；检查是否存在 0→1 位变化。
3. 需要擦除时检查整个扇区；需要编程时检查整个对齐单元。任何实际操作都不能跨越可写边界或保护区。
4. 根据擦除后的 `0xFF` 或原内容生成必要编程单元，同时保存前后完整字节、CRC 和操作次序。
5. 在任何模拟写入之前，对全部受影响扇区核对前置内容；按 NOR 位规则回放，再比较每个扇区的最终完整字节。

`moonfirmware.update-plan.v1` 清单包含所有前置检查、擦除、编程与结果校验，但没有硬件执行器或从外部 JSON 执行任意计划的入口。CRC 不是密码学认证。具体芯片的 ECC、重复编程限制、快照真实性和断电恢复需调用方另行处理。
