# 05 — Capture freeze and selection

Status: completed

Blocked by: 01

## Goal

实现 ScreenCaptureKit 多显示器冻结、矩形选区、原始 PNG 裁切和可配置全局快捷键。

## Acceptance

- 快捷键触发帧而非鼠标松开帧成为截图来源。
- 单屏失败不影响其他屏，全部失败与权限失败走不同恢复路径。
- 2 × 2 物理像素下限、显示器几何变化和新接入屏幕符合 ADR-0010。
- 保存与上传使用完全相同的 8-bit SDR sRGB PNG 字节。

## Comments

- ScreenCaptureKit captures each discovered display independently at shortcut-trigger time; display disconnects, geometry changes and ordinary capture failures remain per-display outcomes, while permission denial is global.
- Selection state owns the frozen display set, enforces a `2 × 2` physical-pixel minimum, rejects changed geometry and releases every full-screen frame after completion or cancellation.
- The cropper emits exact-size 8-bit SDR sRGB PNG data. The resulting `Data` is the single byte object handed to later persistence and Provider seams.
- A narrow C shim owns Carbon registration and callback lifetime. Swift keeps validation, atomic replacement and MainActor delivery; coordinator destruction unregisters its active shortcut.
- Signed-app delivery, real shortcut conflicts, TCC recovery, multi-display hot-plug and trigger-frame visual timing remain Ticket 10 integration gates; no such live behavior is claimed from the SwiftPM host.
