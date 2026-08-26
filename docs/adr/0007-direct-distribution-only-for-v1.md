# ADR-0007: v1 仅采用 Developer ID 直接分发

- 状态: 已接受（2026-08-25）

## 背景与问题

VLMSnapper 已决定启用 App Sandbox，并参考了 Transfer 的 Mac App Store 审核经验来划分用户截图与应用内部数据的存储位置。App Sandbox 同时适用于直接分发应用，启用它不意味着产品必须进入 Mac App Store。当前发布需求已经包含 Universal、Apple Silicon 和 Intel 三个 Developer ID DMG、三条 Sparkle appcast 以及全有或全无的发布门禁；增加 MAS 会引入不同的签名、provisioning、更新和测试边界。

## 备选项

1. **v1 只发布三个 Developer ID DMG，不提供 MAS 版本**
2. v1 同时提供 MAS 版本——否决，因为需要独立 target、签名与 provisioning、App Store 更新机制、TestFlight 验证和第四条发行流水线，超出当前范围
3. v1 只发布 MAS 版本——否决，因为产品已经确认 Sparkle、自选架构安装包和 Developer ID 直接分发

## 决策

选定**方案 1**。v1 仅发布 Universal、Apple Silicon 和 Intel 三个 Developer ID 签名、公证并 stapling 的 DMG，继续通过各自的 Sparkle appcast 更新。v1 不创建 MAS target、不提交 Mac App Store、不使用 TestFlight，也不把 MAS 产物纳入三架构发布门禁。

App Sandbox 和所需 entitlements 仍在三个直接分发构建中启用，作为安全边界和最小权限设计。未来若增加 Mac App Store，必须另建 ADR，重新确定 Bundle Identifier、更新机制、签名与 provisioning、收据验证、TestFlight 和跨渠道数据兼容策略。

## 后果

- 正面：发布矩阵维持三种架构，不增加第四条渠道和独立审核状态。
- 正面：Sparkle 更新、架构保持和全有或全无发布门禁在所有 v1 产物中保持一致。
- 负面：v1 无法通过 Mac App Store 搜索、购买或自动更新，用户只能从直接分发渠道安装。
- 中性：参考 MAS 审核案例仍有价值，因为用户文件可发现性和 entitlement 最小化同样改善直接分发版本；但这些案例不构成 v1 必须通过 MAS 审核的交付条件。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [ADR-0004: 为三个发行架构使用独立 Sparkle appcast](0004-separate-sparkle-feeds-per-distribution-architecture.md)
- [ADR-0005: 固定直接分发应用身份](0005-stable-direct-distribution-application-identity.md)
- [ADR-0006: 将原始截图与应用内部历史分层存储](0006-layer-user-screenshots-and-internal-history-storage.md)
