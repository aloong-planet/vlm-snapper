# 07 — Menu, onboarding, and Provider UI

Status: completed

Blocked by: 03, 05, 06

## Goal

按已确认原型实现菜单栏第一入口、首次引导、Provider 配置附着面板和权限恢复。

## Acceptance

- 两个必要条件正确阻断开始使用，“稍后完成”始终可用。
- Provider 验证成功后原地展开模型选择，不跳页。
- 权限被撤销状态在实现前完成窄状态原型验收。
- UI 文案全部来自简体中文/英语本地化资源。

## Comments

- 2026-08-27: Dependencies 03, 05, and 06 are complete.
- 2026-08-27: Permission recovery Direction A selected: one reusable recovery panel for onboarding and the menu-bar capture entry.
- 2026-08-27: Implemented menu-bar routing, onboarding readiness, attached Provider/privacy/permission panels, explicit-only TCC recovery, and zh-Hans/en UI. Strict build and 143/143 tests pass; 10 light/dark render artifacts were inspected.
