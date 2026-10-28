# Instant capture overlay test review

Scope: capture shortcut latency fix (pending overlay before freeze completion).
No ticket; records follow the no-ticket entry of the ticket-artifact rules.
Project has no `capabilities.toml`; `working-language` and `mutation-testing`
are unconfirmed. This record follows the English precedent of earlier
`docs/.workings/` records, and mutation checks are performed (the stricter
choice) rather than skipped.

## Design review

Date: 2026-10-28. Implementation basis: `850f64d`. Range: tests planned for
`Tests/VLMSnapperAppTests/ProviderApplicationTests.swift` (application
composition seam) and `Tests/VLMSnapperUITests/FrozenCaptureOverlayControllerTests.swift`
(overlay controller seam).

Spec items referenced as `REQ-003/AC-xx` are the pending-overlay acceptance
criteria this change adds to `docs/specs/v1-core.md` (`v1-core::REQ-003`):
AC-01 overlay before freeze and same-window commit, AC-02 selection made while
pending, AC-03 `Esc` while pending, AC-04 rollback on failure, AC-05
termination while pending.

### Test design table

| ID | Test | Spec items | Seam | Input that reaches the target branch | Assertion objects and expected-value source | Fixture shape source | Expensive resources |
|---|---|---|---|---|---|---|---|
| A1 | `overlayCoversDisplaysBeforeFreezeCompletes` (new) | REQ-003/AC-01; Further Notes performance target | Application model + real overlay controller | `FixtureCapture.holdFrames()` keeps `captureFrozenDisplays` suspended after admission; shortcut fired | While held: a visible `.screenSaver` window exists, `capture.requests == 1`, and the rendered overlay is translucent (no frozen frame). After release: the same window object renders the opaque frozen frame. Expected values from AC-01 (immediate overlay, frozen frame later, no window rebuild) | `syntheticDisplay()`: real `NSScreen.main` geometry with a white frame of the real pixel size | None (fixture plus model start measured at 0.3-0.45 s per test) |
| A2 | `selectionDraggedWhileFreezingCompletesWithFrozenFrames` (new) | REQ-003/AC-02; §3 rectangle selection | Same | Held capture; production `drag` helper sends down/drag/up to the pending overlay before release | No toolbar while held; toolbar window appears after release. Expected from AC-02 (selection kept, cropped from frozen frame) | Same | None |
| A3 | `escapeWhileFreezingExitsCapture` (new) | REQ-003/AC-03; §3 `Esc` exits without saving | Same | Held capture; `Esc` key event sent to the pending overlay; capture released afterwards | Overlay not visible after `Esc`; after release no `.screenSaver` window and no toolbar reappear, activity becomes `nil`, history empty, no image request. Expected from AC-03 and §3 | Same | None |
| A4 | `failedFreezeRestoresPreviousSelection` (new) | REQ-003/AC-04; FM-3; FM-25 | Same | First capture completes and a drag shows the toolbar; then `provide(nil)` plus `allowSuspendedCapture()` makes the next capture wait and throw `permissionDenied`; shortcut fired | While pending: previous overlay hidden, a different overlay visible, toolbar hidden. After release: pending overlay gone, previous overlay visible with content, toolbar visible again, activity still `.capture`. Expected from FM-3 (keep previous selection, no half-retired state) | Same; failure shape is the existing `permissionDenied` path of `FixtureCapture` | None |
| A5 | `terminationWhileFreezingWithdrawsOverlay` (new) | REQ-003/AC-05; FM-18 | Same | Held capture; `model.prepareForTermination()` called while held; capture released afterwards | `prepareForTermination` returns `true` while the freeze is still held (it does not wait for the freeze); no visible `.screenSaver` window immediately afterwards; history empty. The late-result discard after release is not asserted here: termination preparation cancels activity observation, so the stale-result guard it shares with `Esc` is asserted by A3 (increment reviewed 2026-10-28) | Same | None |
| A6 | `escapeWhileReplacingSelectionReleasesActivity` (new) | REQ-003/AC-03; FM-25 lease ownership | Same | First capture committed with toolbar; second shortcut with held capture; `Esc` on the pending overlay | All overlays and the toolbar hidden; activity eventually `nil` (single shared lease released exactly once). Expected from AC-03 | Same | None |
| A7 | `escapeWhileFreezingFromResultRestoresWorkspace` (new) | REQ-003/AC-03; FM-23 | Same | Full capture to terminal result (existing image-flow pattern); held capture; shortcut from the terminal workspace; `Esc` on pending overlay; release | Result window stays visible; a further shortcut is admitted and freezes (`capture.requests == 3`, overlay shown). A workspace still reserved for the abandoned capture answers `alreadyPrepared` and refuses that capture, so admission is the public observable of the restored reservation. Expected from AC-03 and FM-23 (workspace stays usable when capture is abandoned). Increment reviewed 2026-10-28: the first design clicked `Try Again`; a control run without any capture showed that clicking it immediately after the first result never starts a request in this fixture (fixed click coordinates against a result window still settling), so that click could not distinguish restored from reserved | Same plus existing DeepSeek SSE fixture shape (`FixtureHTTP.finishImage`) | None |
| A8 | `replacementAndEscapeRetireDisplaySubscriptions` (modified) | REQ-001/AC-07; FM-25 | Same | Existing input; waits additionally until the new overlay renders its frozen frame before checking retirement and subscriptions | Existing assertions unchanged (previous overlay retired, one display read per notification while subscribed, none after `Esc`/termination) | Existing | None |
| A9 | `displayChangesCancelSelectionBeforeMouseUp` (modified) | REQ-001/AC-01-03 | Same | Existing input; waits for the frozen frame before posting display changes | Existing assertions unchanged | Existing | None |
| A10 | `nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive` (modified, increment reviewed 2026-10-28) | §3; FM-23; REQ-003/AC-02 | Same | Existing input; the overlay to drag is the one on `NSScreen.main` (the screen the synthetic display freezes) instead of the first visible overlay | Existing assertions unchanged. Reason: with pending panels on every screen, the first visible overlay can belong to a screen without a frame on multi-display machines; the drag may now reach the pending panel before commit, which is the AC-02 path | Existing | None |
| U1 | `failedReplacementKeepsCurrentOverlay` (modified) | FM-3; REQ-003/AC-04 | Overlay controller | Present and commit one display; present pending; `commit(displays: [])` | Commit returns `false`; after `rollback()` the previous window is visible and `presentedDisplayIDs` unchanged | Existing `makeDisplay` (real `NSScreen` identity) | None |
| U2 | `failureAlertStaysAboveRetainedOverlay` (modified) | FM-3 | Overlay controller | Present and commit one display; prepare alert | Alert level above `.screenSaver` (existing expectation) | Existing | None |

