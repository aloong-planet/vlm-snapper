# 06 — Operation and result UI

Status: blocked

Blocked by: 02, 04, 05

## Goal

按已确认原型实现选区操作栏、提取/翻译工作流、流式结果、单活动任务、取消和重新执行。

## Acceptance

- UI 常量和布局匹配已确认操作栏与结果原型。
- 操作切换不自动请求；每个显式动作恰好一个请求。
- 重新执行只在新成功后覆盖旧成功结果。
- 关闭请求中窗口产生已取消，完成后关闭只隐藏。

## Comments
