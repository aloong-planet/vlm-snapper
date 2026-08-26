# ADR-0004: 为三个发行架构使用独立 Sparkle appcast

- 状态: 已接受（2026-08-25）

## 背景与问题

VLMSnapper 直接分发 Universal、Apple Silicon 和 Intel 三个独立安装包。自动更新必须保证已安装的精简架构包不会被意外替换为 Universal 或另一架构，同时三个下载入口和更新源不能出现版本不一致。

## 备选项

1. **三个发行架构分别使用独立 appcast，并以全有或全无门禁发布同一版本**
2. 所有安装包共用一个只指向 Universal 更新的 appcast——否决，因为 arm64 和 x64 用户更新后会失去原先选择的精简架构包
3. 共用一个包含多个架构更新项的 appcast——否决，因为架构选择、Rosetta 场景和回退规则更复杂，错误配置可能向用户投递不匹配的构建

## 决策

选定**方案 1**：Universal、arm64 和 x64 构建分别嵌入各自的 HTTPS appcast 地址。三条 appcast 使用同一 Sparkle EdDSA 公钥和相同版本号，但各自指向对应架构的签名、公证、stapled 更新包。自动更新保持当前安装包架构，不执行跨架构迁移。

发布流水线实行全有或全无门禁：只有三个架构的构建、Developer ID 签名、Apple 公证、stapling、Sparkle EdDSA 签名和 appcast 生成全部成功，才发布该版本；任一步失败都不更新任何公开 appcast。

## 后果

- 正面：用户持续获得自己选择的架构包；三种下载和更新入口保持版本一致；架构路由简单且可独立验证。
- 负面：每个版本需要生成和维护三条 appcast及三份更新产物，发布流水线和回滚操作更多。
- 中性：在 Apple Silicon 上安装 x64 构建的用户会继续收到 x64 更新；若要改用 arm64 或 Universal，需要手动重新安装对应发行包。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/)
