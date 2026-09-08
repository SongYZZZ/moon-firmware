# Changelog

本项目遵循语义化版本，日期使用 `YYYY-MM-DD`。

## 0.1.0 — 2026-09-08

首次黑客松参赛版本。

### Added

- 稀疏、规范化且有资源边界的 32-bit `FirmwareImage`／`MemoryMap`。
- Intel HEX 00～05 parser、validator、checksum 和确定性 writer。
- Motorola S-Record S0／S1／S2／S3／S5／S6／S7／S8／S9 codec。
- 内容格式检测以及 HEX、SREC、BIN 全向转换。
- overlap-aware merge、range extract／remove／fill／relocate 和 address diff。
- inspect、verify、convert、merge、extract、diff 原生 CLI。
- target region／entry 校验和 bounded touched-page flash plan。
- image CRC／additive checksum、masked pattern、ASCII、word 与 Cortex-M vector 分析。
- 231 个测试入口，包括固定 seed property tests、原创 fixture 和真实文件 IO。
- native benchmark、GitHub Actions、双语 README、设计／格式／测试／安全文档。

### Known limitations

- CLI 0.1.0 为 native-only。
- SREC input 只处理单 block，S4 和厂商私有类型不支持。
- Intel writer canonicalize 为 Type 04，不生成 Type 02。
- 尚未完成第三方工具交叉兼容矩阵。
