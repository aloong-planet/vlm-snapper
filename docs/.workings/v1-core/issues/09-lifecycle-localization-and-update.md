# 09 — Lifecycle, localization, and update

Status: completed

Blocked by: none (02, 03, 06, and 07 completed)

## Goal

实现单主实例、诊断日志、本地化切换、登录项和 Sparkle 生命周期。

## Acceptance

- 第二实例不打开数据库、不注册快捷键、不清理或更新，只唤醒主实例。
- 诊断日志遵守脱敏 allowlist 并保留 7 天。
- 简体中文和英语 UI 完整，语言切换重启生效。
- 更新安装状态在实现前完成窄状态原型验收；自动检查固定 6 小时且可关闭，更新只能由用户显式开始下载。菜单栏与设置页只在 Sparkle 确认完成后显示“已下载”。

## Comments

- 2026-08-27: Confirmed prototype implemented. Sparkle 2.9.6 is isolated behind a product user driver; automatic checks use a fixed six-hour interval, automatic downloads stay disabled, and download/ready UI changes only from ordered Sparkle callbacks.
- 2026-08-27: Validation covers the real POSIX lease, typed seven-day diagnostics with valid gzip export, language resolution and explicit dictionaries, login-item approval mapping, update reply one-shot behavior, and 32 menu/settings renders across both languages and appearances. Signed-app lifecycle and appcast installation remain Ticket 10 gates.
