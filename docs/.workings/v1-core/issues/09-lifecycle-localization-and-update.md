# 09 — Lifecycle, localization, and update

Status: blocked

Blocked by: 02, 03, 06, 07

## Goal

实现单主实例、诊断日志、本地化切换、登录项和 Sparkle 生命周期。

## Acceptance

- 第二实例不打开数据库、不注册快捷键、不清理或更新，只唤醒主实例。
- 诊断日志遵守脱敏 allowlist 并保留 7 天。
- 简体中文和英语 UI 完整，语言切换重启生效。
- 更新安装状态在实现前完成窄状态原型验收；6 小时检查与独立下载安装开关符合 spec。

## Comments
