# Instant capture overlay test review

Scope: capture shortcut latency fix (pending overlay before freeze completion).
No ticket; records follow the no-ticket entry of the ticket-artifact rules.
Project has no `capabilities.toml` (项目无能力声明文件); `working-language` and
`mutation-testing` are unconfirmed (未确认). This record follows the English
precedent of earlier `docs/.workings/` records. No mutation check has been run
as a capability; the decision is the user's (post-implementation finding 2).
Red runs recorded below (the bug reproduction in A1 and the real-event
click-through reproduction) are TDD and review evidence, not a mutation check.

## Design review

Date: 2026-10-28. Implementation basis: `850f64d`. Range: tests planned for
`Tests/VLMSnapperAppTests/ProviderApplicationTests.swift` (application
composition seam) and `Tests/VLMSnapperUITests/FrozenCaptureOverlayControllerTests.swift`
(overlay controller seam).

Spec items are `v1-core::REQ-005/AC-01–07` in `docs/specs/v1-core.md`. The
first version of this table used provisional labels `REQ-003/AC-01–05` before
the identifier was allocated (`REQ-003` is the interface-language requirement
and `REQ-004` is used by an open branch); increment of 2026-10-28 (after
post-implementation finding 3) rewrote every spec cell against REQ-005:
AC-01 overlay before freeze on every display, AC-02 frame in the same window
without flash and excluded from the frame, AC-03 input ownership while
pending, AC-04 `Esc` while pending, AC-05 rollback on failure or invalidated
request, AC-06 displays without a frame, AC-07 termination while pending.

### Test design table

| ID | Test | Spec items | Seam | Input that reaches the target branch | Assertion objects and expected-value source | Fixture shape source | Expensive resources |
|---|---|---|---|---|---|---|---|
| A1 | `overlayCoversDisplaysBeforeFreezeCompletes` (new; increment 2026-10-28 for findings 3 and 6) | REQ-005/AC-01, AC-02 (same window); FM-25 (source retirement after the frame); Further Notes performance target | Application model + real overlay controller | `FixtureCapture.holdFrames()` keeps `captureFrozenDisplays` suspended after admission; shortcut fired | While held: a visible `.screenSaver` window exists, `capture.requests == 1`, and the rendered overlay is translucent (no frozen frame). After release: the same window object renders the opaque frozen frame. Increment: while held, every `NSScreen` has a visible pending overlay (one display on the test machine, every display on multi-display runs) and the model's public `onRetireCaptureSources` hook, which production wiring uses to hide the menu panel, management center and onboarding, has not been called; after the frame it has been called once. Expected values from AC-01 (immediate overlay on every display, frozen frame later, no window rebuild) and FM-25 (sources retired only after the frame) | `syntheticDisplay()`: real `NSScreen.main` geometry with a white frame of the real pixel size | None (fixture plus model start measured at 0.3-0.45 s per test) |
| A2 | `selectionDraggedWhileFreezingCompletesWithFrozenFrames` (new) | REQ-005/AC-03 (rectangle completed before the frame); §3 rectangle selection | Same | Held capture; production `drag` helper sends down/drag/up to the pending overlay before release | No toolbar while held; toolbar window appears after release. Expected from AC-02 (selection kept, cropped from frozen frame) | Same | None |
| A3 | `escapeWhileFreezingExitsCapture` (new; increment 2026-10-28 for finding 4a) | REQ-005/AC-03 (keyboard), AC-04; §3 `Esc` exits without saving | Same | Held capture; increment: `Esc` delivered through `NSApp.sendEvent`, which routes keys to the application's key window, instead of directly to the overlay; capture released afterwards | Increment: the pending overlay is the key window before `Esc`. Overlay not visible after `Esc`; after release no `.screenSaver` window and no toolbar reappear, activity becomes `nil`, history empty, no image request. Expected from AC-03 and §3 | Same | None |
| A4 | `failedFreezeRestoresPreviousSelection` (new; increment 2026-10-28 for finding 6) | REQ-005/AC-05 (permission missing); FM-3; FM-25 | Same | First capture completes and a drag shows the toolbar; then `provide(nil)` plus `allowSuspendedCapture()` makes the next capture wait and throw `permissionDenied`; shortcut fired | While pending: previous overlay hidden, a different overlay visible, toolbar hidden. After release: pending overlay gone, previous overlay visible with content, toolbar visible again, activity still `.capture`. Increment: `onRetireCaptureSources` is called once for the first (committed) capture and not again for the failed one. Expected from FM-3 (keep previous selection, no half-retired state) and FM-25 | Same; failure shape is the existing `permissionDenied` path of `FixtureCapture` | None |
| A5 | `terminationWhileFreezingWithdrawsOverlay` (new) | REQ-005/AC-07; FM-18 | Same | Held capture; `model.prepareForTermination()` called while held; capture released afterwards | `prepareForTermination` returns `true` while the freeze is still held (it does not wait for the freeze); no visible `.screenSaver` window immediately afterwards; history empty. The late-result discard after release is not asserted here: termination preparation cancels activity observation, so the stale-result guard it shares with `Esc` is asserted by A3 (increment reviewed 2026-10-28) | Same | None |
| A6 | `escapeWhileReplacingSelectionReleasesActivity` (new) | REQ-005/AC-04; FM-25 lease ownership | Same | First capture committed with toolbar; second shortcut with held capture; `Esc` on the pending overlay | All overlays and the toolbar hidden; activity eventually `nil` (the shared lease is released). Increment 2026-10-28 (finding 7): "exactly once" removed; the assertions show release, not its count. Expected from AC-04 | Same | None |
| A7 | `escapeWhileFreezingFromResultRestoresWorkspace` (new) | REQ-005/AC-04; FM-23 | Same | Full capture to terminal result (existing image-flow pattern); held capture; shortcut from the terminal workspace; `Esc` on pending overlay; release | Result window stays visible; a further shortcut is admitted and freezes (`capture.requests == 3`, overlay shown). A workspace still reserved for the abandoned capture answers `alreadyPrepared` and refuses that capture, so admission is the public observable of the restored reservation. Expected from AC-03 and FM-23 (workspace stays usable when capture is abandoned). Increment reviewed 2026-10-28: the first design clicked `Try Again`; a control run without any capture showed that clicking it immediately after the first result never starts a request in this fixture (fixed click coordinates against a result window still settling), so that click could not distinguish restored from reserved | Same plus existing DeepSeek SSE fixture shape (`FixtureHTTP.finishImage`) | None |
| A8 | `replacementAndEscapeRetireDisplaySubscriptions` (modified) | REQ-001/AC-07; FM-25 | Same | Existing input; waits additionally until the new overlay renders its frozen frame before checking retirement and subscriptions | Existing assertions unchanged (previous overlay retired, one display read per notification while subscribed, none after `Esc`/termination) | Existing | None |
| A9 | `displayChangesCancelSelectionBeforeMouseUp` (modified) | REQ-001/AC-01-03 | Same | Existing input; waits for the frozen frame before posting display changes | Existing assertions unchanged | Existing | None |
| A10 | `nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive` (modified, increment reviewed 2026-10-28) | §3; FM-23; REQ-005/AC-03 | Same | Existing input; the overlay to drag is the one on `NSScreen.main` (the screen the synthetic display freezes) instead of the first visible overlay | Existing assertions unchanged. Reason: with pending panels on every screen, the first visible overlay can belong to a screen without a frame on multi-display machines; the drag may now reach the pending panel before commit, which is the AC-02 path | Existing | None |
| A11 | `selectionStartedBeforeFramesFinishesAfterThem` (new; increment 2026-10-28 for findings 4b and 9) | REQ-005/AC-03 (rectangle begun before the frame, finished after it); §4 toolbar left-aligned with the selection | Application model + real overlay controller | Held capture; mouse down at (300, 300) and drag to (400, 400) on the pending overlay; capture released; wait for the rendered frozen frame; drag on to (150, 400), which moves the selection's left edge; mouse up there | No toolbar before mouse up; after it, the toolbar's left edge equals the final selection's left edge (overlay x + 150, within 1 pt). A selection completed when the frame arrived would anchor the toolbar at x + 300 and the later mouse up would be refused. Expected from AC-03 and §4 (toolbar left-aligned with the selection) | `syntheticDisplay()` | None |
| A12 | `displayChangeWhileReplacingAbandonsPendingCapture` (new; increment 2026-10-28 for findings 5 and 10; bug reproduction, must fail first) | REQ-005/AC-01 (an admitted shortcut shows the overlay), AC-05 (request invalidated); REQ-001/AC-01-02 | Same | First capture committed without a drag; held second capture; geometry change plus notification ends the first selection and releases the shared activity; geometry restored; one further shortcut while the second capture is still held; then release of both held captures | After the change: no overlay and activity `nil`. The single further shortcut is admitted at once (`capture.requests == 3`, a pending overlay on the main screen) although the second capture's freeze has not returned. After release the third capture's frozen frame appears in the same overlay window, which is visible when that frame is first seen. These last checks are read once, when the frame appears; they are not ordered after the stale second result (nothing observable marks its handling), so they catch the stale result closing or replacing the third overlay only when it is handled first, which the resume order usually but not necessarily produces (increment 2026-10-28, finding 12). Expected from AC-01 (admission shows the overlay) and AC-05 | `syntheticDisplay()` plus `changedGeometry`; `FixtureCapture` holds several suspended captures and releases them together | None |
| U1 | `failedReplacementKeepsCurrentOverlay` (modified) | FM-3; REQ-005/AC-05 | Overlay controller | Present and commit one display; present pending; `commit(displays: [])` | Commit returns `false`; after `rollback()` the previous window is visible and `presentedDisplayIDs` unchanged | Existing `makeDisplay` (real `NSScreen` identity) | None |
| U2 | `failureAlertStaysAboveRetainedOverlay` (modified) | FM-3 | Overlay controller | Present and commit one display; prepare alert | Alert level above `.screenSaver` (existing expectation) | Existing | None |

Rendered-frame observable used by A1, A8, A9: render the overlay content
view's layer tree into a small bitmap and read the alpha at the centre. A
pending overlay over the live screen is translucent (scrim only); a committed
overlay shows the opaque frozen frame. This reads what the user sees, not
controller state, and its negative case is asserted in A1.

### Dimension 1: Coverage

