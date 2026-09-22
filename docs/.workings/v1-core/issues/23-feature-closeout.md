# 23 — 收口:内联 Provider 配置完整验收与文档回归

**这是收口票。** 本 feature 的最后一张，承担全 feature 收口，不交付产品行为。

**Blocked by:** 19 — Manage Providers inline in Settings Center; 20 — Make Provider credential editing deterministic; 21 — Reconcile Provider credentials from Keychain truth; 22 — Make Provider credential work exclusive with capture and model requests; [25 — Complete History filtering in Management Center](25-history-filter-workflow.md).

**Status:** in-progress

## 需求来源与当前收口门禁

[v1-core spec](../../../specs/v1-core.md)；参考 commit：0febbb48fcd9acccdefc67dc9015ebf92605511c，含恢复的未提交改动和本轮需求细化。

2026-09-13：本票未完成。历史扩展筛选由已获建票批准的 [#25](25-history-filter-workflow.md) 负责实现与本票范围内回归，本票负责收口查证并依赖 #25 完成。#25 的交互细则与原型仍未确认，不能进入实现。既有编号不变；显示变化实机验收和 #24 整套测试红灯仍不能被局部验收抵扣。

## 流程验收

- [ ] 完整读取当前 spec 及同一份 [checklist](../checklist.md) 的“来源 → spec”“spec → tickets → 验证”“验证历史”“双向核对”，对当前 feature 全部有效规范性条件逐项查证；本轮 25 个单位只是增量，不是全 v1。
  — **Evidence**：每个完整需求 ID 对应的实现版本、用户路径、测试/门禁/实机证据及结论；当前未迁移的条件必须补齐，不能从旧章节级表推定完整覆盖。
- [ ] 核对每个条件的承兑票和实际结果，包含共享约束、跨票组合及明确回归责任；缺证据、原型未确认或实现缺口逐项保持未验收。
  — **Evidence**：checklist 的逐项核销记录；不得只引用组件名、票已关闭、测试总数或 58 行非空检查。
- [ ] 按 /features-catalog 完成 spec↔实现、实现↔features、ADR/CONTEXT/原型三类一致性回归；读取映射后再查证，不能只对文档措辞。
  — **Evidence**：final-regression.md 引用当轮 checklist 记录，标明源码 commit 和未提交差异；发现需求变化回到 /to-spec，不以实现反改需求消除缺口。
- [ ] 完成既有严格构建、完整 non-App/App/native 测试、本地化、原型/渲染及源码检查；保留首个失败，不降低断言或超时换绿。
  — **Gate**：每条命令退出状态与完整报告一致；#24 诊断记录不能豁免原生套件红灯。
- [ ] 独立执行 /review-code 与 /review-tests，完成收口全部未迁移条件后才重判本票状态。
  — **Evidence**：当轮独立审查记录；本次文档整理不构成代码或产品验收。

## 历史验收记录（下方旧条目保留原证据，不替代当前门禁）

- 2026-09-08 Refresh follow-up: approved compact prototype implemented in the native Provider card. Refresh progress is separate from credential phase; controls remain visible and disabled, ordinary network failure retains cache/selection and replaces model-help text, returning to a busy card preserves state. Core baseline reds reproduced phase/cache loss. Application callback/HTTP and native render coverage added; scoped review and evidence live in `../provider-refresh-tasklist.md`. Installed-app Refresh acceptance and full feature closeout remain open. No push, merge or installation performed.

- [ ] `/features-catalog` 的全 feature 收口通过 — **evidence**: record the three consistency passes for spec/implementation, implementation/features, and decision/prototype/terminology documents, including every discrepancy and its resolution.
- [ ] Current feature coverage is complete — **Evidence**: redeem the current full requirement-to-ticket-to-verification mapping above. Historical fact: the old 58-row structural parser and its six tests passed on 2026-09-09, but the later history-filter gap disproved treating that result as complete semantic coverage. That structural pass is retained, not promoted to acceptance.
- [x] The complete onboarding-to-Provider flow opens inline configuration, accepts a native-field key, validates exactly once, selects a model, persists recoverably, and returns to onboarding without using the retired standalone surface — **test**: `ProviderApplicationTests.nativeOnboardingValidatesSelectsAndReturns`; 2026-09-09 App suite passed. Programmatic native events and isolated external adapters, not a claim of physical input automation.
- [x] Provider validation/recovery and capture/model/rerun cannot interleave in the production composition, and blocked actions preserve existing capture, result, draft, and history state — **test**: `ProviderApplicationTests.credentialValidationAndFreezingExcludeEachOtherThroughApplicationWiring` and `nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive`; 2026-09-09 App suite passed, including delayed recovery and terminal release.
- [ ] Confirmed onboarding, Provider settings, capture toolbar, menu, and result surfaces remain visually consistent in both languages and appearances — **evidence**: inspect and record fresh production renders beside the confirmed prototypes, including normal and minimum Settings Center widths.
- [ ] Retired tasklists no longer act as parallel authority and all surviving implementation/review evidence names Tickets 19–23 consistently — **evidence**: record the repository-wide search commands and results for the retired tasklist names and stale standalone Provider terminology.
- [ ] Strict warnings-as-errors build, full test suite, localization parity, prototype syntax, render contracts, source/literal checks, and `git diff --check` all pass together after the four behavior tickets — **gate**: the repository's full closeout command set fails non-zero on any member failure.

## Comments

- 2026-09-09 display follow-up: the previously missing production display notification wiring is implemented with per-display invalidation and post-registration revalidation. Strict build, 333 non-App and 14 App tests pass; native lifecycle reports 3 tests / 1 failure at the #24 key-window acquisition wait (before Paste). Hardware display-change acceptance, Provider icon parity and the remaining full-feature closeout checks are not waived. See `../display-reconfiguration-tasklist.md`; no publication or installation.

- 2026-09-09 closeout in progress: the user accepted installed-App interaction/visual checks and asked to record the unconfirmed focus issue before closeout. Remaining key-window/toolbar deadline diagnostics now have a separate local Ticket 24; the distinct teardown correction is not their proven fix. FM-43's ownership mirror and the retired Provider-sheet wording were corrected, and distribution details were removed from the user-feature catalog without waiving Ticket 10's release gates. The live display-reconfiguration follow-up remains a production gap against US-03/ADR-0010, so full feature acceptance and this ticket remain open. Provider icon parity also awaits an explicit decision. Current work is tracked in `../23-closeout-tasklist.md`.

- 2026-09-08 test-owned lifetime correction: both fixture owners now detach only their new native windows after stop and await weak external-adapter release in a real MainActor Task, preserving cancellation and cleanup errors. Production isolated cleanup is unchanged. Final-code alternating regression completed 10/10 App suites (11 tests each) and 10/10 same-process native suites (3 methods each), 140 executions with completion-report and exit-code checks. Review rejected two earlier exit-0 incomplete App runs, traced the new nested-RunLoop interaction, and removed it from the cleanup poll; CI now rejects incomplete reports. Forced-retention ordinary/cancelled controls fail at the intended bounded cleanup. This addresses the demonstrated teardown crash locally, not the still-unproven historical key-window/toolbar deadlines or full feature closeout. Evidence: `../native-lifetime-tasklist.md` and `../native-flake-diagnosis.md`. No installation or publication.

- 2026-09-08 teardown minimization: reproduced the invalid-free/SIGABRT independently of XCTest/UI with the unchanged shortcut coordinator (3/3), then an empty isolated deinitializer (3/3), under synchronous TaskLocal with no current Swift Task. Moving release into a real Task passed 3/3 for both types; removing TaskLocal or using ordinary deinit also passed 3/3; raising only the deployment target still crashed. LLDB frames match the earlier teardown reports and Swift's no-task TaskLocal marker allocation fix. This isolates the teardown mechanism, not the historical window deadlines. Next is a separately verified test-lifetime correction; no production fix or ticket closure. Reproducer and controls: `../native-flake-diagnosis.md`.

- 2026-09-08 diagnostic follow-up: added bounded test-only state traces at Paste/key-window and capture/toolbar waits. Five rebuilt runs each passed; two temporary fault injections hit their intended waits and were removed; restored Paste/capture/closed-window and 11 App tests passed. Paste's injected timeout additionally exposed a teardown SIGABRT whose key deinitializer/runtime frames match two earlier crash reports. This is a separate recurring crash signature, not the historical deadline's proven cause. Continue minimization under this ticket; see `../native-flake-diagnosis.md` for logs, scoped review, privacy and observer-effect limits. No production fix or closure claimed.

- 2026-09-08 native stability investigation: current Paste and capture cases each passed ten independent runs; three App→Paste sequences and one non-App→App→Paste sequence also passed. Temporarily replaying the historical unpumped drag passed three times, then was exactly restored and rebuilt. Neither original deadline was reproduced, so no root cause or fix is claimed. Stability remains open; scoped logs, evidence limits and next failure diagnostics are recorded in `../native-flake-diagnosis.md`.

- 2026-09-08: User accepted installed build 28 VA-01–04 on the real app. This closes that scoped manual review, not the remaining Ticket 23 criteria. User then approved VA-05's English copy-only change to `Version %@ available`. The shared menu/General Settings title now uses it; Chinese and 300-point menu geometry are unchanged. Six focused localization/render tests passed; fresh English light/dark 300-point menu images display `Version 1.1.0 available` without truncation, and the General Settings light render was inspected. These are native render evidence for the sample version, not an arbitrary-version-length guarantee. The copy change is not yet installed or published.

- 2026-09-08 VA-01–04 follow-up: user-approved visual corrections are implemented and source-contract/native-render checked; see `../visual-alignment-tasklist.md` and the audit follow-up. Strict build, 333 non-App and 11 App tests pass; isolated closed-window completion passes; menu Paste initially timed out before key-window acquisition, then passed unchanged independently. Keep the native stability caveat with this ticket, not a relaxed test or inferred product root cause. VA-05, Provider icon choice and full feature visual/physical acceptance remain open. No installed-app update or release.

- 2026-09-08 visual audit after merge #27: inspected 52 fresh bilingual/light-dark native renders from `0febbb4`, including normal/minimum management widths. Onboarding composition, Provider model geometry/footer styling and Chinese History filter label still differ from confirmed prototype source; English menu update title truncates. Findings and evidence limits are recorded in `../23-visual-audit.md`. Browser URL policy blocked actual HTML render comparison; no workaround used. These differences and remaining actual-window/scroll-state checks stay owned by this ticket. Visual consistency and full-feature closeout remain unchecked; no implementation changed in this audit.

- 2026-09-08: User confirmed installed build 27 Refresh acceptance and explicitly requested push and merge of the current work. Publish the accepted application-test wiring and Refresh follow-up incrementally; keep this ticket in-progress. Full-feature visual consistency (including the unresolved Provider icon choice), remaining failure/cancellation coverage and document reconciliation are not waived. No release or tag requested.

- 2026-09-08: User identified excessive whitespace in Refresh A and approved reusing the existing model-help row for inline errors. Prototype now shares a content-sized row between help/error text instead of adding a separate fixed-height empty block; Refresh button geometry is unchanged. Native implementation is still untouched. Static checks do not establish visual acceptance; the revised render still needs user confirmation because browser URL policy prevented automated preview.

- 2026-09-08: User confirmed the six installed-app manual checks (native paste/validation, replacement key/model selection, closed-window response and reconstruction, capture admission during validation, capture/rerun history identity, result backgrounding and Quit). This is scoped manual acceptance, not completion of every closeout criterion. A new Refresh layout defect remains: operation feedback inserts/removes controls. User selected presentation A: preserve controls and geometry, show progress inside a fixed-size Refresh button, disable conflicting submissions without hiding them, keep credential status separate, preserve cached models/selection on ordinary network failure, and reserve inline failure feedback space. Prototype updated only; native implementation and visual confirmation remain pending. Browser preview was denied by the browser URL policy; static JavaScript syntax and diff checks passed, but these are not render evidence. Existing prototype letter-icon discrepancy remains assigned to the visual consistency criterion above.

- 2026-09-08: Added independent-process native main-menu Paste/Validate and successful-response-while-Settings-remains-closed cases. Both have reached target mutations and explicit restored completion reports. Same-process native runner aborts and incomplete reports are rejected. Full regression additionally exposed a capture/toolbar timing-sensitive failure; stability remains open. See the new tasklist entry; no full-ticket gate or physical-input acceptance is claimed.

- 2026-09-08: Added actual Validate-button and close/reopen-before-response coverage, with preserved candidate/read-only/no duplicate request and durable reconstruction. Candidate-loss mutation reached and failed its intended wait; restored. Strict build plus 336 Swift tests and six checklist tests passed. Main-menu Paste and completion while remaining closed are still Pending: rejected key-window/terminal-observation probes are recorded separately, not counted as acceptance. Full ticket status remains in-progress.

- 2026-09-08: Added same-Model native selection/toolbar/image/rerun and recovery-wait composition coverage, including nonempty history preservation and successful replacement retaining the history ID. Disconnected-rerun and missing-recovery-wakeup mutations both failed at their intended waits, then were restored. Strict build, 335 Swift tests and six checklist tests passed. Full acceptance remains open for remaining native failure/cancellation branches, physical/bilingual visual checks and feature-wide reconciliation; see the dated tasklist evidence.

- 2026-09-07: Added real-delegate startup/cleanup and a combined native onboarding → secure input/Return → validate → close/reopen → model menu → return → reconstruction case. Added application-wiring validation/freezing exclusion in both directions. These are partial acceptance: model/rerun/recovery-wait and additional native failure branches remain open; the full acceptance checkboxes above are intentionally unchanged. Scoped evidence and review records are in the Ticket 23 tasklist.

- 2026-09-07: Started on `codex/ticket-23-provider-feature-closeout` from merged PR #26 (`af4ffcd`); `git log origin/main..HEAD` was empty. Plan and acceptance boundaries are recorded in `../23-feature-closeout-tasklist.md`. No full-feature acceptance is claimed by starting this ticket.

- 2026-09-05: This closeout ticket explicitly prevents the retrospectively ticketed drafts from being treated as complete merely because prior tasklists were checked.

- 2026-09-06 Ticket 20 scoped review: the management-center visual demo uses DS/OA/G letter marks while native UI uses the existing symbol anchor. These pre-existing marks are outside the editor fix. Include this in the full visual consistency check; ask for an icon choice before replacing it, do not silently copy letter marks into native UI. The same prototype's old API Key trim/dirty/lifetime simulation is now explicitly marked non-authoritative; layout remains confirmed.

- 2026-09-07 Ticket 22 handoff: shared production admission, real SQLite rerun and programmatic AppKit blocked/terminal controls are covered. Combined installed-app acceptance must still verify physical shortcut/menu delivery, the active Provider window actually foregrounding, and an unsaved result actually foregrounding without screen freezing. The native adapter's unsaved-result fronting omission was restored during review; its session preparation test is not OS-focus evidence. Do not infer these results from lower-level callbacks or the earlier Ticket 21 preview acceptance.

- 2026-09-09 Provider marks: user explicitly selected prototype parity. Settings
  Center now uses DS/OA/G in the approved theme-specific rounded tiles; generic
  action/navigation symbols unchanged. Spec/features synchronized; fresh native
  render samples inspected. Strict build and 333 non-App tests pass. App suite
  13/14 passed with the existing toolbar-wait boundary timing out; recorded in
  Ticket 24. Browser/installed acceptance unavailable while Mac locked. The
  identity-choice question is resolved, not the full-feature acceptance gate.

- 2026-09-09 continuation after installed build 29 acceptance: the user accepted the Provider identity marks; the earlier locked-Mac limitation no longer leaves that scoped manual check open. No claim is made for unrelated display hardware or failure paths. Current production display notifications and session invalidation callers were verified; hardware acceptance remains outstanding.
- Full-feature semantic reconciliation found an unresolved US-10 discrepancy: status, Provider, model, target-language and date filters exist in the query layer but not in the native management-center workflow or confirmed prototype. Ownership was made explicit under #23; see `../23-history-filter-audit.md`. Keep this ticket in-progress. Recommend prototype alignment followed by native wiring and exclusion/control-level tests; wait for the user's UI/scope decision instead of silently dropping the requirement.
- This continuation is a partial closeout audit, not final code/test review or completion of all 58 acceptance rows. The ownership parser's six tests and 58-row check pass, but do not establish semantic completeness. No install, commit, push, PR, merge or release.

- 2026-09-13：用户“ok，新增#25”批准独立历史筛选票；新增 #25 阻塞边。设计门禁未解除，17 个对应单位尚未验收，本票继续 in-progress；未重编号或关闭其它票。
