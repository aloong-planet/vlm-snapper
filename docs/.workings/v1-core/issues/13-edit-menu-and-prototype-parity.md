# 13 — Edit menu and confirmed prototype parity

Status: completed

Blocked by: none

## Goal

完整提供符合 macOS responder chain 的 Edit 菜单，并让当前所有用户可见页面（包括菜单栏左键主面板）回到已经确认的原型结构、状态和视觉密度。

## Acceptance

- 应用提供本地化的标准 macOS 主菜单，Edit 菜单完整包含确认原型中的 Undo/Redo、剪贴板、Find、Spelling & Grammar、Substitutions、Transformations、Speech、Dictation 与 Emoji & Symbols 项。
- Edit 菜单命令使用 AppKit responder chain；文本输入焦点切换时，Paste/Cut/Copy/Delete/Select All 等项目的启用状态和执行对象随系统自动更新。
- Provider API Key 输入框及应用中其他标准文本输入表面可使用 Command-V，并保留系统 Edit 菜单行为。
- 菜单栏左键主面板与 `companion-shell` 确认原型一致：品牌与 Provider 状态、主截图按钮、更新提示、带缩略图/操作时间/状态的最近记录、双列底部入口。
- 引导、存储隐私、Provider 配置、权限恢复、截图操作栏、结果工作台和管理中心分别与其已确认原型保持同一信息层级、结构、状态表达和已确认几何常量。
- 原型演示数据不进入生产；生产界面使用真实应用状态，缺失数据使用正式空态，而不是伪造结果。
- 中英文与明暗模式均有真实 SwiftUI/AppKit 渲染证据；关键几何和菜单契约有独立测试，不能只断言 PNG 文件存在。
- spec、feature catalog、设计文档、原型 manifest 与生产实现保持一致。

## Comments

- 2026-08-31: User required the complete confirmed Edit menu and full parity for every page, explicitly including the left-click menu bar panel.
- 2026-08-31: Existing HTML prototypes remain the accepted design contract; this ticket implements them in native AppKit/SwiftUI rather than treating prototype renders as implementation evidence.
- 2026-08-31: Completed with a localized native application menu, responder-chain Paste, real menu/history/provider presentation data, all confirmed native surfaces, 40 named bilingual light/dark renders, strict build, and 209 tests in 54 suites.
- 2026-08-31: Code review corrected multi-Provider state misreporting and Markdown heading markers in recent titles. Test review killed selector, geometry, and Provider-state mutations and replaced the stale-file-prone render count with an exact filename contract.
