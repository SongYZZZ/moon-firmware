# 可运行应用场景

以下命令均在 2026-09-10 使用仓库内 MoonBit 工具链与原创最小 fixture 实际执行。示例模拟 64 KiB Flash、64 KiB RAM 和 1 KiB 擦除页的 Cortex-M 目标，不对应某个具体量产芯片型号。

## 场景一：单一应用发布门禁

```powershell
moon run cmd/moon-firmware -- gate tests/fixtures/cortex_m_release.hex --flash-start 0x08000000 --flash-end 0x0800FFFF --ram-start 0x20000000 --ram-end 0x2000FFFF --page-size 0x400
```

实际输出：

```text
Release gate: passed
Flash: 0x08000000..0x0800FFFF
Vector table: 0x08000000
Initial stack pointer: 0x20010000
Reset handler: 0x08000008
Flash pages: 1
Page size: 1024 bytes
Payload: 9 bytes
Output: 1024 bytes
Erase padding: 1015 bytes
Erase value: 0xFF
0x08000000..0x080003FF: 9 payload bytes
```

初始栈指针可以等于 RAM 的上边界，这是 Cortex-M 启动栈位于 RAM 顶端的常见布局。复位向量原始值为 `0x08000009`；门禁清除 Thumb 状态位后检查 `0x08000008` 是否位于 Flash 且确实存在于镜像。

## 场景二：bootloader 与 application 装配

```powershell
moon run cmd/moon-firmware -- merge tests/fixtures/cortex_m_boot.hex tests/fixtures/cortex_m_app.hex -o artifacts/cortex-m-release.hex --force
moon run cmd/moon-firmware -- gate artifacts/cortex-m-release.hex --flash-start 0x08000000 --flash-end 0x0800FFFF --ram-start 0x20000000 --ram-end 0x2000FFFF --vector-address 0x08008000 --page-size 0x400
```

`merge` 默认拒绝任何 overlap。第二条命令实际报告 13 字节 payload 和两个烧录页：`0x08000000..0x080003FF` 与 `0x08008000..0x080083FF`。二者相距 32 KiB，中间未触及的页不会分配、填充或写入。

## 场景三：OTA 版本地址差异

```powershell
moon run cmd/moon-firmware -- diff tests/fixtures/cortex_m_app.hex tests/fixtures/cortex_m_app_v2.hex
```

实际结果包含：

```text
Identical bytes: 8
Changed bytes: 1
Changed ranges:
  0x08008008..0x08008008
```

`diff` 比较的是固件地址空间，而不是 HEX 文本。记录长度、大小写或记录排列不同但内存语义相同的文件不会被误报为固件变化。发现语义变化时退出码为 1，适合在 CI 中作为人工复核或发布阻断条件。

## 场景边界

`gate` 读取并验证发布文件，生成确定性的烧录页计划，但不连接 SWD／JTAG、串口或 USB，也不操作真实设备。页大小、擦除值、Flash、RAM 和向量表地址均来自调用者明确提供的目标合同；工具不会猜测芯片型号。
