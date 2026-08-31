# 13 — Status item autosave identity

Status: completed

Blocked by: none

## Goal

为唯一的菜单栏状态项设置稳定、显式的 `autosaveName`，使 AppKit 能够跨启动识别同一个状态项，而不依赖自动生成名称。

## Acceptance

- 状态项创建后立即设置固定名称 `com.loong.vlmsnapper.menu-bar-status-item`。
- 名称不包含版本号、不参与本地化，且不与未来其他状态项复用。
- 实现不读取或修改 macOS 私有菜单栏排序偏好，也不承诺把图标强制放在系统图标旁边。
- 严格构建、完整测试和文档一致性门禁通过。

## Testing decision

本票豁免新增单元测试。`NSStatusItem` 被封装在 AppKit controller 内部，`autosaveName` 是一行系统接线；为读取它而暴露生产属性、反射私有字段或复制同一常量作断言都会把测试耦合到实现细节，并不能验证 macOS 跨启动持久化。回归由现有菜单栏 controller 测试、完整测试套件和签名应用重启后的人工验收承担。

## Comments

- 2026-08-31: User requested an explicit `autosaveName` after discussing macOS menu-bar ordering and persistence boundaries.
- 2026-08-31: Implemented the fixed identity with a strict build, the five existing status-item interaction tests, and the complete 197-test / 49-suite regression gate.
- 2026-08-31: Developer ID-signed arm64 build 3 passed the repository app verifier, installed over a recoverable build 2 backup, and launched successfully. User-position persistence remains a user-controlled drag-and-restart observation rather than an automated position claim.
