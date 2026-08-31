# 12 — Status item interactions

Status: completed

Blocked by: none

## Goal

让菜单栏状态项遵循 macOS 常见交互：左键打开主面板，右键只提供“退出 VLMSnapper”；同时保证主面板中的“截取屏幕”在满足前置条件时能够关闭面板并启动与全局快捷键相同的真实截图流程。

## Acceptance

- 左键继续打开或关闭菜单栏主面板。
- 右键显示原生上下文菜单，且菜单中只有本地化的“退出 VLMSnapper”。
- 主面板不再显示退出入口，更新检查仍保留。
- 右键退出复用应用级协调终止流程，不绕过活动截图、活动请求或未保存结果处理。
- Provider 未配置或截图权限未就绪时，点击“截取屏幕”保留面板并展示原有恢复界面。
- Provider 与权限均就绪时，点击“截取屏幕”先关闭面板，再调用与全局快捷键相同的截图入口。
- 生产交互、确认原型、spec、feature 与测试证据保持一致。

## Comments

- 2026-08-31: User confirmed the native right-click menu with only Quit and required the visible Capture Screen button to start capture, not just the global shortcut.
- 2026-08-31: Ticket 11 is reserved by the open coordinated-quit sheet repair, so this independent branch uses Ticket 12.
- 2026-08-31: Implemented with five focused interaction tests, strict warnings-as-errors build, 197 tests across 49 suites, bilingual localization checks, and inspected light/dark menu renders.