Rewritten against `v1-core::REQ-005` in the increment of 2026-10-28
(findings 3, 4, 5, 6, 7).

| Spec boundary | Planned coverage |
|---|---|
| AC-01 overlay before the freeze, on every connected display | A1 (every `NSScreen` checked; multi-display runs exercise more than one) |
| AC-02 frozen frame in the same window | A1 |
| AC-02 no desktop flash between old and new overlays | Gap: the ordering happens inside one main-thread call and is not observable in process. Re-test condition: screen recording of the installed app while retriggering |
| AC-02 frame and PNG exclude the overlay | Gap: compositor (signed app); supplementary in-process measurement in `measurements.md` |
| AC-03 keyboard owned by the pending overlay | A3 (key window asserted, `Esc` routed through the application) |
| AC-03 clicks inside a clear selection stay on the overlay | Gap: window-server hit testing; reproduced and fixed with posted HID events (`review-code.md`) |
| AC-03 rectangle completed before the frame | A2 |
| AC-03 rectangle begun before the frame, finished after it | A11 |
| AC-04 `Esc` while pending, fresh capture | A3 |
| AC-04 `Esc` while pending, replacing a selection | A6 |
| AC-04 `Esc` while pending, replacing a terminal result workspace (FM-23) | A7 |
| AC-04 late freeze result after `Esc` is discarded | A3, A7 (both wait for `activity == nil`, produced only after the late result was handled) |
| AC-05 permission missing; previous overlay and toolbar restored (FM-3) | A4, U1 |
| AC-05 request invalidated (previous selection ended by a display change while pending) | A12 |
| AC-05 freeze failure or new overlay covers no display | Gap: modal capture-failure alert (`runModal`) blocks the composition test; already untested before this change. Re-test condition: a non-modal failure presentation seam or a signed-app manual check |
| AC-06 display without a valid frame withdrawn while another commits | Gap: needs two displays; U1 covers the all-missing case |
| AC-06 display connected while pending is not selectable | Gap: needs hot-plug during the freeze. Re-test condition: hardware acceptance with REQ-001's display checks |
| AC-07 termination while pending (FM-18) | A5 |
| FM-25 sources retired only after the frame, not on failure | A1, A4 (public `onRetireCaptureSources` hook; the delegate's wiring of that hook is unchanged by this change) |
| FM-25 shared lease | A6 |
| Display changes after commit (REQ-001) | A8, A9 plus unchanged existing tests |

The gaps are written in the header of the modified test file.

Fixture independence: frozen frames are external ScreenCaptureKit data. The
fixture reproduces the real shape (one `CGImage` per display at the real
`NSScreen` pixel geometry), taken from the live screen rather than invented.
Failure shapes reuse the capturer's real error type (`CaptureDiscoveryError`).

Conclusion: every REQ-005 boundary has a case or a recorded,
environment-bound gap with a re-test condition.

### Dimension 2: Case design

- Every case drives the production shortcut handler, production overlay
  panels, production key/mouse event delivery and the real application model;
  only the capturer, display reads, HTTP and credentials are fixtures, as the
  spec's testing decisions require.
- Assertions read window visibility, the rendered overlay, toolbar windows,
  the published activity snapshot, history through the model, and recorded
  HTTP requests. None reads controller or model private state.
- No case constructs a state the public path cannot reach: the held capture is
  a real suspension inside the capturer protocol the production model awaits.

Conclusion: no finding.

### Dimension 3: False greens (design-time checks)

- Vacuous assertions: the rendered-alpha check separates 0.48 (scrim only)
  from 1.0 (frozen frame); A1 asserts both sides so the helper is shown to
  return `false` as well as `true`.
- Tautologies: expected values come from the spec acceptance criteria and
  observable windows; no case imports the scrim constant or recomputes the
  implementation.
- Stale paths: the removed `replace(displays:onSelection:onCancel:)` entry is
  not asserted anywhere after the change; U1/U2 move to the live
  present/commit/rollback API.

Conclusion: no finding at design time.

### Dimension 4: Resource reuse

Measured on `850f64d`: the existing composition tests take 0.3-0.45 s each
including `ApplicationFixture` creation and `model.start()`. No resource in the
table reaches the 1 s threshold. Each case writes its own temporary root and
preference suite, following the existing per-test `withFixture` precedent.

Conclusion: no expensive resource; no finding.

### Findings

1. Existing composition tests treat "a visible `.screenSaver` window" as "the
   selection is ready". With a pending overlay that becomes true before the
   freeze commits, so A8 and A9 would assert display subscriptions and
   retirement before they exist. Resolution: A8/A9 wait for the rendered frozen
   frame first (rows above).

### Increment review: rows changed after the post-implementation check

Date: 2026-10-28. Basis: `8bd52f2`. Rows A1, A3, A4, A6, A11, A12 and every
spec cell.

- Coverage: the rewritten Dimension 1 table lists each REQ-005 clause with a
  case or a gap; the two clauses newly recorded as gaps (no flash, hot-plug
  while pending) are environment-bound and get re-test conditions in the test
  file header.
- Case design: A1 and A4 observe the model's public `onRetireCaptureSources`
  callback, the same hook the production delegate wires to hide the menu
  panel, management center and onboarding; no private state is read. A3 sends
  `Esc` through `NSApplication.sendEvent`, so it reaches the overlay only if
  the overlay is the application's key window. A11 sends real `NSEvent`s in
  the order a user would (down and drag before the frame, up after it). A12
  reaches the invalidated branch only through public steps (two shortcuts, a
  posted display notification), not by setting state.
- False greens at design time: A1's hook count is asserted as both 0 (while
  held) and 1 (after the frame); A3's key-window assertion fails if
  `presentPending` stops making the overlay key; A11 fails if `attach` drops a
  drag in progress; A12's final admission fails if the invalidated branch
  leaves the request registered, and the geometry is restored before release
  so the late commit does not reach the modal failure alert.
- Resource reuse: no new resource; same per-test fixture.

Conclusion: no finding on the changed rows.

### Increment review: rows A11 and A12 after the incremental round (2026-10-28)

- A11: the final mouse up lands on a point that changes the selection's left
  edge after the frame arrived, and the assertion reads the toolbar's left
  edge, which the spec (§4) ties to the selection's left edge; it fails if the
  selection is completed at frame arrival instead of at mouse up.
- A12: one shortcut, no retry. It fails first on the code at `da94f5c`
  (request left registered until the stale freeze returns) and is the bug
  reproduction for finding 10; the fixture change (several held captures,
  released together) is needed because the second and third captures are both
  suspended at once.
- Resources and observables unchanged.

Conclusion: no finding on rows A11 and A12.

### Handling of post-implementation findings (2026-10-28)

| Finding | Handling |
|---|---|
| 2 Capability declaration missing | Record header corrected: it no longer claims mutation checks were performed. No mutation check is run until the user confirms `mutation-testing` (for example through `/repo-scaffold`); reported to the user with the registry's recommended answers |
| 3 Wrong requirement labels; unreconciled clauses | Spec cells and the Dimension 1 table rewritten against REQ-005; A1 now checks every `NSScreen`; "no desktop flash" and "display connected while pending" added to the test-file header with re-test conditions; checklist rows AC-01/02/03/05/06 updated |
| 4 AC-03 input ownership | A3 asserts the pending overlay is the key window and sends `Esc` through `NSApplication`; new A11 covers a drag begun before the frame and finished after it |
| 5 AC-05 invalidated request | New A12 |
| 6 FM-25 sources while pending | A1 and A4 count calls of the model's public `onRetireCaptureSources` hook (0 while pending, 1 after the frame, unchanged after a failed capture) |
| 7 Overstated claims | Late-result row now cites A3 and A7; "exactly once" removed from row A6 and from the test comment |
| 8 Native cleanup case not run | Run on the current code: passed, log in `native-thrown-operation-run.txt`. Its absence from CI and the local gate predates this change and is reported to the user for a decision; the test-file header now says which native cases CI runs |

Pre-handoff self-check of the fix (items 2-5):

