# Live display reconfiguration during selection

本票保留原文件名；同目录另有编号 01 的持久化票，引用本票必须使用完整文件链接，不能只写“#01”。

Status: in-progress

Blocked by: none

## Problem

Originally, `CaptureSelectionSession.applyCurrentDisplayGeometries(_:)` had no production caller, so display changes were detected only when selection finished. Production now revalidates before overlay presentation and observes AppKit display/sleep notifications during selection. The remaining acceptance gap is actual hardware behavior, not missing notification wiring.

## Impact

Before the correction, the frozen frame could remain visible until mouse-up. Current per-display invalidation is exercised through injected notifications, but real hot-plug, scale/rotation/arrangement changes, sleep/wake and survivor focus still need acceptance. This is separate from the Retina downsampling repair and the #24 native-test waits.

## Recommendation

Accept the implemented AppKit notification path on real displays: refresh the complete geometry set, retire only affected frozen displays, and verify observer cleanup on completion/cancel. Do not replace it with the original raw CoreGraphics proposal merely because that proposal remains in historical comments.

## 需求来源

[v1-core spec](../../../specs/v1-core.md)；参考 commit：0febbb48fcd9acccdefc67dc9015ebf92605511c，包含恢复的未提交显示监听改动及本轮 spec 细化。
旧的四条复合条件迁移为下列八项；保留 Comments 中的历史结果，不沿用为当前硬件通过。

## 产品验收

- [ ] v1-core::REQ-001/AC-01 — 选区期间已冻结显示器断开时立即使该屏不可选并撤下其遮罩、释放其冻结帧，不等待鼠标松开。
  — **Evidence：安装版双屏选区拖拽中拔除所在屏，鼠标尚未松开时遮罩失效；记录系统、屏幕配置、App commit 与观察。Test：复用真实应用注入显示通知用例。**
- [ ] v1-core::REQ-001/AC-02 — 选区期间显示器分辨率、缩放、旋转或几何布局变化时只使受影响屏幕失效，并取消其当前拖拽，不重新捕获实时画面。
  — **Evidence：安装版分别改变分辨率、缩放、旋转、排列，观察仅受影响屏取消拖拽且不抓新帧。Test：注入对应几何变化驱动生产遮罩。**
- [ ] v1-core::REQ-001/AC-03 — 已冻结显示器休眠时使其失效；唤醒不恢复本次已经失效的冻结帧。
  — **Evidence：安装版选区中休眠/唤醒，已失效帧不恢复；Test：真实应用休眠通知路径。不能把整机锁屏下测试超时当作合格结果。**
- [ ] v1-core::REQ-001/AC-04 — 部分屏幕失效后，未变化的成功冻结屏幕仍可继续选择。
  — **Evidence：双屏一屏失效后在幸存屏完成选择；全部失效后选区结束、历史无新增。Test：应用组合分别验证部分/全部失效。**
- [ ] v1-core::REQ-001/AC-05 — 本次选择开始后新接入的显示器不可选，下一次显式截图才纳入新的冻结集合。
  — **Evidence：选区中新接屏本次不可选，退出后显式新截图可选；Test：应用通知路径相同前后状态。**
- [ ] v1-core::REQ-001/AC-06 — 冻结完成后和监听注册后均核对完整几何，注册前的异步间隙发生的变化不能遗漏。
  — **Test：复用 displayChangeBetweenFreezeValidationAndObserverRegistrationIsNotLost，经生产装配把变化插入监听注册间隙，断言失效遮罩不发布。**
- [ ] v1-core::REQ-001/AC-07 — 取消、替换选区和裁切完成后解除旧监听；迟到通知不能撤下或改变新会话的遮罩。
  — **Test：复用 replacementAndEscapeRetireDisplaySubscriptions，并覆盖裁切完成/旧代次迟到通知；断言新会话遮罩不受影响及旧订阅释放。**

- [ ] v1-core::REQ-001/AC-08 — 全部冻结屏幕失效时结束选区且不创建历史。
  — **Test**：应用组合使全部屏失效，断言遮罩关闭且历史无新增；**Evidence**：实际显示器全部失效的独立验收记录。

## 流程验收

- [ ] 对照 [checklist](../checklist.md) 同标识记录 App/spec commit、未提交内容、实际路径与证据；真实显示变更和注入通知分列。
  — **Evidence**：安装版测试配置、动作与可观察结果；不能只写“通过”。
- [ ] 如复测暴露原生等待故障，保留首次失败并归入 [#24](24-native-test-wait-timeouts.md)；不要重跑到绿代替解释。
  — **Gate**：退出码与完整测试报告一致；依 /review-tests 审查验证边界。

## Comments

- 2026-09-09 implementation checkpoint: production now uses `NSApplication.didChangeScreenParametersNotification` and `NSWorkspace.screensDidSleepNotification`, with complete active geometry reads, per-display panel retirement, session/generation checks and observer cleanup. The OS-level AppKit notification replaces the earlier suggested raw CoreGraphics callback; the accepted per-display behavior is unchanged. A second read immediately after registration covers the intervening actor hop. Five injected change cases, a registration-gap case, replacement/Escape/termination and post-crop cleanup pass through the real application composition. Original missing-sleep wiring and the registration gap were red before their fixes; disconnect/geometry forwarding mutation also fails at visible-overlay assertions.
- Validation: strict build and 333 non-App + 14 App tests pass. The full native suite fails at the separately tracked #24 key-window wait; no retry was used to convert that gate to green. Hardware hot-plug, display-settings changes and two-display survivor/focus acceptance remain pending. Implementation is ready for that acceptance, not a claim that this ticket or #23 is fully closed. No install/push/merge. Evidence and review: `../display-reconfiguration-tasklist.md` and the dated review/regression entries.

- 2026-09-09 Ticket 23 closeout: the gap remains current. Full production-source search finds `applyCurrentDisplayGeometries` only at its declaration, with callers in `CaptureSelectionSessionTests`; no production display-reconfiguration observer is connected. US-03 and ADR-0010 still require invalidation during selection, not only a geometry check when selection finishes. This remains a full-feature acceptance blocker; it has not been waived or folded into the unrelated native test-focus investigation.

- Recorded while reviewing the Retina frozen-capture repair. Kept separate because it predates and does not cause the downsampling bug.
