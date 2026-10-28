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
| A11 | `selectionStartedBeforeFramesFinishesAfterThem` (new; increment 2026-10-28 for finding 4b) | REQ-005/AC-03 (rectangle begun before the frame, finished after it) | Application model + real overlay controller | Held capture; mouse down and drag sent to the pending overlay; capture released; wait for the rendered frozen frame; mouse up sent | No toolbar before mouse up; toolbar appears after it. Expected from AC-03 (selection begun while pending is kept and cropped from the frame) | `syntheticDisplay()` | None |
| A12 | `displayChangeWhileReplacingAbandonsPendingCapture` (new; increment 2026-10-28 for finding 5) | REQ-005/AC-05 (request invalidated); REQ-001/AC-01-02 | Same | First capture committed without a drag (selection subscribed to display changes); held second capture; geometry change plus notification ends the first selection and releases the shared lease; geometry restored; capture released | After the change: no overlay and activity `nil`. After release and a further shortcut: the capture is admitted and freezes (`capture.requests == 3`, overlay on the main screen). A request left registered after the invalidated branch would refuse that shortcut. Expected from AC-05 and REQ-001 | `syntheticDisplay()` plus `changedGeometry` (existing helper) | None |
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
