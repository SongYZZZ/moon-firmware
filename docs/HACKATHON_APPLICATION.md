# MoonFirmware 项目申报书

**项目名称：** MoonFirmware：基于既有镜像库的 NOR Flash 更新安全规划与验证工具
**参赛者：** 宋永振（SongYZZZ）　**方向：** MoonBit 基础软件／嵌入式发布工具链
**仓库：** [SongYZZZ/moon-firmware](https://github.com/SongYZZZ/moon-firmware)；公开仓库已超过 10 个有效提交，包含功能、测试与修复，未以空提交凑数。

## 项目简介与通用性

核心实现采用 MoonBit。固件文件校验正确，不等于可以安全更新设备：一个字节的修改可能触发整个扇区擦除，误删未修改的数据或校准区。MoonFirmware 接受旧设备快照、稀疏更新镜像和版本化目标配置，在开发主机／CI 中生成并模拟验证 NOR Flash 更新计划。配置显式描述非等长擦除扇区、编程粒度、可写分区和保护区，可服务不同板卡的发布评审、产线更新与维护工具，无需固件本身使用 MoonBit 编写。

## 既有基础与新增核心贡献

项目属于基于开源库的原创扩展，非源码移植。采用“复用开源基础＋新增更新规划”的方式。实际依赖 [Zzqy-yi/firmware-image-toolkit@0.1.0](https://github.com/Zzqy-yi/moonbit-firmware-image)（Apache-2.0），由其提供 HEX／SREC 解析、稀疏镜像及 CRC；不将这些已有能力计为新增贡献。MoonFirmware 新增基于旧内容的扇区重建、NOR 位转换与擦除决策、完整编程单元保护检查、设备基线前置校验和操作序列模拟。旧版转换命令保留兼容，向量静态检查和等长页规划不再作为本次独立贡献的主体。

## 三个完整使用场景

1. **产线局部更新。** 输入旧快照、单字节更新及 16／64／16 KiB 非等长扇区配置，重建受影响的 64 KiB 扇区，输出擦除、编程与校验计划；案例验证只改 1 字节，其余 65,535 字节保持原值，独立 bootloader／校准扇区不被操作。
2. **共享扇区保护。** 输入同一更新和包含扇区尾部校准区的配置，即使更新字节没有落入保护区，规划器仍识别整扇区擦除的连带影响，以 `ProtectedErase` 拒绝，阻止错误计划进入后续烧录流程。
3. **发布基线核验。** 输入基线、更新镜像，通过 `--observed` 提供另一次设备快照，在任何模拟写入前逐字节核对所有受影响扇区；旧内容不一致返回 `StaleBaseline`，旧内容缺失返回 `MissingBaseline`，避免按错误版本或假定的擦除值更新。

## 核心功能与交付边界

已实现版本化 JSON 目标配置、非等长扇区规划、可行时免擦除编程、未更新字节保留、保护区／编程粒度校验、前置检查和 NOR 操作模拟；提供 Library API、`plan-update` CLI、含前后字节证据的确定性 JSON 清单，以及正反案例和 CI。当前 286 项测试通过；源码、测试和原创样例均开源，许可证 Apache-2.0。工具不连接硬件，不宣称断电原子更新或签名认证；配置与快照由调用方提供，具体芯片的 ECC、重复编程等限制需另行适配。

补充材料：[新增贡献及复审回应](https://github.com/SongYZZZ/moon-firmware/blob/main/docs/RESUBMISSION_RESPONSE.md) · [案例与验收结果](https://github.com/SongYZZZ/moon-firmware/blob/main/docs/UPDATE_PLAN_CASES.md)。
