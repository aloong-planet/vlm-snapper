# Code review — 2026-09-30

Scope is this turn's update-copy change, not the pre-existing extraction-to-translation diff.

- 【① 底层前提】The exact hint was referenced by both the switch and idle/current/checking status. Enumerated all update-state cases and both call sites. The switch remains its only view call site; its localization entries must remain.
- 【② 可运行性】Optional detail is conditionally rendered. No empty Text or extra VStack spacing remains below the status heading. Available, downloading, ready-to-install and failed still return their distinct details. No state transitions or callbacks changed.
- 【③ 安全正确性】No network, credentials, persistence, permissions or update-install behavior changed. No new error escape path.
- 【④ 一致性】Chinese/English and light/dark production renders inspected; status icon/title/button remain, duplicated hint is absent. Spec/features explicitly describe the copy rule. Prototype already has no duplicate automatic-check hint; other prototype status information is left unchanged. No icon/style/abstraction changes or unused-key deletion.

No blocking findings in this scoped review. Existing branch changes were neither reverted nor re-reviewed as part of this narrow request.

## 2026-09-30 — compact spacing follow-up

- 【① 底层前提】Native grouped Form supplies row insets; only the updateStatus-specific 8pt per-side padding is removed when the existing optional detail is absent. Prototype's compact current/checking states were explicitly accepted for App synchronization.
- 【② 可运行性】Release build succeeds. All seven update-state cases reviewed: idle/current/checking use compact spacing; available/downloading/ready/failed retain 8pt. The installed render is unverified because native CUA timed out after restart.
- 【③ 安全正确性】No callback, state transition, user-data, network or security behavior changed. Strict signed installation checks passed.
- 【④ 一致性】Spec/features describe compact single-line rows; prototype already reflects this. No new icon/color/string and no unrelated cleanup. Existing dirty branch preserved. Visual acceptance remains pending, not a code/build failure.
