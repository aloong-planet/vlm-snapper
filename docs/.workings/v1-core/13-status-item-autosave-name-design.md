# Ticket 13 — 状态项持久身份设计

## 目标

让 AppKit 在不同启动周期中以固定名称识别 VLMSnapper 唯一的菜单栏状态项，同时保持菜单栏具体排序由 macOS 和用户控制。

## 方案

在 `NSStatusBar.system.statusItem(withLength:)` 返回后立即设置：

```swift
statusItem.autosaveName = "com.loong.vlmsnapper.menu-bar-status-item"
```

名称采用 Bundle ID 前缀和稳定的语义后缀，不包含版本、语言或运行时序号。未来若增加第二个状态项，必须使用不同名称。

## 边界与失败模式

- 用户可继续按住 Command 拖动图标；应用不设置位置或顺序。
- Apple 的公开契约只保证 `autosaveName` 关联持久化信息，不能据此承诺图标排在某个系统状态项旁边。
- 改名会让 AppKit 把它视为新的持久身份，因此该字符串一经发布不得随意修改。
- 重复使用同名会混淆持久状态；当前应用只创建一个状态项。
- 不读取 `SystemUIServer` 或其他私有偏好，不使用私有 API。

## 测试策略

不新增针对私有状态项字段的单元测试，理由见 Ticket 13 的 Testing decision。自动门禁运行现有 `VLMSnapperUITests`、全量测试和严格构建；真实持久化效果在签名应用中通过移动图标、退出并重启进行人工验收。

