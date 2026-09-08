# Benchmark

以下数据由 `moon bench --release benchmarks` 在 2026-09-08 实际执行。环境为 Microsoft Windows NT 10.0.22621.0、MoonBit moon 0.1.20260827、moonc 0.10.11、native release backend。当前受限会话无法读取 CPU 型号，因此不填写猜测硬件。

| Case | Mean | σ | Observed range |
|---|---:|---:|---:|
| HEX parse 100 KiB | 5.74 ms | 353.71 µs | 5.22～6.15 ms |
| HEX write 100 KiB | 10.38 ms | 1.31 ms | 8.72～11.94 ms |
| SREC parse 100 KiB | 6.58 ms | 464.05 µs | 5.86～7.08 ms |
| SREC write 100 KiB | 11.57 ms | 802.88 µs | 10.39～12.33 ms |
| HEX parse 1 MiB | 60.71 ms | 8.51 ms | 52.58～71.89 ms |
| HEX write 1 MiB | 86.77 ms | 8.74 ms | 78.88～99.55 ms |
| SREC parse 1 MiB | 74.39 ms | 8.09 ms | 64.67～83.23 ms |
| SREC write 1 MiB | 106.25 ms | 12.66 ms | 91.08～123.48 ms |
| HEX parse，1024 segments／4 GiB span | 6.71 ms | 171.35 µs | 6.45～6.93 ms |
| HEX parse，102,400 one-byte records | 59.03 ms | 4.93 ms | 54.76～66.92 ms |

100 KiB 与 1 MiB 数据由固定字节函数生成。稀疏 case 存储 1024×100 bytes，但地址跨度接近 4 GiB；它验证解析成本取决于记录和 payload，而不会申请 4 GiB dense array。小记录 case 验证升序 append／segment normalization 不会因逐记录插入退化成海量单字节 segment。

这些结果只描述当前机器的一次运行，不代表跨机器保证，也不用于宣称“最快”。变更 parser、writer 或 memory normalization 后应重跑并更新日期、工具链和完整结果。
