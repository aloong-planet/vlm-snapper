# 06 — Operation and result UI

Status: completed

Blocked by: 02, 04, 05

## Goal

按已确认原型实现选区操作栏、提取/翻译工作流、流式结果、单活动任务、取消和重新执行。

## Acceptance

- UI 常量和布局匹配已确认操作栏与结果原型。
- 操作切换不自动请求；每个显式动作恰好一个请求。
- 重新执行只在新成功后覆盖旧成功结果。
- 关闭请求中窗口产生已取消，完成后关闭只隐藏。

## Comments

- Implemented the confirmed compact capture toolbar and two-card result workspace as native SwiftUI/AppKit components.
- Added an application-wide activity lease, explicit-only Extract/Translate starts, retained-success reruns, cancellation, unsaved-result confirmation and save-only retry.
- Migrated history schema v1 to v2 with typed operation and translation target fields.
- Verified strict Swift/C compilation and 127 Swift tests; signed-app accessibility, TCC and packaged window behavior remain Ticket 10 gates.