Rendered-frame observable used by A1, A8, A9: render the overlay content
view's layer tree into a small bitmap and read the alpha at the centre. A
pending overlay over the live screen is translucent (scrim only); a committed
overlay shows the opaque frozen frame. This reads what the user sees, not
controller state, and its negative case is asserted in A1.

### Dimension 1: Coverage

| Spec boundary | Planned coverage |
|---|---|
| Overlay before freeze, frozen frame later in the same window (AC-01) | A1 |
| Selection completed while pending (AC-02) | A2 |
| `Esc` while pending, fresh capture (AC-03) | A3 |
| `Esc` while pending, replacing a selection (shared lease) | A6 |
| `Esc` while pending, replacing a terminal result workspace (FM-23) | A7 |
| Failure while pending restores previous selection and toolbar (AC-04, FM-3, FM-25) | A4, U1 |
| Termination while pending (AC-05, FM-18) | A5 |
| Late freeze result after cancellation is discarded | A3, A5, A6 (release after cancel, assert nothing reappears) |
| Display changes after commit (REQ-001) | A8, A9 plus unchanged existing tests |
| Validation removes every display before commit | Gap: this branch shows the modal capture-failure alert (`runModal`), which blocks the composition test; already untested before this change. Re-test condition: a non-modal failure presentation seam or a signed-app manual check |
| Several displays, one without a frame | Gap: needs two physical displays; controller-level empty commit (U1) covers the all-missing case only |
| Compositor excludes the pending overlay from the frozen frame | Gap for automated tests (spec already assigns compositor exclusion to the signed app); this change adds an in-process ScreenCaptureKit measurement with the production capturer and controller as supplementary evidence |

The gaps are written in the header of the modified test file.

Fixture independence: frozen frames are external ScreenCaptureKit data. The
fixture reproduces the real shape (one `CGImage` per display at the real
`NSScreen` pixel geometry), taken from the live screen rather than invented.
Failure shapes reuse the capturer's real error type (`CaptureDiscoveryError`).

Conclusion: every new boundary has a planned case; the three gaps are
environment-bound and documented.

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
