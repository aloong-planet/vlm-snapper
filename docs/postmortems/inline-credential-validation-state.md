# API Key 输入后验证按钮保持禁用

## 用户可见故障

本地测试版 0.1.0 (24) 的管理中心从空 API Key 开始编辑时，输入框显示密文，状态变成待验证，但 Validate 保持禁用。用户多次安装测试后仍能复现。

## 已复现的因果链

`ProviderSettingsConfiguration` 是普通值类型，其中的 API Key 使用应用模型提供的闭包 Binding。输入 setter 已写入模型，但窗口没有观察这个模型；子控件判断也通过嵌套 Binding 的缓存值读取。局部 `apiKeyIsDirty` 的变化可以更新状态徽标，却不保证所有读取拿到本次输入。

真实 `ManagementCenterWindowController` 测试在 AppKit field editor 输入虚拟 Key，确认底层收到完整值，然后在界面上点击 Validate：最初为空的场景不提交，预先有值的对照场景在同一坐标能提交。截图与用户症状一致。

只将绑定提升为 `@Binding` 可修复首次启用，但新的反向测试发现清空后仍能提交空值：任意闭包 Binding 的写入本身不保证视图失效。因此最终把显示值保存在窗口的 `@State` 中，编辑和清空通过同一路径同步到外部绑定；外部凭据值或 Provider 切换随窗口更新同步回来。

## 为什么此前没发现

状态单元测试直接构造 `hasAPIKey: true` 与 `isDirty: true`，证明的是给定一致输入时状态公式正确，没有验证真实编辑能否产生这些输入。渲染测试只检查静态已配置页面，也没有键入或点击。因此这两类绿灯不能证明输入交互已可用。

## 新增防线与证据边界

`ProviderCredentialInteractionTests.editingEnablesValidation` 驱动生产窗口和系统编辑器，覆盖初始空/非空、键入/粘贴、鼠标验证、清空后禁止提交、再次输入与 Return、窗口刷新、外部凭据加载及清除。只使用虚拟 Key，在公开验证回调记录提交内容，不接触真实网络或 Keychain。

恢复旧 `hasAPIKey` 读值路径并重新构建后，同一测试再次在空框提交和清空后的断言失败；恢复修复后完整 272 tests / 69 suites 通过。测试点击位置以当前最小尺寸布局为基准，预填场景是命中位置的正对照。粘贴通过系统 field editor 的公开 `readSelection` 路径测试，不声称这替代了物理 Command-V 按键或完整真实账号验证。

本次修复只处理此回归，不把后续 Ticket 20 的原生编辑器、特殊字符边界、显隐选择区保持及异步提交约束标为完成。

## 2026-09-16 防线更新

上文是当时的坐标测试与结果。布局演进后，同一坐标已不再命中 Validate，不能继续把它当作现行防线。现已替换为原生 `editsSubmitViaReturn`（输入/粘贴/Return/更新）和独立进程 AX 按钮场景（清空、禁用/启用、精确提交），不使用测试坐标猜按钮位置。当前入口、用例映射及物理鼠标验收边界见 [AX 回归说明](../../Tests/AXScenarios/README.md)。
