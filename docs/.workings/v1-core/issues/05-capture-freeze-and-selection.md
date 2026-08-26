# 05 — Capture freeze and selection

Status: blocked

Blocked by: 01

## Goal

实现 ScreenCaptureKit 多显示器冻结、矩形选区、原始 PNG 裁切和可配置全局快捷键。

## Acceptance

- 快捷键触发帧而非鼠标松开帧成为截图来源。
- 单屏失败不影响其他屏，全部失败与权限失败走不同恢复路径。
- 2 × 2 物理像素下限、显示器几何变化和新接入屏幕符合 ADR-0010。
- 保存与上传使用完全相同的 8-bit SDR sRGB PNG 字节。

## Comments
