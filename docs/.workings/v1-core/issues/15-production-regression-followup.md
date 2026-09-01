# 15 — Production regression follow-up

Status: implemented; pending installed-app acceptance

Blocked by: none

## Goal

修复安装版实测仍存在的三个生产回归：菜单栏截图恢复时引导窗口没有可靠置前、Provider 模型列表鉴权失败被误报为临时不可用，以及最小管理中心窗口裁掉标题栏内容。

## Acceptance

- 从菜单栏面板点击“截取屏幕”且权限或 Provider 未就绪时，面板先完全关闭，引导窗口随后可靠显示为最前面的 key window。
- Provider 模型列表返回 401/403 时显示 API Key 被拒绝的明确原因，不再显示 Provider 临时不可用；失败不保存候选 Key，也不自动重试。
- 管理中心缩到允许的最小尺寸时，内容区仍至少为 `920×620`，Header、列表底栏和详情内容均不被窗口外框裁切。
- 已确认的引导、Provider 和管理中心原型继续作为视觉权威，不增加或改变控件、间距方向或产品范围。
- 聚焦测试、完整测试、双语明暗渲染、代码 review、测试 review 和文档同步全部通过。

## Comments

- 2026-09-01: User reproduced the three regressions in the locally installed Developer ID build.
- 2026-09-01: Unified logging confirmed a successful TLS exchange followed by OpenAI HTTP 401; the application displayed the wrong failure category.
- 2026-09-01: An AppKit geometry probe confirmed that a `920×620` frame exposes only a `920×588` content layout rectangle.
- 2026-09-01: Strict build, 216 Swift tests in 57 suites, 44 production renders, localization parity, syntax/literal scans, code review, test review, and documentation regression all passed.
- 2026-09-01: Developer ID arm64 build 6 passed the package verifier and replaced build 5 in `/Applications`; build 5 remains as a recoverable backup. Final frontmost-window acceptance is intentionally left to the real installed-app test.
