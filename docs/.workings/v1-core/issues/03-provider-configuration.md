# 03 — Provider configuration

Status: completed

Blocked by: 01

## Goal

实现 Provider 配置领域模型、Apple Keychain、完整模型列表刷新、当前选择和视觉兼容状态。

## Acceptance

- API Key 仅在鉴权和完整分页成功后原子写入 Keychain。
- 模型不可手输，成功刷新后消失的当前模型被清除，刷新失败保留旧缓存。
- 24 小时缓存、手动刷新、一次模型不存在刷新和活动请求配置冻结符合 spec。
- 未知、已验证、不兼容状态只按明确协议证据转换。

## Comments

- Provider 模型请求级的错误归一化与“一次刷新”接线由 Ticket 04 完成；本票已提供每次尝试只能 claim 一次的状态原语。
- Data Protection Keychain 的生产默认保持启用；未签名 SwiftPM 宿主只能验证登录 Keychain 生命周期，签名路径由 Ticket 10 验收。
