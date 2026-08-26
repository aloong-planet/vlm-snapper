# ADR-0005: 固定直接分发应用身份

- 状态: 已接受（2026-08-25）

## 背景与问题

VLMSnapper 的 Bundle Identifier 会参与 macOS 屏幕录制权限、Keychain 访问、登录项注册、Sparkle 更新和代码签名身份判断。产品还会提供 Universal、arm64 和 x64 三个直接分发构建；如果它们使用不同身份或发布后更换身份，用户可能丢失权限、凭据访问和更新连续性。

## 备选项

1. **直接分发版本固定使用 `com.loong.vlmsnapper`，三个架构共享身份**
2. 使用 `com.aloongplanet.vlmsnapper`——否决，因为现有 Transfer 的直接分发版本采用 `com.loong.*`，`com.aloongplanet.*` 用于其 Mac App Store 变体
3. 为三个架构使用不同 Bundle Identifier——否决，因为会把同一产品拆成三个独立的权限、Keychain、登录项和更新身份

## 决策

选定**方案 1**：应用显示名为 `VLMSnapper`，v1 直接分发 Bundle Identifier 固定为 `com.loong.vlmsnapper`。Universal、arm64 和 x64 构建共享该 Bundle Identifier，只允许构建架构和 Sparkle appcast 地址不同。

Keychain service、登录项、屏幕录制权限和 Sparkle 配置均以该 Bundle Identifier 作为稳定根标识。正式发布后不得在普通升级中修改；如果未来确需迁移，必须另建 ADR 和显式迁移方案。

## 后果

- 正面：三个架构共享同一应用身份，Keychain、TCC 权限、登录项和自动更新在版本升级中保持连续。
- 负面：发布后更名或改变反向域名需要兼容迁移，不能只修改构建配置。
- 中性：不同架构仍通过 ADR-0004 的独立 appcast 保持更新产物隔离，但它们在 macOS 看来是同一个应用身份，用户不应并行安装多个架构变体。

## 来源

- [VLMSnapper v1 需求对齐记录](../.workings/v1-core/requirements-alignment.md)
- [ADR-0004: 为三个发行架构使用独立 Sparkle appcast](0004-separate-sparkle-feeds-per-distribution-architecture.md)
