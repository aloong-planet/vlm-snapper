# Instant capture overlay implementation tasklist

Base: `850f64d` (origin/main, 2026-10-28). Requirement source: the user asked
to remove the visible delay between the capture shortcut and the selection
overlay after comparing VLMSnapper with a static reverse-engineering report of
Snipaste 2.7.2; `docs/specs/v1-core.md` already requires the overlay to appear
immediately after the shortcut.

## Success criteria

1. After a capture is admitted, the selection overlay covers every display
   before the freeze finishes (application seam, held capturer).
2. A rectangle dragged before frozen frames arrive is completed against those
   frames once they arrive; the operation toolbar then appears.
3. `Esc` while frames are pending exits capture: no overlay, no toolbar, no
   history, the capture activity is released, and a reserved result workspace
   becomes usable again.
4. Freezing failure while a previous selection exists withdraws the pending
   overlay and restores the previous overlay and toolbar unchanged.
5. Termination preparation while frames are pending withdraws the overlay.
6. Existing capture regression tests stay green (replacement retirement,
   display invalidation, observer registration, termination, exclusivity).
7. Presenting the pending overlay costs a few milliseconds on the main thread
   and dragging no longer redraws the frozen frame on the CPU (measured with
   the production overlay controller).
8. Rendered overlay matches the existing appearance (scrim, border, 1:1 frozen
   pixels), checked from a rendering of the production controller.

## Tasks

- [x] Test design review recorded in `review-tests.md` before any test change.
- [x] Vertical slice 1: pending overlay before freeze completes (criteria 1, 6).
- [x] Vertical slice 2: selection made while pending completes after commit (criterion 2).
- [x] Vertical slice 3: `Esc` and termination while pending (criteria 3, 5).
- [x] Vertical slice 4: failed freeze restores previous selection and toolbar (criterion 4).
- [x] Overlay controller unit tests adapted to present/commit/rollback.
- [x] Targeted verification (build, affected tests, lint per gate).
- [x] Measurement and rendering evidence (criteria 7, 8), recorded in `measurements.md`.
- [ ] Step 5: `/review-code`, recorded in `review-code.md`.
- [ ] Full verification gate (pre-review run).
- [ ] Step 6: `/review-tests` post-implementation check.
- [ ] Spec final check; ADR, spec, CONTEXT, feature catalog updates.
- [ ] Full verification and delivery.

## Targeted verification (2026-10-28)

- Bug reproduction first red on unfixed code: `overlayCoversDisplaysBeforeFreezeCompletes`
  failed with `deadline` at the wait for an overlay while the capturer is held
  (provider setup had passed), then passed after the change.
- Strict build with CI flags (`-warnings-as-errors`, `-Wall -Wextra -Werror`): exit 0.
- `swift test --filter VLMSnapperUITests`: 77 Swift Testing tests and 29 XCTest cases passed.
- `swift test --filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu`: 27 tests passed.
- Affected-test search: `grep -rl "import VLMSnapperUI\|import VLMSnapperApp\|@testable import VLMSnapperApp" Tests`
  lists the `VLMSnapperUITests` files (run above), `ProviderApplicationTests.swift`
  (run above, plus its three `ProviderApplicationTestsNativeMenu` XCTest cases run
  one by one as CI does: all passed) and `Tests/AXFixture/main.swift`, an executable
  fixture that does not reference the overlay or toolbar and builds in the strict
  build. No test reads a changed configuration or data file.

## Fixture teardown flake (2026-10-28)

- Before the fix: 4 of 21 runs of `swift test --filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu`
  failed in `escapeWhileFreezingFromResultRestoresWorkspace` teardown (`waitForShortcutRelease` deadline);
  0 of 15 isolated runs of that test failed.
- Diagnosis (temporary instrumentation, not committed): the model stayed alive 35 s after the deadline, and
  `stopFixture` skipped the test's own result window as "pre-existing" because its `ObjectIdentifier` matched a
  window freed during the test. Root cause and fix are recorded in `review-code.md` (Runnability, finding 3).
- After the fix (strong references compared by identity): 0 of 20 runs of the same suite command failed.

## Spec final check (2026-10-28, code at `cb19ef2`, read-only)