- Item 2, each new or changed assertion: `everyScreenCovered` is false whenever any screen lacks a pending overlay; `retiredSources` is asserted at both 0 and 1 in A1 and stays 1 in A4; `overlay.isKeyWindow` was observed false in the locked-session run (Ticket 24), so it can fail; A11 checks no toolbar before mouse up and a toolbar after it; A12's `activity == nil` and overlay checks precede the admission check, which stays at 2 requests if the request is left registered. One assertion added during the fix, `historyRecords.isEmpty` in A12, could not fail on that path and was removed before handoff.
- Item 3, changed functions: only test code changed. `pressEscapeThroughApplication` throws when no window is key (driven by A3's failure mode) and is exercised by A3; `sendMouse` is exercised by A11; A12's bounded retry loop exits on admission or after 5 s and its result is asserted.
- Item 4, data: A11 and A12 use `syntheticDisplay()` (real screen geometry) and the existing `changedGeometry` helper; no new fixture shape.
- Item 5, shared helpers: no existing helper was modified; the two new helpers are used only by A3 and A11 (`grep -n 'pressEscapeThroughApplication\|sendMouse(' Tests -r`).

Self-check result: one item found and fixed (the vacuous A12 assertion); the rerun of the self-check found nothing further.

## Post-implementation check

Date: 2026-10-28. Implementation version: `8bd52f2` (commit range
`850f64d..8bd52f2`, branch `perf/instant-capture-overlay`). No ticket; this
round writes to this change's no-ticket path,
`docs/.workings/capture-instant-overlay/review-tests.md`. First round (no fix
range was handed over). Date, version and range apply to every dimension
below.

Objects: the tests this change writes or modifies, A1-A10 in
`Tests/VLMSnapperAppTests/ProviderApplicationTests.swift` and U1-U2 in
`Tests/VLMSnapperUITests/FrozenCaptureOverlayControllerTests.swift`, with the
fixture code they use (`FixtureCapture`, `stopFixture`, the new helpers).

Spec reference: the requirement this change adds is `v1-core::REQ-005`
(AC-01-07, `docs/specs/v1-core.md` lines 66-78); `v1-core::REQ-003` is the
interface-language requirement (line 248). AC numbers in this section are
REQ-005's; the design review's `REQ-003/AC-xx` labels are finding 3.

Capability declaration: 项目无能力声明文件 (no `capabilities.toml` at the
repository root). 未确认 mutation-testing: this round neither runs the
mutation check nor treats it as disabled (finding 2). Every "when does it go
red" answer below is derived from the code under test and the expected-value
source.

### Run evidence

Log (handed over, not rerun):
`/private/tmp/claude-501/-Users-loong-zhou-CascadeProjects-vlm-snapper/ced9312a-2254-4011-9516-18529f20df8b/scratchpad/logs/gate-pre-review.log`.

| Log requirement | Log content | Verdict |
|---|---|---|
| Tested version | `git rev-parse HEAD` = `8bd52f26...`, the end of the handed range; `git status --porcelain --untracked-files=all` lists only `:-` with its `git hash-object` (untracked since 2026-09-01, a codesign requirement string that no test reads) | Matches the handed range |
| Every command | `bash Scripts/test-local-regression.sh --offline`; the `PATH` prefix is logged as `<scratch rg shim>`, and the scratch `gate.sh` shows it is the scratchpad `bin/`, whose `rg` only `exec`s Claude Code's ripgrep | Present; the elided prefix changes no stage result |
| Exit code not taken through a pipe | `== exit: 0`, from `code=$?` directly after a redirect (`gate.sh`) | Present |
| Full output | Top-level output plus all nine stage logs (strict-build to accessibility) | Present |
| Skipped commands | None; this change modifies test files, so none may be skipped | Correct |

Reviewed tests in the log: A1-A10 pass in the `app` stage (log lines 97-132);
U1 and U2 pass in the `non-app` stage (lines 1213 and 1257). The native XCTest
case that checks the changed fixture cleanup is not in the log (finding 8).

Conclusion: the log meets the gate's log requirements and is this round's run
evidence.

### Test design table check

| Row | Written test against the table (seam, input, assertions, expected-value source, fixture, resources) | Verdict |
|---|---|---|
| A1 | As designed; "same window" is checked with `mainScreenOverlay() === overlay` | Consistent |
| A2 | As designed, plus "no frozen frame while held" and "frozen frame after release" | Consistent |
| A3 | As designed | Consistent |
| A4 | As designed, plus one onboarding request as the wait condition | Consistent |
| A5 | As designed | Consistent |
| A6 | Assertions as designed; the parenthesis "single shared lease released exactly once" is not something the assertions can show | Finding 7 |
| A7 | As designed | Consistent |
| A8, A9, A10 | As designed | Consistent |
| U1 | As designed, plus visibility of the current and pending overlays before and after `rollback()` | Consistent |
| U2 | API migration only | Consistent |
| All rows | The spec column cites `REQ-003/AC-01-05` | Finding 3 |

Not in the table: the shared teardown change in `cb19ef2` (`stopFixture`,
`withModel` and `withApplication` hold pre-existing windows by strong
reference). It is fixture code and changes no row's seam, input or assertion;
it is judged under Dimension 2, and the case that guards its contract is
finding 8.

### Dimension 1: Coverage

Test-file header (`ProviderApplicationTests.swift` lines 34-40) names four
gaps, each checked against the code: compositor exclusion of the pending
overlay (signed app); a second display whose freeze fails while another
commits (two displays); every display invalidated before commit (`commit`
returns `false`, then `showCaptureFailure` runs `runModal`,
`VLMSnapperApplicationModel.swift` 1171-1178 and 1257-1280); window-server hit
testing (`sendEvent`). All four are real gaps with re-test conditions.

Coverage of REQ-005 and the failure modes this change touches:

| Spec clause | Case | Verdict |
|---|---|---|
| AC-01 overlay shown before the freeze, no new element or text | A1 | Covered |
| AC-01 "every connected display" | A1 looks only at `NSScreen.main`; the test machine has one display (`measurements.md`) | Neither covered nor recorded (finding 3) |
| AC-02 frame in the same window, no rebuild | A1 | Covered |
| AC-02 no desktop flash | Ordering inside one main-thread call; not observable in process | Not recorded as a gap (finding 3) |
| AC-02 frame and PNG exclude the overlay | Header gap | Recorded gap |
| AC-03 mouse taken over incl. the clear selection interior; no click reaches other apps | Header gap (hit testing) | Recorded gap |
| AC-03 keyboard taken over while pending | None | Finding 4 |
| AC-03 rectangle completed before the frame | A2 | Covered |
| AC-03 rectangle begun before the frame, finished after it | A10 only by timing | Finding 4 |
| AC-04 overlays and toolbar withdrawn; replaced selection discarded | A3, A6 | Covered |
| AC-04 reserved result workspace usable again | A7 | Covered |
| AC-04 late freeze result does not reopen the selection | A3, A7 | Covered (the design table's A5/A6 claim is finding 7) |
| AC-05 permission missing; previous overlay and toolbar restored | A4, U1 | Covered |
| AC-05 freeze failure; new overlay covers no display | Modal alert path | Recorded gap |
| AC-05 request invalidated | None | Finding 5 |
| AC-06 display without a valid frame withdrawn while another commits | Two displays | Recorded gap |
| AC-06 display connected before the freeze completes is not selectable | None | Not recorded (finding 3) |
| AC-07 termination while pending (the update-install path calls the same `prepareForTermination`) | A5 | Covered |
| FM-3 failure keeps the previous selection | A4, U1 | Covered |
| FM-18 | A5 | Covered |
| FM-23 `Esc` from a terminal result workspace | A7 | Covered |
| FM-25 new overlay shown before the old one is hidden; old overlay, toolbar and frame released only after the new frame | A4 (state after `presentPending`), A8 (`contentView == nil` only after the frame), A4 and U1 (old overlay intact after failure) | Covered |
| FM-25 one shared lease | A6 | Covered |
| FM-25 menu panel and management center stay open under the pending overlay and are hidden after the frame | None | Finding 6 |

Fixture independence: unchanged from the design review. Frozen frames keep the
real per-display shape (`NSScreen.main` geometry and pixel size); the held
capture is a suspension inside the real `FrozenDisplayCapturing` call; the
failure uses the real `CaptureDiscoveryError.permissionDenied`.

Conclusion: findings 3, 4, 5 and 6.

### Dimension 2: Case design

- Production paths: shortcut handler, model, overlay panels, toolbar and
  result windows are production; capturer, display reads, HTTP and credentials
  are fixtures. Exception: `pressEscape` (`ProviderApplicationTests.swift`
  1725-1730) hands the key event to the overlay window itself, so no case
  routes a key event through the application's key-window choice (finding 4).
- Isolation: each case builds its own fixture, and teardown releases the held
  capture before `prepareForTermination`. `cb19ef2` holds pre-existing windows
  by strong reference, so a window created by the case can no longer be
  skipped through address reuse (4 of 21 suite runs failed before, 0 of 20
  after, `tasklist.md`). A2, A4, A6 and A7 wait for the toolbar and time out
  in a locked session (`locked-session-toolbar-timeouts.txt`, Ticket 24): an
  environment dependency, not a false green.
- Observables: window visibility and frame, the content view's rendered layer
  tree, toolbar windows, the published activity, history through the model,
  recorded HTTP requests and the fixture's capture count. No private
  controller or model state is read.
- Reachability: a held capture stands for the real 100-200 ms freeze;
  `permissionDenied` after a wait is a real capturer outcome. No unreachable
  state is constructed.

Conclusion: finding 4 (keyboard part); nothing else.

### Dimension 3: False greens

Mutation check: not run (finding 2).

Unit-test forms:

- Vacuous assertions: `overlayShowsFrozenFrame` is shown `false` (pending
  scrim, alpha about 0.48) and `true` (opaque frame) in A1, and `false` in A2
  with a selection hole away from the sampled centre. `historyRecords.isEmpty`
  and `imageRequests.isEmpty` in A3, A5 and A6 cannot turn red on the pending
  path, because history and requests need an operation click these cases
  never make; they are guards, and no row relies on them alone.
- Tautologies: expected values come from the spec and observed windows; no
  case imports the scrim constant or recomputes the implementation.
- Stale paths: `replace(displays:onSelection:onCancel:)` is removed and
  unreferenced; A8 and A9 no longer treat any visible overlay as "selection
  ready".
- Silent conditional skips: none; a missing screen or window throws
  (`#require`, `requireFixture`).
- Assertions that may not run: none sits in a callback; U1 checks both window
  lists are non-empty before `allSatisfy`.

UI forms (`review-code/false-greens.md`):

- Existence instead of effect: overlays are identified by level, visibility
  and exact screen frame, frozen frames by rendered alpha.
- Synthetic events: mouse events via `sendEvent` skip hit testing (recorded
  gap); key events skip key-window routing (finding 4).
- Read too early or too late: A3 and A7 wait for `activity == nil`, which the
  admission wrapper produces only after `perform` returns, that is after the
  late freeze result was handled (`ApplicationWorkflow.swift` 41). A6 polls
  the same expression, but a replacement reuses the existing lease
  (`ProviderConfiguration.swift` 437) and `Esc` already released it in
  `cancelCapture` (`VLMSnapperApplicationModel.swift` 1552-1564), so A6's
  post-release checks can run before the late result is handled (finding 7).
  A8 and A9: `commit` and `displayMonitor.start` run in one main-actor stretch
  without suspension, so a visible frame implies the subscription. A4: the
  onboarding callback runs after `rollback` in the same synchronous branch.
- Command, gate, exemption, geometry and scope forms: no CLI check, gate or
  exemption is added; the only geometry check is exact frame equality.

When each case goes red:

| Case | Goes red when |
|---|---|
| A1 | The overlay waits for the freeze (the recorded first red), the frame lands in another window, or no frame is attached |
| A2 | A selection released before the frame is dropped, or completes before the frame (toolbar while held) |
| A3 | `Esc` while pending does not withdraw the overlay, the lease is not released, or the late result reopens overlay or toolbar |
| A4 | Rollback does not show the previous overlay with its frame, the toolbar is not resumed, the pending overlay stays, or the failure releases the shared lease |
| A5 | Termination leaves the pending overlay or refuses; if it awaited the freeze the case would hang rather than fail (the local gate has no stage timeout) |
| A6 | `Esc` restores the replaced selection instead of discarding it, the toolbar stays, or the lease is never released; not when the late result reopens something after the checks (finding 7) |
| A7 | The result window is hidden before commit (nothing shows it again on `Esc`), or the reservation is not restored (third capture refused) |
| A8 | The previous overlay is not retired at commit, or subscriptions are missing after the frame or kept after `Esc` or termination |
| A9, A10 | Unchanged assertions, now taken after the frame (A9) or on the main-screen overlay (A10) |
| U1 | `commit([])` reports success or changes `presentedDisplayIDs`, `presentPending` leaves the current overlay visible, or `rollback` does not swap back |
| U2 | The alert is not raised above `.screenSaver` |

Conclusion: finding 7; the mutation check waits on finding 2.

### Dimension 4: Resource reuse

Resources: `ApplicationFixture` (temporary root, preference suite, model with
temporary SQLite, `model.start()`), the synthetic frozen frame (one
full-resolution fill), overlay panels, and U1/U2's controller with a 2x2
image.

Runtime (gate log, `app` stage): whole cases including fixture creation,
start, frame construction and teardown took 0.075 s (A5), 0.111 s (A1) and
0.125 s (A3), so no resource reaches 1 s; longer cases (A10, 1.997 s) add
flows on the same fixture. U1's 7.014 s is wall-clock time in the parallel
Swift Testing run: the case is synchronous without I/O, and two unrelated
tests finish at the same 7.014 s (log lines 1221 and 1223); panel creation was
measured at 4-11 ms (`measurements.md`). No expensive resource exists, so
there are no load counts to compare and no shared resource that a case clears.

Conclusion: no finding; the design-review conclusion holds.

### Document sync check

Scope: this record and every file in `docs/.workings/capture-instant-overlay/`
(enumerated with `find`, hidden files included;
`git ls-files --others --ignored --exclude-standard` over `docs`, `Tests` and
the root documents returned nothing); `docs/.workings/v1-core/checklist.md`
(REQ-005 section, lines 10-31); `docs/specs/v1-core.md`;
`docs/features/v1-core.md`; ADR-0013; `CONTEXT.md`; root `AGENTS.md` and
`CODEX.md` (`@AGENTS.md`; there is no root README); both test-file headers;
`Scripts/test-local-regression.sh` and `.github/workflows/ci.yml` for which
cases run. Other directories are excluded: a repository-wide search for the
reviewed test names (excluding `.build` and `.git`) finds them only in these
files and in `docs/.workings/capture-self-exclusion/review-tests.md`, an
earlier change's record of U1's previous form.

Facts established this round: the requirement is REQ-005 with seven criteria;
the clauses in findings 4-6 can be driven in process but are not; late-result
coverage rests on A3 and A7; the native cleanup case is run by neither the
gate nor CI.

| Document | Statement | State |
|---|---|---|
| This record, header and design review | `REQ-003/AC-xx` labels; "mutation checks are performed"; coverage row "A3, A5, A6"; A6 "exactly once" | Untrue (findings 2, 3, 7); left in place for the resolver, because this round may only add its own section |
| `docs/.workings/v1-core/checklist.md` lines 25, 27, 28 | AC-03 lists A2 and the click gap; AC-05 lists A4 and U1; AC-06 cites "单屏组合测试经冻结后几何复核" without naming a case | Incomplete for findings 3-5; update with their resolution |
| `final-regression.md` line 18 | "untestable parts are the REQ-005 Pending and the test-file header gaps" | Contradicted by findings 4-6; re-check after their resolution (the report already plans a re-check after this review) |
| `ProviderApplicationTests.swift` header lines 24 and 34-40 | "CI also runs these cases separately"; four REQ-005 gaps | Line 24 untrue for one of the three native cases (finding 8); the gap list is to be extended per finding 3 |
| Spec Testing Decisions lines 367, 371, 381 | Native XCTest covers cleanup after a throw or cancellation; REQ-005 composition observables; fixture identity rule | 371 and 381 true; 367 true that the case exists, but no gate runs it (finding 8) |
| `tasklist.md`, `review-code.md`, `measurements.md`, features, ADR-0013, `CONTEXT.md` | No test-coverage statement | Unaffected; `review-code.md`'s Runnability row for a display change while pending describes finding 5's path and stays true |
| Root `AGENTS.md` | "项目能力" section | Capability statements in a rules file (finding 2) |

No sync item is completed by this round.

### Incremental round: fix `8bd52f2..da94f5c`

Date: 2026-10-28. Implementation version: `da94f5c` (fix range
`8bd52f2..da94f5c` of the change `850f64d..da94f5c`, branch
`perf/instant-capture-overlay`). No ticket; same no-ticket path. Date, version
and range apply to every part of this round. Everything outside the objects
below carries over from the first round of this check (the subsections above,
version `8bd52f2`).

Capability declaration, re-checked directly (`ls capabilities.toml` at the
repository root: no such file): 项目无能力声明文件; 未确认 mutation-testing;
未确认 working-language. Finding 2 is still open, so this round neither runs the
mutation check nor treats it as disabled; every "goes red" answer below comes
from the code under test and the expected-value source, not from a run.

#### Objects

| Retrieval | Result |
|---|---|
| `git diff --name-only 8bd52f2..da94f5c -- Tests Sources VLMSnapper Package.swift Scripts .github` | Only `Tests/VLMSnapperAppTests/ProviderApplicationTests.swift`; no product, build or gate file changed |
| `git diff -U0 8bd52f2..da94f5c -- Tests` (hunk headers) | Header lines 24-27 and 39-42; A1 (`overlayCoversDisplaysBeforeFreezeCompletes`), A3 (`escapeWhileFreezingExitsCapture`), A4 (`failedFreezeRestoresPreviousSelection`), A6 (`escapeWhileReplacingSelectionReleasesActivity`, comment only), new A11 (`selectionStartedBeforeFramesFinishesAfterThem`) and A12 (`displayChangeWhileReplacingAbandonsPendingCapture`), new helpers at lines 1816-1835. No existing helper, fixture or shared setup changed |
| `grep -rna --include='*.swift' -e 'pressEscapeThroughApplication' -e 'sendMouse(' Tests` (86 Swift files under `Tests`) | Both new helpers are `private` to `ProviderApplicationTests.swift` (1818, 1827), so no other file can import them; callers are A3 (1076) and A11 (1239, 1240, 1244) only. No further test depends on changed helper code |
| Test design table rows at `8bd52f2` and `da94f5c` (`git show <rev>:docs/.workings/capture-instant-overlay/review-tests.md`, rows `^\| [AU][0-9]* \|`, compared with and without the spec column) | Changed: A1, A3, A4, A6 (content and spec cell); A2, A5, A7, A10, U1 (spec cell only); A11, A12 (new). Unchanged: A8, A9, U2 |

Objects of this round: tests A1, A3, A4, A6, A11, A12 and the test-file
header; table rows A1-A7, A10, A11, A12 and U1.

#### Run evidence

Handed logs, not rerun. Targeted log of the fix:
`logs/targeted-findings-fix.log`. Reused pre-review gate log:
`logs/gate-pre-review-8bd52f2.log`, byte-identical (`cmp`) to the
session-temporary original the first round checked, so the first round's
verdict on it carries over.

| Log requirement (targeted log) | Log content | Verdict |
|---|---|---|
| Tested version | `git rev-parse HEAD` = `8bd52f26…` with a modified tree; every manifest hash equals the blob at `da94f5c` (`git rev-parse da94f5c:<path>`) except `tasklist.md` (`e2957e7` logged, `12ea198` committed: the later edit only adds the pointer to this log, an inert `docs/` Markdown file no build or test reads). The three `logs/` files were absent at run time (written afterwards). `:-` unchanged (`208ccf6`) | Matches `da94f5c` for every file the build and tests read |
| Every command | The six build and test commands are logged with their arguments, as are `git rev-parse HEAD` and `git status --porcelain --untracked-files=all`; the command that produced the manifest is not (`-- manifest` only) | Missing item (finding 11) |
| Exit code not taken through a pipe | `== exit: N` after every command and `== overall: 0`; how they were taken is shown only by the session-temporary `targeted.sh` (`"$@" >> "$log" 2>&1; local c=$?`) | Present; provenance not kept (finding 11) |
| Full output | Complete output of every command inline | Present |
| Objects run | App run: A1, A3, A4, A6, A11, A12 pass (log lines 343-360); the native thrown-operation case passes on the fixed code (424-429) | All objects ran and passed |

#### Test design table check

| Row | Written test against the row | Verdict |
|---|---|---|
| A1 | Every-screen check, hook count 0 while held and 1 after the frame, same window | Consistent |
| A3 | Key-window assertion, then `Esc` through `NSApp.sendEvent` | Consistent |
| A4 | Hook count 1 after the first capture and still 1 after the failed one | Consistent |
| A6 | The comment no longer claims "exactly once"; assertions unchanged | Consistent |
| A11 | Down and drag before the frame, wait for the rendered frame, no toolbar, mouse up, toolbar | Consistent (what its "no toolbar" read can detect: finding 9) |
| A12 | Row: "after release and a further shortcut … `capture.requests == 3`". Test: a shortcut every 50 ms for up to 5 s until admitted, then `requests >= 3` | Inconsistent driving input and assertion (finding 10) |
| A2, A5, A7, A10, U1 | Spec cells now cite REQ-005 correctly (A2 AC-03, A5 AC-07, A7 AC-04, A10 AC-03, U1 AC-05) | Consistent |

The expected-value cells of A2 and A7 and the reason cell of A10 still carry
the provisional numbers ("AC-02", "AC-03", "the AC-02 path") beside the right
content: numbering only, no conclusion depends on it, not a finding.

#### Dimension 1: Coverage

Test-file header lines 36-42: the two gaps added by the fix are real. A
display connected while frames are pending gets no pending panel
(`presentPending` builds panels from `NSScreen.screens` at presentation,
`FrozenCaptureOverlayController.swift` 39) and no frame, and the screen list
cannot be changed in process; the absence of a flash is ordering inside
`presentPending` (67-73). Lines 24-27 are true: `Scripts/test-local-regression.sh`
50-55 and `.github/workflows/ci.yml` 38, 44, 50 run only the Paste and
closed-window native cases.

| Clause touched by the fix | Case | Verdict |
|---|---|---|
| AC-01 overlay on every connected display | A1 | Covered on multi-display runs only; on the one-display machines that run the suite the check follows from the preceding wait. The checklist row says so ("本机单屏"), and this is the option finding 3 offered; no new finding |
| AC-03 keyboard owned while pending | A3 | Covered |
| AC-03 rectangle begun before the frame is kept | A11 | Covered (a drag reset at the frame turns A11 red) |
| AC-03 and §3: a rectangle begun before the frame completes at mouse-up, not when the frame arrives | A11's "no toolbar" read | Not effectively driven (finding 9) |
| AC-05 request invalidated | A12 | The withdrawal and the cleared request are covered; the admission refusal A12 tolerates is finding 10 |
| FM-25 sources retired only after the frame, not on failure | A1, A4 | Covered through the model hook; the delegate wiring (`VLMSnapperApplicationDelegate.swift` 149-153) has no diff in `850f64d..da94f5c` |

Fixture independence: A11 and A12 use `syntheticDisplay()` (real
`NSScreen.main` geometry and pixel size) and the existing `changedGeometry`;
no new shape.

Conclusion: findings 9 and 10.

#### Dimension 2: Case design

- A3 now drives `Esc` through the application's key-window routing; A11 sends
  real `NSEvent`s to the pending panel in user order, still without hit
  testing (header gap); A12 reaches the invalidated branch only through two
  shortcuts and an injected display notification, the REQ-001 tests' path.
- Observables: window visibility and key status, the rendered frame, the
  toolbar window, the published activity, the fixture's capture count and the
  model's `onRetireCaptureSources` callback, which production wiring sets. No
  private state is read.
- No unreachable state is constructed. A12 restores the geometry before the
  third capture, so that capture is not invalidated into the modal failure
  alert.

Conclusion: no finding.

#### Dimension 3: False greens

Mutation check: not run (finding 2, open).

UI forms (`review-code/false-greens.md`): key status, per-screen frames and the
rendered frame are effects, not existence. Key events now pass the
application's routing; mouse events still skip hit testing (recorded gap).
Read timing: A1's hook is called in the same main-actor stretch as `commit`
(`VLMSnapperApplicationModel.swift` 1168-1202, no suspension), so a visible
frame implies the call; A12 polls exactly the expressions it asserts; A11's
"no toolbar" is read in the main-actor turn in which the frame was seen,
before an early completion could show a toolbar (finding 9). No gate, CLI
check or exemption is added.

| Case | Goes red when |
|---|---|
| A1 | Sources are retired at admission or in `presentPending` (count 1 while held), or not retired, or retired twice after the frame; a screen lacks a pending overlay (multi-display runs only); plus the first round's causes |
| A3 | `presentPending` does not make the pending panel key (`isKeyWindow` false, as observed in the locked-session run, Ticket 24), no window is key (`requireFixture` throws), or `Esc` routed by the application does not withdraw the overlay; plus the first round's causes |
| A4 | The failed capture or its rollback calls the retirement hook, or the first commit does not |
| A6 | Unchanged from the first round |
| A11 | `attach` or `commit` resets or replaces the view holding the drag (mouse-up finds no `dragStart`, no toolbar), a mouse-down before the frame is ignored, or the frame lands in another window (`overlayShowsFrozenFrame` throws on a retired panel). Not when the selection is completed at frame arrival (finding 9) |
| A12 | The invalidated branch leaves `captureRequest` set (requests stay at 2 for 5 s), the display change leaves the pending overlay or the activity in place, or the third capture shows no overlay |

Conclusion: finding 9.

#### Dimension 4: Resource reuse

Counted from the targeted log, whole cases including fixture creation, model
start, frame construction and teardown: A1 0.133 s, A3 0.126 s, A4 0.324 s,
A6 0.547 s, A11 0.211 s, A12 0.217 s. No resource reaches 1 s, so there are no
load counts to compare and no shared resource that a case clears; the
collection-order check does not apply.

Conclusion: no finding.

#### Re-check of the first round's findings

| Finding | State after the fix |
|---|---|
| 2 | Open: `capabilities.toml` still absent; waits on the user |
| 3 | Resolved: spec cells and the Dimension 1 table use REQ-005, header gaps added, A1 checks every screen, checklist rows updated |
| 4 | Resolved: A3 (keyboard) and A11 (drag kept across the frame); finding 9 is a different gap in A11 |
| 5 | Resolved for the branch; finding 10 concerns what A12 tolerates |
| 6 | Resolved: A1, A4 |
| 7 | Resolved: the late-result row cites A3 and A7; "exactly once" removed from row A6 and the test comment |
| 8 | The case ran on the fixed code (targeted log 424-429) and the header is corrected; adding it to the gate and CI still waits on the user's decision |

#### Document sync check

Scope: this record and every file under `docs/.workings/capture-instant-overlay/`
(enumerated with `find`, hidden files included;
`git ls-files --others --ignored --exclude-standard -- docs Tests AGENTS.md CODEX.md CONTEXT.md`
returned nothing); `docs/.workings/v1-core/checklist.md` REQ-005 rows (lines
23-29); `docs/specs/v1-core.md` (§3 line 42, REQ-005 lines 66-78, FM-25,
Testing Decisions 367 and 371); `docs/features/v1-core.md`; ADR-0013;
`CONTEXT.md`; root `AGENTS.md` and `CODEX.md`; the test-file header;
`Scripts/test-local-regression.sh` and `.github/workflows/ci.yml`. A
repository search for the reviewed test names and the retirement hook
(excluding `.build` and `.git`) finds them only in these files, the evidence
logs and the product sources, so other directories are excluded.

Facts from the fix range and its targeted run: A1, A3 and A4 strengthened, A11
and A12 added, header gaps added and the native-case statement corrected, the
native cleanup case run on the fixed code, logs kept in `logs/`. Facts this
round establishes: findings 9-11.

| Document | Statement | State |
|---|---|---|
| This record, test design table row A12 | "after release and a further shortcut … `capture.requests == 3`" | Differs from the test (finding 10) |
| This record, design-review Dimension 1 row "AC-03 rectangle begun before the frame, finished after it" | Covered by A11 | Holds for "kept", not for "completed at mouse-up" (finding 9) |
| This record, first-round Run evidence (lines 213-229) | Cites the session-temporary log, `gate.sh` and the rg shim | The log is now kept byte-identical; the scripts are not (finding 11) |
| `checklist.md` line 23 (AC-01) | Every `NSScreen` checked, "本机单屏" | True |
| `checklist.md` line 25 (AC-03) | A11 for "冻结前开始、帧到达后完成的选区" | Overstated until finding 9 is resolved |
| `checklist.md` line 27 (AC-05) | A12 for 请求失效 | True for the withdrawal; see finding 10 |
| `final-regression.md` line 18 | REQ-005 against implementation and tests: "True; parts not driven by tests are the REQ-005 Pending and the gaps listed in the test-file header" | Contradicted by findings 9 and 10; re-check after their resolution |
| `tasklist.md` line 74 (spec final check, AC-01 "Met") | Admission shows the overlay immediately | Not met in finding 10's window |
| `tasklist.md` lines 91-96 | Evidence list | True; the run scripts are missing (finding 11) |
| Test-file header lines 24-27, 36-42 | Native-case runs; gap list | True |
| Spec REQ-005 scope and AC-01 (lines 68, 70), §3 (line 42); features line 35 | A ready shortcut shows the overlay at once | Contradicted by the implementation in finding 10's window; unchanged under its option (a), needs wording under option (b) |
| Spec Testing Decisions 367 and 371, ADR-0013, `CONTEXT.md`, `measurements.md`, `review-code.md`, root `AGENTS.md` and `CODEX.md` | No statement on these facts | Unaffected |

No sync item is completed by this round.

### Incremental round: fix `da94f5c..533de26`

Date: 2026-10-28. Implementation version: `533de26` (fix range
`da94f5c..533de26` of the change `850f64d..533de26`, branch
`perf/instant-capture-overlay`). No ticket; same no-ticket path. Date, version
and range apply to every part of this round. Outside the objects below, every
dimension carries over from the previous incremental round (fix
`8bd52f2..da94f5c`, version `da94f5c`) and, where that round carried over,
from the first round (version `8bd52f2`).

Capability declaration, re-checked by opening `capabilities.toml` at the
repository root with Python's `tomllib` (`FileNotFoundError`): 项目无能力声明文件;
未确认 mutation-testing; 未确认 working-language. Finding 2 is still open, so this
round neither runs the mutation check nor treats it as disabled; every "goes
red" answer below comes from the code under test and the expected-value
source.

#### Objects

| Retrieval | Result |
|---|---|
| `git diff --name-only da94f5c..533de26 -- Tests Sources VLMSnapper Package.swift Scripts .github` | `Sources/VLMSnapperApp/VLMSnapperApplicationModel.swift` (the `cancelCapture` fix) and `Tests/VLMSnapperAppTests/ProviderApplicationTests.swift` |
| `git diff da94f5c..533de26 -- Tests` (hunks) | A11 body (1236-1251), A12 body (1276-1289) and `FixtureCapture` (2223-2252: the single `waiter` becomes `waiters`, and `release()` resumes all of them). No header line, other test or other helper changed |
| `grep -rn --include='*.swift' 'FixtureCapture' Tests` | Declared `private` in `ProviderApplicationTests.swift` (2219) and used only as `ApplicationFixture.capture` (1978); `ApplicationFixture` and `withFixture` (1901) are `private` to the same file, so no other test file can reach the changed code |
| `grep -n -E '^\s*(@Test\|func test[A-Za-z]*\()'` on that file, checked against its uses of `withFixture` | 29 Swift Testing tests in `ProviderApplicationTests` (208-1556) and 3 XCTest cases in `ProviderApplicationTestsNativeMenu` (49, 99, 146). Every one builds an `ApplicationFixture`, so all 32 depend on `FixtureCapture`, at least through the teardown's `capture.release()` in `withModel` and `withApplication` |
| `grep -n -e 'holdFrames()' -e 'allowSuspendedCapture()' -e 'capture.release()'` on that file, read with each test's `shortcuts.fire()` calls | Suspending tests: A1-A7, A11, A12 and `credentialValidationAndFreezingExcludeEachOtherThroughApplicationWiring`. Only A12 holds two captures at once (its second and third shortcut); every other one fires a single shortcut between its hold and `release()` (A7's third shortcut follows `release()`, which clears `framesHeld`). For those nine and the 22 tests that never suspend, `release()` resumes one or no continuation, as before |
| `git diff da94f5c..533de26 -- docs/.workings/capture-instant-overlay/review-tests.md`, rows `^\| [AU][0-9]* \|` | Rows A11 and A12 changed; no other row |

Objects of this round: tests A11 and A12, the other 30 tests of the file
through `FixtureCapture`, and table rows A11 and A12.

#### Run evidence

Handed logs, not rerun. Targeted log of the fix:
`logs/targeted-findings-9-11.log`. The reused gate log
`logs/gate-pre-review-8bd52f2.log` is not touched by the fix range and no
object of this round takes its result from it; the earlier rounds' verdict on
it carries over.

| Log requirement (targeted log) | Log content | Verdict |
|---|---|---|
| Tested version | `git rev-parse HEAD` = `da94f5c…` with a modified tree. Manifest hashes against `git rev-parse 533de26:<path>`: equal for the model, the test file, `review-code.md`, `review-tests.md`, the spec and the three `logs/scripts/` files. `tasklist.md`: `6673155` logged, `095d0c2` committed; the logged blob is the committed file's first 99 lines (`git hash-object` of `head -n 99`), and the three later lines only point to this log (inert `docs/` Markdown no build or test reads). `targeted-findings-9-11.log` is the run's own output, and `change-scope-after-findings-9-11.txt` was written afterwards (it lists the log as present). `:-` unchanged (`208ccf6`). Before this round wrote its section, the work tree equalled `533de26` apart from `:-` (`git diff --stat 533de26 -- . ':(exclude):-'` was empty) | Matches `533de26` for every file the build and tests read |
| Every command | The two builds and four test runs with their arguments; `git rev-parse HEAD`, `git status --porcelain --untracked-files=all` and the manifest command (line 16) | Present |
| Exit code not taken through a pipe | `== exit: N` after every command and `== overall: 0`; `logs/scripts/targeted.sh` (blob `4ecc9d0`, the hash the manifest recorded at run time, and byte-identical to the session copy) takes `c=$?` directly after the redirected command | Present; provenance kept |
| Full output | Complete output of every command inline | Present |
| Objects run | Swift Testing run: 29 tests in 1 suite passed (lines 301-385), A11 0.234 s (360-361), A12 0.246 s (362-363); the three XCTest cases passed (387-443) | All 32 objects ran and passed |

A12's red run on `da94f5c`, cited by the handling of findings 9-11 and by
`tasklist.md` lines 98-99, survives only in the session scratchpad
(`logs/f10-red.log`: `deadline(..., 1281)`, no version manifest). This round
does not rely on it: the "goes red" answer for a request left registered comes
from the code at `da94f5c`, whose `cancelCapture` active branch has no
`captureRequest` step (the fix hunk at model line 1555), and agrees with it.

#### Test design table check

| Row | Written test against the row | Verdict |
|---|---|---|
| A11 | Down at (300, 300), drag to (400, 400), release, wait for the rendered frame, drag to (150, 400) and up there (1239-1246); no toolbar after the frame (1243); toolbar left edge within 1 pt of overlay x + 150 (1250). The expected value comes from the input point and §4 (操作栏默认位于选区左下方), not from `CaptureToolbarPlacement` | Consistent |
| A12 | One shortcut while the second capture is held (1280); admission as `requests == 3` with a main-screen overlay (1281-1283); release of both; frozen frame in the same, visible window (1284-1288) | Driving input and assertions consistent; the row's reading of the post-release checks ("stays visible: the stale second result does not touch it") is finding 12 |
| A1-A10 | Fixture cells unchanged in meaning: a held capture still returns the provided display after `release()` | Consistent |

The other 20 tests of the file predate this change and have no rows.

#### Dimension 1: Coverage

Test-file header (lines 34-44): unchanged by the fix range; its gaps stay
true, and the fix adds no environment-bound path.

| Clause touched by the fix | Case | Verdict |
|---|---|---|
| AC-05 added sentence: the replaced selection ends on its own before the freeze completes, so this capture ends | A12 (after the display change: no visible overlay, activity `nil`) | Covered |
| AC-05 added sentence and AC-01: a later shortcut shows a new overlay without waiting for the invalidated freeze | A12 (one shortcut while the second freeze is held; `requests == 3` and an overlay) | Covered |
| AC-03: a rectangle begun before the frame completes at mouse-up (finding 9) | A11 (toolbar at the final left edge) | Covered |
| The fix's `replacement?.workspaceToRetire?.restoreAfterCaptureFailure()` (model 1568) | None | Not a gap: no reachable state gives that request a workspace (below) |
| A stale freeze result leaves a newer capture alone | A12's post-release checks | Not ordered after the stale result (finding 12) |

No reachable workspace for a replacement: `workspaceSession` is `private` to
the model, the only Swift file that names it (`git grep -c workspaceSession --
'*.swift'`); its writes (`grep -n -E 'workspaceSession\s*=[^=]'`; no `&`,
tuple or key-path writes) are lines 862, 1196, 1402, 1538 and 1547. A commit
leaves it `nil` (`captureRequestCanCommit` 1248-1254 with 1194-1196). While the
selection is active, 1402 cannot run first (it follows
`cancelCaptureSurfaces()` at 1391, which ends the selection), and 862 belongs
to `openHistoryRecord`, whose only trigger, `ManagementCenterCallbacks.onOpenRecord`
(model 326), is never invoked: `git grep -n OpenRecord -- '*.swift'` finds only
its declaration, initializer parameter and assignment
(`ManagementCenterView.swift` 100, 125, 149) and test closures whose tests
assert it is not called. So `perform` reads `workspaceSession == nil` (1082)
for every replacement.

Fixture independence: A11 and A12 keep `syntheticDisplay()` and
`changedGeometry`; `FixtureCapture` still returns one batch per call at the
real `NSScreen.main` geometry. Several calls held at once is the state the
fixed model produces (the invalidated freeze still in flight while a new
capture starts).

Conclusion: no finding.

#### Dimension 2: Case design

- A11 sends real `NSEvent`s to the pending panel in user order and reads the
  visible toolbar window's frame. A12 reaches the branch through shortcuts and
  an injected display notification (the REQ-001 tests' path) and reads the
  capture count, the visible main-screen overlay, its rendered frame and its
  identity. No private state is read.
- Each held call is a real suspension inside the `FrozenDisplayCapturing`
  call the production coordinator awaits; no unreachable state is built.
- Isolation: the teardown's `release()` now resumes every held call, so no
  capture task outlives its test; the single `waiter` would have dropped A12's
  first continuation.

Conclusion: no finding.

#### Dimension 3: False greens

Mutation check: not run (finding 2, open).

Unit-test forms: A11's left-edge check separates 150 from 300 with a 1 pt
tolerance; A12 asserts `requests == 3`, not the earlier `>= 3`, and fires once
(the retry loop is gone); expected values come from the inputs and the spec,
with no import of `CaptureToolbarPlacement` or overlay constants; no silent
skip (`#require` throws); no assertion sits in a callback.

UI forms (`review-code/false-greens.md`), read timing: A11 reads the toolbar
once it appears. Under a completion at frame arrival, that completion's task
is created in `attach` before the test sends the later events, and both
completions pass the main actor and the session actor in creation order, so
the early toolbar is the one read. A12's admission wait polls the asserted
expression. A12's post-release checks run in the main-actor turn in which the
third frame is first seen, while the stale second result arrives on its own
task (`release()` resumes it first; `startCapture` then runs on the generic
executor, `CaptureFreezeCoordinator.swift` 73-99, language mode 6 without
`NonisolatedNonsendingByDefault`, `Package.swift` lines 1 and 142) with no
ordering to that turn (finding 12). No gate, CLI check or exemption is added.

| Case | Goes red when |
|---|---|
| A11 | The selection completes at frame arrival (toolbar at x + 300; the later mouse-up is dropped by the `captureDisplayGeometries` guard, model 1286-1288, or refused as `inactiveSession`); `attach` or `commit` drops the drag (no `dragStart`, no toolbar); a mouse-down before the frame is ignored; the frame lands in another window; the toolbar stops being left-aligned with the selection |
| A12 | `cancelCapture` leaves the pending replacement's `captureRequest` (the defect: `perform`'s guard, model 1079, refuses the shortcut, requests stay 2, deadline at test line 1281); the display change leaves an overlay or the activity; the third capture shows no pending overlay or its frame lands in another window; the stale result closes or replaces the third overlay before the checks run. Not when it does so after them (finding 12), and not for the workspace restore at model 1568 (no reachable workspace, Dimension 1) |
| The other 30 | Unchanged: with no or one held call, `release()` behaves as before |

Conclusion: finding 12.

#### Dimension 4: Resource reuse

Counted from the targeted log, whole cases including fixture creation, model
start and teardown: A11 0.234 s, A12 0.246 s; the fastest dependent cases take
0.029 s (`terminationPreparationDoesNotUnregisterBeforeExitIsCommitted`,
`historyImageRemainsVisibleWhileSameRecordReloads`) and 0.035 s, so the
per-test fixture stays far below 1 s, and longer cases add flows on it. The
`FixtureCapture` change adds no resource. No resource reaches 1 s, so there are
no load counts to compare and no shared resource that a case clears; the
collection-order check does not apply.

Conclusion: no finding.

#### Re-check of earlier findings

| Finding | State at `533de26` |
|---|---|
| 2 | Open: `capabilities.toml` still absent |
| 8 | Unchanged: the case passes on the fixed code (targeted log 427-443); adding it to the gate and CI still waits on the user |
| 9 | Resolved: A11 asserts the toolbar at the final left edge |
| 10 | Resolved: `cancelCapture` clears the pending replacement, A12 fires one shortcut and expects admission, and REQ-005/AC-05 states the consequence. Finding 12 concerns only A12's post-release reading |
| 11 | Resolved: `logs/scripts/` keeps the three scripts (byte-identical to the session copies), and the targeted log names its manifest command |

#### Document sync check

Scope: this record and every file under
`docs/.workings/capture-instant-overlay/` (enumerated with `find`, hidden files
included;
`git ls-files --others --ignored --exclude-standard -- docs Tests AGENTS.md CODEX.md CONTEXT.md`
returned nothing); `docs/.workings/v1-core/checklist.md` REQ-005 rows (22-28);
`docs/specs/v1-core.md` (REQ-005 lines 66-78, §4 line 82, FM-23 and FM-25
lines 301 and 303, Testing Decisions 367 and 371); `docs/features/v1-core.md`
(lines 35, 37, 39, 49); ADR-0013; `CONTEXT.md`; root `AGENTS.md` and
`CODEX.md`; the test-file header. `git grep` for the two changed test names
and `FixtureCapture` finds them only in the test file, this record,
`review-code.md`, the checklist and the two targeted logs, so other
directories are excluded.

Facts from the fix range and its targeted run: `cancelCapture` clears a
pending replacement and calls its workspace restore; AC-05 gained a sentence;
A11 and A12 rewritten; `FixtureCapture` holds several calls; scripts kept; all
32 dependent tests pass. Facts this round establishes: finding 12; the
workspace restore has no reachable workspace.

| Document | Statement | State |
|---|---|---|
| This record, row A12 and item 2 of the self-check of the findings 9-11 fix | "stays visible: the stale second result does not touch it"; "fails if the stale second result replaced or closed the third capture's overlay" | Overstated (finding 12) |
| This record, the previous round's Document sync check | `checklist.md` line 25 "overstated until finding 9 is resolved"; `final-regression.md` line 18 "contradicted by findings 9 and 10"; `tasklist.md` line 74 "not met in finding 10's window"; spec and features contradicted in that window | Superseded at `533de26`: findings 9 and 10 are resolved, so these documents are true again; that table records its own version `da94f5c` |
| `checklist.md` lines 25 and 27 (AC-03, AC-05) | A11 for 冻结前开始、帧到达后完成的选区; A12 for 请求失效 | True |
| `final-regression.md` line 18 and closeout | REQ-005 true apart from the Pending and the header gaps; re-check after this review | No longer contradicted by findings 9 and 10; finding 12 names no undriven clause; the report's own re-check is still due |
| `tasklist.md` line 74 (AC-01 "Met") | Admission shows the overlay immediately | True (A12) |
| `tasklist.md` line 78 (spec final check, AC-05) | Quotes AC-05 without the added sentence; "workspace restore unchanged" | Stale since the fix: the added sentence is checked in `review-code.md` (fix section, self-check item 1), and `cancelCapture` now also calls a restore that has no reachable workspace. No test conclusion depends on the row; for the implementer's next update of the spec final check |
| `review-code.md`, fix section | "Reproduced before the fix by `displayChangeWhileReplacingAbandonsPendingCapture` (deadline at the admission wait)"; "restores its reserved workspace" | The first agrees with the code at `da94f5c` and the scratch red log; the second describes a call with no reachable workspace (Dimension 1), a code statement no test conclusion depends on |
| `logs/` | Targeted log and kept scripts | True |
| Test-file header lines 34-44 | Gap list | True; no new gap |
| Spec AC-01 and AC-05 (lines 70, 74), §4 (82), Testing Decisions 371 | Admission shows the overlay; the added AC-05 sentence; toolbar at the selection's lower left; REQ-005 composition observables | True against the implementation and A11, A12 |
| Features lines 35, 37, 39, 49 | Selection view at capture start; rectangle drawn before the frame kept; display changes; workspace after failure or Escape | True |
| ADR-0013, `CONTEXT.md`, `measurements.md`, `native-thrown-operation-run.txt`, `locked-session-toolbar-timeouts.txt` | No statement on these facts | Unaffected |
| Root `AGENTS.md`, `CODEX.md` | "项目能力" section | Finding 2, open |

No sync item is completed by this round.

### Findings

2. **Capability declaration missing; `mutation-testing` unconfirmed.**
   Required by the global capability rule: 项目无能力声明文件; 未确认
   mutation-testing; 未确认 working-language. Evidence: no `capabilities.toml`
   at the repository root (checked directly); root `AGENTS.md` carries a
   "项目能力" section (i18n), which belongs in `capabilities.toml` with only a
   pointer line in `AGENTS.md`; this record's header (lines 5-8) chose
   "mutation checks are performed (the stricter choice)", deciding the value
   for the user. Impact: this round can neither run nor skip the mutation
   check; the language of this record and its fixed names, and the gate's
   lint and e2e decisions, rest on unconfirmed IDs. Recommendation: ask the
   user or run `/repo-scaffold`; the registry's recommended answers are the
   defaults, `[mutation-testing] enabled = false` and
   `working-language = "en"`. If mutation testing is enabled, an incremental
   round runs it on A1-A10 and U1-U2.

3. **The record maps the tests to a non-existent `REQ-003/AC-01-05`, and
   coverage is not reconciled with REQ-005.** Category: untrue record.
   Evidence: lines 17-21 and every spec cell of the test design table; spec
   line 248 (REQ-003 is the interface language) and lines 66-76 (REQ-005,
   numbered differently: the record's AC-02/03/04/05 are REQ-005's
   AC-03/04/05/07, and AC-06 has no row); the checklist (line 31) records the
   renumbering. Clauses with neither a case nor a recorded gap: AC-01 overlay
   on every connected display (A1 looks only at `NSScreen.main` on a
   one-display machine); AC-02 no desktop flash (ordering inside
   `presentPending` and `commit`, not observable in process); AC-06 a display
   connected before the freeze completes is not selectable (needs hot-plug
   while pending). Recommendation: rewrite the spec column and the Dimension 1
   table against REQ-005 and re-review the changed rows; record the three
   environment-bound clauses in the test-file header with re-test conditions
   (two displays, compositor capture, hot-plug), or let A1 require a pending
   overlay on every `NSScreen` so multi-display runs check it; update checklist
   rows 25, 27 and 28.

4. **REQ-005/AC-03 input ownership while pending is only partly driven.**
   Category: regression that would be missed. (a) Keyboard: every `Esc` goes
   through `pressEscape` (`ProviderApplicationTests.swift` 1725-1730) straight
   to the overlay window, and no case checks that the pending overlay is the
   key window, which `pendingPanels.last?.makeKey()`
   (`FrozenCaptureOverlayController.swift` 70) provides; in the app, a
   non-key pending overlay leaves `Esc` with the previously key window.
   Whether deleting that line turns any case red depends on AppKit's
   first-responder setup and needs a mutation run (finding 2). The state is
   observable in process: the gate log's trace (line 99) shows the test
   process active with the overlay as key window. (b) A rectangle begun before
   the frame and finished after it: A2 releases before the frame and only A10
   may hit this by timing; `attach` (line 243) finishes only a completed drag,
   so an `attach` that reset an in-progress drag would keep every case green.
   Recommendation: assert `pending.isKeyWindow` before `Esc` in A3, or deliver
   `Esc` through `NSApp.sendEvent`; add a case that holds the capture, sends
   mouse down and drag, releases the capture, waits for the frame, sends mouse
   up and expects the toolbar.

5. **REQ-005/AC-05 "request invalidated" is not driven.** Category:
   regression that would be missed. Evidence: the `captureRequestCanCommit`
   branch with `ownsRequest` (`VLMSnapperApplicationModel.swift` 1154-1167) is
   reached when a replacement capture is pending and a display change ends the
   previous, still-selecting capture: `captureDisplaysChanged` calls
   `cancelCapture` for it, which closes every overlay including the pending one
   and releases the shared lease, so the late result fails the lease check
   (`review-code.md`, Runnability row "Previous selection cancelled by a display
   change while pending"). No case drives it and no gap names it. Impact:
   removing `captureRequest = nil` from that branch would refuse every later
   capture (`perform` guard, line 1079) with all cases green. Recommendation:
   a case with a first capture left without a drag (as in A8's first
   iteration), `holdFrames`, a second shortcut, a geometry change plus
   notification (A9's pattern), expecting no overlay and `activity == nil`;
   then release, fire again and expect admission (`capture.requests == 3` and
   an overlay).

6. **FM-25 source interfaces during the pending phase are not driven.**
   Category: regression that would be missed. Evidence: spec line 303 (FM-25)
   and line 15 keep the menu panel and management center open under the
   pending overlay and hide them after the frozen frame; the model calls
   `onRetireCaptureSources` after `commit` (line 1202), wired in
   `VLMSnapperApplicationDelegate.swift` 149-151; no test references the hook
   or opens a source before capturing (search over `Tests`). Impact: moving
   the retirement to `presentPending` time keeps every case green.
   Recommendation: a delegate-level case with `withApplication` and
   `holdFrames` that opens the management center, fires the shortcut, expects
   it visible while pending and hidden after the frame; the same for the menu
   panel if its window is reachable in the fixture.

7. **The late-result coverage row and A6's lease claim overstate the
   evidence.** Category: untrue record. Evidence: the Dimension 1 row "Late
   freeze result after cancellation is discarded | A3, A5, A6", while row A5
   says it is not asserted there; A6's post-release checks are not ordered
   after the late result (Dimension 3); A6's "single shared lease released
   exactly once" is shown only as "released", and with `lease == owner` the
   admission wrapper never releases it a second time
   (`ApplicationWorkflow.swift` 41). Coverage impact: none; A3 and A7 assert
   the discard through the same generation guard, and the replacement case
   adds no branch to it. Recommendation: correct the row to A3 and A7 and drop
   "exactly once" from row A6 and from the test comment
   (`ProviderApplicationTests.swift` 1150).

8. **The native case guarding the changed fixture cleanup has no run after
   the change.** Category: regression that would be missed (run evidence).
   Evidence: `cb19ef2` changes `stopFixture`, `withModel` and
   `withApplication`; `testThrownNativeOperationReleasesViewsWithoutChangingExistingWindows`
   (line 44) checks that contract (fixture views released after a throw or
   cancellation, the pre-existing window untouched; spec line 367).
   `Scripts/test-local-regression.sh` runs only the paste and closed-window
   native cases (lines 52-55), and so does CI (`ci.yml` lines 44 and 50); the
   only run of this case in this change is the scratch log from 16:11, before
   `cb19ef2` (16:43). Header line 24 says CI runs these cases. Impact: a
   cleanup change that touched pre-existing windows or kept fixture views
   alive would pass the gate. Recommendation: now, run the case once on
   `8bd52f2` and keep the log with this change's evidence. The gate and CI
   omission predates this change: recommend adding the case to both as a
   separate task; it has no durable home, so the user decides whether to file
   it.

Incremental round (fix `8bd52f2..da94f5c`, 2026-10-28). Finding 2 remains open
and blocks the mutation check of this round's objects; findings 3-8 are
re-checked in the round's table above.

9. **A11 cannot see a selection completed when the frame arrives instead of
   at mouse-up.** Category: regression that would be missed. Evidence:
   `attach` finishes a drag only when `completedBeforeFrame` is set
   (`FrozenCaptureOverlayController.swift` 215, 246-249, 291-293); an
   `attach` that finished any drag in progress would confirm the selection
   while the mouse is still down. A11 reads `captureToolbar() == nil`
   (`ProviderApplicationTests.swift` 1243) in the main-actor turn in which
   `eventually` saw the frame, while the toolbar of such an early completion
   needs three session-actor hops and the crop
   (`VLMSnapperApplicationModel.swift` 1293-1311); the mouse-up lands on the
   last drag point (1240, 1244), so the completed rectangle is the same either
   way, and the later mouse-up completion is refused as `inactiveSession`
   (`CaptureSelectionSession.swift` 146-147) and swallowed (model 1314-1318).
   Impact: dropping that condition from `attach` keeps A11 green (analysis;
   no mutation run, finding 2). Recommendation: after the frame, move the drag
   to a point that changes the selection's lower-left corner, then mouse up,
   and assert that the toolbar is anchored to the final rectangle
   (`CaptureToolbarPlacement.origin`: x from the selection's minX, y below its
   minY); or wait a bound that covers A2's toolbar latency before asserting no
   toolbar. Update row A11 and re-review it.

10. **A12 retries the shortcut and so accepts a refusal that REQ-005/AC-01
    does not allow; its table row expects one shortcut.** Category: defect
    (the test masks a deviation) and untrue record. Evidence: when a display
    change ends the selection being replaced, `cancelCapture` for the active
    generation releases the activity and closes every overlay
    (`VLMSnapperApplicationModel.swift` 1552-1564) but leaves the pending
    replacement's `captureRequest`, which is cleared only when the stale
    freeze returns (1154-1167). A shortcut in that window gets a fresh lease
    from the workflow (`ApplicationWorkflow.swift` 27), is refused by
    `guard captureRequest == nil` (model 1079) and its lease is released
    (workflow 40-41): no overlay, no feedback. REQ-005's scope and AC-01 (spec
    lines 68, 70), §3 (line 42) and features line 35 require the overlay once
    Provider, permission and activity admit the shortcut; `Esc` while pending
    clears the request at once (`abandonPendingCapture`, model 1230-1238).
    A12 states the refusal as expected and fires a shortcut every 50 ms for up
    to 5 s (`ProviderApplicationTests.swift` 1275-1282, `requests >= 3`); row
    A12 expects one further shortcut to be admitted (`requests == 3`).
    Impact: in the app, a shortcut pressed after a display change ends the
    selection being replaced and before the stale freeze returns (100-200 ms
    per display, ADR-0013) is silently dropped, and A12 stays green.
    Recommendation (user decision, as it changes product code or the spec):
    (a), recommended because AC-01 already requires it and `Esc` behaves so,
    clear the pending request when the selection it replaces is cancelled,
    and let A12 fire one shortcut while the stale capture is still held,
    expecting admission (`requests == 3`, an overlay), then release and check
    that the stale result leaves the new capture alone (the fixture's single
    `waiter` must then hold two suspended captures); (b) accept the window,
    state it in REQ-005 and the features catalogue, and change row A12 to the
    bounded retry. Either way the row and the test must agree, with the row
    re-reviewed under the design review's increment rule.

11. **The run scripts behind both handed logs are not kept, and the targeted
    log omits its manifest command.** Category: untrue record and evidence.
    Evidence: `logs/targeted-findings-fix.log` lines 13-21 print the manifest
    under `-- manifest` without the command that produced it (a gate log
    requirement; the per-file `git hash-object` loop is visible only in
    `targeted.sh`). Both logs' `== exit:` lines and the gate log's
    `<scratch rg shim>` PATH are explained only by `targeted.sh`, `gate.sh`
    and `bin/rg` in the session scratchpad, which the first round's Run
    evidence cites by session path and which disappear with the session;
    `tasklist.md` 91-94 keeps the logs but not the scripts. Impact on results:
    none, the manifest hashes equal the blobs at `da94f5c`; after the session
    the logs alone cannot show how the manifest and the exit codes were taken.
    Recommendation: keep the three scripts next to the logs in `logs/`, list
    them in `tasklist.md` and point the first round's Run evidence to them; no
    rerun.

Incremental round (fix `da94f5c..533de26`, 2026-10-28). Finding 2 remains open
and blocks the mutation check of this round's objects; findings 8-11 are
re-checked in the round's table above.

12. **A12's post-release checks are not ordered after the stale second
    result, yet its row and the fix's self-check say they show that result
    leaves the third capture alone.** Category: untrue record. Evidence:
    `release()` resumes both held calls (`ProviderApplicationTests.swift`
    2236-2242), and each continues on its own task: `startCapture` runs on the
    generic executor (`CaptureFreezeCoordinator.swift` 73-99; language mode 6
    without `NonisolatedNonsendingByDefault`, `Package.swift` lines 1 and 142)
    before `beginCapture` resumes on the main actor. The checks
    `replacement.isVisible` and `mainScreenOverlay() === replacement`
    (1287-1288) run in the main-actor turn in which `eventually` first sees the
    third frame (1286), and nothing observable marks the stale result as
    handled; when the third result reaches the main actor first, the checks
    precede anything the stale result does. Row A12 says "stays visible: the
    stale second result does not touch it", and item 2 of the self-check of
    the findings 9-11 fix says the identity check "fails if the stale second
    result replaced or closed the third capture's overlay". Impact: no
    behaviour of the current code goes unguarded, because the stale result is
    inert through two independent generation checks
    (`VLMSnapperApplicationModel.swift` 1141 and 1249) that a stale-first run,
    which the resume order favours, still exercises; but a regression letting
    the stale result close or replace the third overlay is caught only in that
    ordering. Recommendation: reword row A12 and that self-check line to what
    the checks show (the third capture's frame in the same, still visible
    window, read once when it appears; the stale result is usually, not
    necessarily, handled first), with no test change, and re-review the row
    under the design review's increment rule. Making the stronger claim hold
    would need an observable for the stale result's handling, which neither
    the model nor the fixture offers.

### Handling of incremental-round findings 9-11 (2026-10-28)

| Finding | Handling |
|---|---|
| 9 A11 blind to completion at frame arrival | A11 keeps dragging after the frame arrives so the left edge moves from 300 to 150, then asserts the toolbar's left edge at the final selection's left edge (spec §4); row A11 re-reviewed |
| 10 A12 accepted a refused shortcut | Product defect fixed: cancelling the selection a pending capture replaces now clears that request at once (`cancelCapture`, active branch). A12 fires one shortcut while the stale freeze is still held and expects admission; it failed first on `da94f5c` at that wait (deadline, line 1281) and passes after the fix. `FixtureCapture` now holds several suspended captures. REQ-005/AC-05 states the consequence; row A12 re-reviewed |
| 11 Scripts not kept; manifest command missing | `logs/scripts/` keeps `gate.sh`, `targeted.sh` and `rg-shim` (the scratchpad `bin/rg` behind the `<scratch rg shim>` PATH). Both scripts now also print the manifest command; the kept copies differ from the versions that produced `gate-pre-review-8bd52f2.log` and `targeted-findings-fix.log` only by that added echo line. The first round's Run evidence cites the scratchpad paths; the kept copies are these files |

Pre-handoff self-check of this fix (items 2-5):

- Item 2: A11's new assertion compares the toolbar's left edge with a value
  from the spec rule (left alignment) and the input point, not from
  `CaptureToolbarPlacement`; it fails by 150 pt if completion happens at frame
  arrival. A12's admission wait fails if the shortcut is refused (shown red);
  its final checks read the third capture's frame in the same, still
  visible window once, when it appears; they are not ordered after the stale
  second result, so they detect that result closing or replacing the third
  overlay only when it was handled first (corrected for finding 12).
- Item 3: `cancelCapture` (product) gained one branch-free step; both callers
  enumerated in `review-code.md`. `FixtureCapture.release` resumes every held
  continuation; its holders are `holdFrames` captures and the suspended
  permission path, both driven by existing tests (A4, the exclusivity test).
- Item 4: no new data shapes.
- Item 5: `FixtureCapture` users: every composition test (same file), all in
  the targeted run of this fix.

Self-check result: no finding.

### Handling of incremental-round finding 12 (2026-10-28)

Records only, as recommended: row A12 and item 2 of the self-check for the
findings 9-11 fix now state what A12's final checks show (the third frame in
the same, still visible window, read once when it appears; the stale result is
usually, not necessarily, handled first). No test or code changed. Row A12
re-reviewed under the increment rule: coverage claim now matches the
observable; case design and resources unchanged; no false-green claim remains.
Self-check of this fix: items 2-5 not applicable (no test, data or helper
change); no finding. Whether a further incremental review is needed is decided
by `change-scope.mjs` (recorded in `tasklist.md`).

### Increment: overlay window-open animation (2026-10-28, user report)

Design table row U3 (written before the test; implementation base `17dbf8d`):

| Row | Spec item | Seam | Driving input | Assertion and expected value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| U3 | v1-core::REQ-005/AC-01 (first overlay frame covers the whole display, no opening animation) | `FrozenCaptureOverlayController.presentPending` | one call; no frames | every visible `.screenSaver` window has `animationBehavior == .none`; expected value from AC-01 and AppKit's documented behavior values | none | none |

Design review of U3:
- Dimension 1: AC-01's new clause has no in-process behavioral observable;
  frame and window-server bounds stay at the screen size while the animation
  plays (probe in `measurements.md`), so U3 asserts the window property that
  decides it, and the test file header of the app tests records that the
  visible effect was checked by screen recording.
- Dimension 2: public seam; the windows are read back through `NSApp.windows`
  as in U1; state reached through the public call only.
- Dimension 3: it turns red when an overlay window keeps the default
  animation; an empty window list cannot pass (non-empty asserted first).
- Dimension 4: no expensive resource.

Post-implementation check of U3: written as designed; red with the
`animationBehavior` line removed, failing on that expectation only
(`logs/animation-red.log`); green with the fix (`logs/animation-green.log`).
The full offline gate run after this commit is recorded in `tasklist.md`.

Findings: none.
