# MoonFirmware 设计说明

## 边界与分层

MoonFirmware 将协议文本、固件语义和操作系统 IO 分开。`codec` 提供严格的 ASCII 十六进制与有界行扫描；`ihex`、`srec` 各自实现记录规则和 checksum；`model` 只表达地址空间；`firmware` 在统一模型上执行转换和集合操作；`validation`、`analysis` 提供可选的目标校验与镜像分析；`cli` 才接触参数和文件。

根包只暴露长期使用的高层类型和函数。格式专属的 `Record`、writer options 和 checksum 保留在子包中，避免将 parser 的内部状态变成公共 API。

## 为什么使用 sparse memory model

固件地址是设备地址，不是文件偏移。一个镜像可能仅含两个 1 KiB 区域，却分别位于 `0x00000000` 和 `0xFFFF0000`。若使用长度等于最高地址的 `Array[Byte]`，这 2 KiB payload 会申请近 4 GiB；恶意输入还可用一条高地址记录触发巨大分配。

`MemoryMap` 保存按起始地址排序、非空、互不重叠且不相邻的 segment。相邻插入会规范化合并，连续的小记录不会退化成数万个 1-byte segment。gap 只由两个端点表达；内存主要随真实 payload 和 segment 数增长。公共 `segments()` 返回不可变快照，不泄漏内部可增长数组。

`MemoryMap` 的地址范围为 `0x00000000` 至 `0xFFFFFFFF`，区间统一使用 half-open `[start, end)`。显示给用户时用包含端点的 `start..end-1`。空区间合法，但任何非空数据都必须完全落入 32-bit 地址空间。

## 地址语义

Intel HEX Data Record 的 16-bit 地址与最近的扩展地址记录组合：

- Type 02：base 为 16-bit segment 值左移 4 位。HEX86 data offset 在 64 KiB 边界按 16-bit 回绕，回绕后的字节仍落在同一个 segment base。
- Type 04：base 为 16-bit upper linear 值左移 16 位。数据地址按线性地址递增，writer 会在 64 KiB 边界拆分并切换 Type 04。
- Type 03：保留原始 CS:IP，统一模型表示为 `EntryPoint::Segment`。
- Type 05：32-bit 线性入口，表示为 `EntryPoint::Linear`。

S1、S2、S3 分别使用 16、24、32-bit big-endian 地址。S7、S8、S9 是对应宽度的终止／入口记录。解码后所有 data address 都进入相同的绝对地址空间。

## 插入与 overlap

插入先完成范围、冲突、payload 和 segment 数检查，再改变 map，因而错误不会留下部分写入。

- `Reject`：任何已占用地址都报错，默认用于 parse 和 merge。
- `AllowIdentical`：只允许重叠字节全部相同；第一个不同字节形成结构化冲突诊断。
- `Overwrite`：新字节覆盖旧字节，未覆盖部分保留并重新规范化。

冲突诊断保留第一个连续冲突范围。merge 按输入顺序应用策略，并单独处理 entry point 冲突。

## 解析模式

Strict 接受 LF 或 CRLF，但拒绝空行、注释、外围空白、BOM、缺少 terminator、重复 terminator 和重复 entry。Permissive 仅容忍 UTF-8 BOM、ASCII 外围空白、空行、以 `#` 或 `;` 开始的整行注释、缺少 terminator、Intel HEX 重复 EOF、以及 SREC 混合 data width；每次容忍都生成 warning。

两种模式都拒绝错误 checksum、错误 count、非法 digit、地址溢出、未知 record type、terminator 后 data 和冲突写入。`max_warnings` 防止宽松输入通过注释洪泛消耗内存。

## 确定性序列化

writer 总是遍历规范化的升序 segment，同样的 image 和 options 会产生逐字节相同的文本。Intel HEX 默认每条 16 个 data bytes，必要时切分 64 KiB 边界，按变化输出 Type 04，随后输出 entry 和唯一 EOF。SREC 选择能够覆盖最高 payload／entry 地址的最小 S1/S2/S3 宽度，按需要输出 S5 或 S6，然后输出匹配的 S9/S8/S7。

大小写、record data length 和 LF／CRLF 是显式选项。Intel writer 使用 Type 04 作为 canonical 地址形式，不尝试还原输入的记录边界或 Type 02。确定性指语义模型到文本稳定，不表示与原文字符相同。

## BIN 与空洞

BIN 没有地址或入口 metadata。载入 BIN 必须提供 base address。输出 BIN 必须有隐含的 image bounds 或显式 window；window 中出现 gap 时必须给 fill。默认 16 MiB、硬上限 64 MiB 阻止稀疏高地址被无意展开成巨型文件。

## Diff、截取与 flash 计划

diff 对两个排序 segment 做区间 sweep，生成 only-left、only-right 和 changed ranges，同时累计相同字节数；它不对空洞逐字节扫描。extract 计算 segment 与选择区间的交集，保留内部 gap；范围外 entry 被移除并产生 warning。

flash planner 只产生含 payload 的完整 page。页内空白由调用者明确指定的 erase value 填充，完全未触及的页不出现。它在分配页数据前验证完整页的 allowed range、页数和总输出预算；计划是数据，不代表已经执行设备擦除。

## Cortex-M 发布门禁

`validate_cortex_m_release` 将通用布局校验、Cortex-M 前两个向量和 flash page plan 组合成一个目标合同。调用者必须明确给出 Flash、一个或多个 RAM 区间、向量表地址、页大小与擦除值；库不根据文件名或地址猜测芯片型号。

所有 payload 必须落在 Flash。初始栈指针必须满足对齐并位于 RAM；由于 Cortex-M 启动栈通常从 RAM 顶端向下增长，栈指针允许等于 half-open RAM 区间的 `end`。复位向量必须设置 Thumb 位，清除状态位后的处理器地址必须位于 Flash 且在稀疏镜像中存在。只有布局和向量检查都通过时才生成完整页计划。门禁返回报告和退出状态，不连接设备，也不把计划解释为已经烧录。

## 错误模型

`FirmwareError` 包含 `Diagnostic`，后者有稳定 `ErrorCode`、格式、1-based 行列、可选记录类型和地址范围。parser 将底层地址／overlap 错误重新附上原始行位置。IO 错误只在 CLI 边界转换为 `Io`；Library API 不接收路径。

程序只在内部不可达状态使用测试失败或不变量；用户输入的语法、大小、范围、选项和冲突都返回结构化错误。输出 writer 在 append 前检查容量，避免先生成超限文本再发现错误。

## 文件写入

CLI 打开普通文件并在读取前检查 size，读取后用同一 handle 再次检查 size。输出默认拒绝已有路径；写入同目录、随机命名且排他创建的 staging 文件，`sync` 并关闭后 rename。只有成功创建 staging 的进程才会清理它，避免碰撞时删除他人的文件。

这提供应用级失败隔离，但没有目录 `fsync` 的断电事务保证，也无法识别同长度并发输入修改。对应限制在 README 和安全文档中公开。