| Spec unit (quoted) | Implementation | Verdict |
|---|---|---|
| v1-core::REQ-005/AC-01 “准入后立即在每块已连接显示器上显示与冻结后外观相同的选区遮罩，不等待冻结完成，不新增加载提示或文案；同时开始冻结各显示器” | `beginCapture` calls `presentPending` (one panel per `NSScreen`, same scrim) before awaiting `startCapture`; no new strings | Met |
| AC-02 “冻结帧在原遮罩中原位显示，不重建遮罩、不出现桌面闪烁；冻结帧与最终 PNG 不包含该遮罩” | `commit` attaches frames to the pending panels; new panels ordered in before old ones are hidden; freeze filter excludes the current process | Met (compositor part measured on macOS 26.0.1; 14.4–15 is the spec Pending) |
| AC-03 “冻结完成前遮罩接管鼠标与键盘，包括已拖出选区的透明内部……冻结帧显示后按冻结帧裁切” | pending panel made key; `ignoresMouseEvents = false`; drag released before a frame is completed in `attach` | Met |
| AC-04 “冻结完成前按 `Esc` 退出截图……迟到的冻结结果不重新打开选区” | `cancelCapture` → `abandonPendingCapture`; stale generation guard discards late results | Met |
| AC-05 “冻结失败、权限缺失、新遮罩无法覆盖任何显示器或请求失效时撤下待冻结遮罩，此前的选区遮罩、操作栏或结果工作区原样恢复” | `withdrawPendingCapture` (rollback + toolbar resume) on all four branches; workspace restore unchanged | Met |
| AC-06 “冻结完成时没有有效冻结帧的显示器……撤下其遮罩且不可选；冻结完成前新接入的显示器本次不可选” | `commit` retires pending panels without a valid frame; panels exist only for screens present at presentation | Met (multi-display path not testable on one display) |
| AC-07 “应用准备退出（含安装更新前）时撤下待冻结遮罩，不等待冻结完成” | `prepareForTermination` → `abandonPendingCapture`, no await on the freeze | Met |
| Solution, §3 entry bullet, §6 workspace bullet, FM-23, FM-25 (rewritten this round) | Same code paths as above | Consistent |

Unrecorded scope expansion: none in product code. The fixture identity fix is test infrastructure required to keep the new tests reliable; it changes no product behaviour.

## Post-implementation findings: evidence and records (2026-10-28)

- Item 6 (evidence): `native-thrown-operation-run.txt` keeps the command, version manifest, full output and exit code
  of the native cleanup case run; the targeted verification log of the fix is listed below once written.
- Item 7 (records): test design table and Dimension 1 table (`review-tests.md`), test-file header gaps, v1-core
  checklist rows REQ-005/AC-01/02/03/05/06 and `final-regression.md` updated in the same fix.
- Targeted verification of the fix (strict build, test build, App suite 29 tests, three native cases, all exit 0):
  `logs/targeted-findings-fix.log`. Pre-review gate run handed to the reviewer, kept as
  `logs/gate-pre-review-8bd52f2.log` (copy of the session-temporary original; fixture placeholder keys such as
  `openai-secret` in it come from the test sources).
- Incremental review decision: `node <implement skill>/change-scope.mjs --base 8bd52f2` exit 1, verdict `run`
  (`Tests/VLMSnapperAppTests/ProviderApplicationTests.swift` changed): `logs/change-scope-after-findings-fix.txt`.
- Incremental-round findings 9-11 (2026-10-28): run scripts kept in `logs/scripts/` (see `review-tests.md`, handling
  of findings 9-11, for how they differ from the versions behind the two earlier logs). A12 bug reproduction: red on
  `da94f5c` (deadline at the admission wait), green after the `cancelCapture` fix.
- Targeted verification of the findings 9-11 fix: `logs/targeted-findings-9-11.log` (all commands exit 0; App suite
  29 tests; three native cases passed). Incremental review decision: `logs/change-scope-after-findings-9-11.txt`
  (exit 1, verdict `run`).
- Finding 12 (records only): `logs/change-scope-after-finding-12.txt` exit 1, verdict `run`, caused solely by the
  user's pre-existing untracked `:-` (a codesign requirement string no test reads; not a test file or test data);
  every file this fix changed is `inert`, so no further incremental review is required.

## Full verification gate before delivery (2026-10-28)

- `logs/gate-full-4327bd6.log` (script `logs/scripts/gate.sh`): `Scripts/test-local-regression.sh --offline` at
  `4327bd6`, every stage PASS, exit 0 (strict build, script tests, checklist, shell syntax, non-app, app,
  native Paste, native closed-window, accessibility). Live Provider regression not run.
- After the run only this log copy and this note were committed (documentation). Reuse check below.
