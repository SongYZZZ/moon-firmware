# MoonFirmware

面向嵌入式固件的 Intel HEX / Motorola S-Record 解析、校验与转换工具库。

作者：宋永振（SongYZZZ）。许可证：Apache-2.0。

项目正在分阶段实现。MoonBit 为核心语言，采用稀疏地址模型；目标是带地址语义的固件处理，不是 Hex Editor。

本地工具链：moon 0.1.20260819，moonc v0.10.9。默认后端为 native。

开发检查：`moon fmt`、`moon check`、`moon test`。
