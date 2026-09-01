# 14 — Confirmed UI regression fixes

Status: completed

Blocked by: none

## Goal

恢复已经确认、但在生产应用中回归的截图恢复路径、Provider 输入交互和管理中心视觉层级，不引入新的产品范围或视觉方向。

## Acceptance

- 菜单栏面板点击截图时先关闭面板；Provider 或权限未就绪则把首次引导窗口带到最前，就绪才进入截图。
- Provider 配置不再附着到状态项 popover，而是在应用窗口中居中展示且不越出屏幕。
- 粘贴或输入 API Key 后 Validate 立即启用；验证进行中禁用，切换 Provider 不泄漏上一项草稿。
- 浅色管理中心和 Provider 左侧导航使用已确认的浅层次级表面，暗色模式保持自适应对比。
- 历史详情恢复次级页面底色、独立描边卡片以及 header、截图、结果和 metrics 的确认层级。
- 不改变 Provider 请求、模型列表、Keychain、历史数据或截图行为。
- spec、feature catalog、design/review、实现、测试和当前 production renders 保持一致。

## Comments

- 2026-09-01: User reported five production regressions after installing and testing the current application.
- 2026-09-01: Existing confirmed prototypes remained the authority, so no new visual decision or prototype revision was required.
- 2026-09-01: Completed with one application-owned readiness flow, observable Provider input state, adaptive semantic secondary surfaces, and the confirmed history-detail card hierarchy.
- 2026-09-01: Strict build, 213 tests in 56 suites, 40 bilingual light/dark production renders, localization parity, static checks, three mutation checks, code review, test review, and final regression all passed.
