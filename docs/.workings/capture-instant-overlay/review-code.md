# Instant capture overlay code review

Date: 2026-10-28. Range: `850f64d..e3c41d5` plus the review fixes committed
after it. Scope: pending overlay before the freeze, layer-backed overlay
rendering, commit/rollback/abandon paths in the application model, toolbar
suspend/resume. No ticket.

## Underlying premises

- The pending overlay is on screen while ScreenCaptureKit freezes, so the
  change now depends on the freeze filter excluding VLMSnapper's own windows
  (`SCContentFilter(display:excludingApplications:)` with the current process,
  introduced earlier for self-exclusion). Measured with the production capturer
  and controller on macOS 26.0.1: the frame frozen under the visible 48 % scrim
  has the same luma as a reference freeze (236.4-236.8 vs 236.9), see
  `measurements.md`. `NSWindow.sharingType` is not relied on: ScreenCaptureKit
  handles it inconsistently (Apple Developer Forums thread 808016, where DTS
  asked for a bug report), and third parties report a behaviour change from
  macOS 15; it happened to be honoured in a macOS 26 probe, which is not a
  guarantee. macOS 14.4-15 relies on the
  documented application exclusion; the spec already assigns compositor
  exclusion to signed-app acceptance.
- Layer backing: `wantsLayer = true` creates the backing layer before the
  sublayers are added (pending dim visible in the real screenshot), and
  `viewDidChangeBackingProperties` gives the shape layers the Retina scale on
  first presentation (measured `contentsScale` 2.0 on a 2.0 backing panel).
- The menu panel is a custom `.popUpMenu` panel closed only by explicit hide or
  its mouse-down monitors; the pending overlay becoming key does not close it.
- New causal comments were checked against evidence; two overstated ones were
  reworded (the frozen frame does not replace the live screen "pixel for pixel"
  where VLMSnapper windows were visible, and exclusion is a property of the
  freeze filter, not a guarantee for every system).

Conclusion: premises hold on the measured system; macOS 14.4-15 compositing
remains a signed-app acceptance item (unchanged ownership).

## Runnability

States of a capture request after this change: pending (fresh, replacing a
selection, replacing a terminal result workspace) and committed. Exits from
pending, each checked against the implementation:

| Exit | Overlay | Toolbar | Workspace | Lease |
|---|---|---|---|---|
| Commit succeeds | Frames attached to pending panels; panels without a frame and the previous overlay retired | Hidden | Retired | Kept by the new selection |
| Commit finds no framed panel | Rolled back to previous overlay | Resumed | Restored | Released only if no selection remains (existing rule) |
| Permission required / all displays failed | Rolled back | Resumed | Restored | Same as above |
| Request can no longer commit (still owned) | Rolled back | Resumed | Restored | Unchanged |
| Request cleared by someone else | Untouched (owner withdrew it) | Untouched | Not restored again | Unchanged |
| `Esc` while pending | All overlays closed (previous selection cancelled too) | Hidden | Restored | Released by the selection cancel, or by the admission wrapper after the freeze returns |
| Termination preparation while pending | Same as `Esc` | Same | Same | Same |
| Previous selection cancelled by a display change while pending | All overlays closed by its cancel; the pending request then fails the lease check and stays closed | Hidden | n/a | Released once |

Selections released before frames arrive are completed when the frame is
attached; the model's `finishSelection` task runs after commit has set the
active generation and session (no suspension point between them).

Findings in this layer:

1. **Clicks escaped to other applications while pending (fixed).** The pending
   panel is non-opaque and a completed selection leaves a fully transparent
   hole in the scrim. Reproduced with posted HID events (Accessibility-trusted
   harness, own window placed underneath): a second click inside the hole was
   delivered to the window underneath and not to the overlay. Escape surface:
   upper (a click reaches an unrelated application). Fix: the overlay panel sets
   `ignoresMouseEvents = false` explicitly; the same reproduction then delivers
   the click to the overlay (new selection started, hole closed, underlying
   window received nothing). Not reproducible in the test suite because
   `sendEvent` bypasses window-server hit testing and CI has no Accessibility
   trust; recorded in the test file header. Class check: every non-opaque
   window was enumerated (`grep -rn 'isOpaque = false' Sources VLMSnapper`):
   the capture overlay (fixed), the operation toolbar (only rounded corners are
   clear and it sits above VLMSnapper's own overlay) and the menu panel (clear
   area around its arrow, conventional popover click-through, unchanged by this
   work). Two others checked, none with the same exposure.
2. **Abandoned request could undo a newer request (fixed during implementation).**
   If `Esc` cleared request A while A was suspended in display revalidation and
   a new shortcut started request B, A's "cannot commit" branch would have rolled
   back B's pending overlay and un-reserved B's workspace. That branch now acts
   only while A still owns the request.

3. **Test fixture skipped windows whose address was reused (fixed).** Found by
   the pre-review gate: `escapeWhileFreezingFromResultRestoresWorkspace`
   failed in fixture teardown (shortcut lease never released) in 4 of 21 app
   suite runs before the fix and 0 of 15 isolated runs. Teardown diagnostics showed the model
   was still alive 35 s later and that `stopFixture` had skipped the result
   window holding `NSHostingController<ResultWorkspaceView>` as "pre-existing",
   although the test created it. The fixture recorded pre-existing windows as
   `ObjectIdentifier`s; a window alive at test start was freed during the test
   and the new result window reused its address, so its view graph (whose
   `Binding` retains the model) was never cleared. Escape surface: upper (a
   later fixture deadline fails an unrelated, passing test). Fix: keep strong
   references to the pre-existing windows and compare by identity. Class check:
   every `ObjectIdentifier` use was enumerated
   (`grep -rn 'ObjectIdentifier' Tests Sources VLMSnapper`); the three fixture
   sites shared one helper and are all fixed; the only other use is
   `commit(displays:)`, whose identifiers come from panels the pending array
   keeps alive, so no address can be reused there. Confirmation: see the
   suite-loop result recorded in `tasklist.md`.

Conclusion: three bugs found and fixed; all enumerated exits end in a defined
state.

## Security

No new input, persistence, credential, network or logging surface. The
self-exclusion filter still fails closed when the current process cannot be
resolved. The behavioural dependency added here (overlay visible during the
freeze) would degrade to a darker screenshot, not to a disclosure, if an OS
release stopped honouring application exclusion; the click-through escape
above was the only cross-application effect found and is fixed.

Conclusion: no open finding.

## Consistency

- Contract change: `docs/specs/v1-core.md` (Solution, §3, FM-25) and ADR-0010
  state that the overlay appears only after every display is frozen. The
  presentation order changes; the decision goes to a new ADR that supersedes
  that part of ADR-0010, and the spec is rewritten in the spec final check.
- Removed API `replace(displays:onSelection:onCancel:)`: no remaining reference
  (`grep -rn 'replace(displays' Sources VLMSnapper Tests` is empty).
- Smell baseline on touched code: no speculative generality (every new entry
  point is called by the model), no duplicated logic in production code; the
  new composition tests repeat the fixture preamble exactly like the existing
  tests in the same file (kept for local consistency). `NSScreenNumber` lookup
  also exists in `CaptureDisplayMonitor.swift` (pre-existing, outside the
  change; recorded only).

Conclusion: contract documents must be updated (tracked in the tasklist); no
code finding.

## Refactor list (not executed)

| Item | Reason | Escape surface | Recommendation |
|---|---|---|---|
| Prepare the next pending panels ahead of time | `presentPending` measured 4-11 ms, mostly window creation; a prepared set would be about 1 ms | Self (latency only) | Not now: already below one 60 Hz frame; adds lifecycle handling for display changes and memory for hidden panels |
| Overlay scrim and border colours are AppKit literals, not theme tokens | ui-design colour rule; values unchanged from the previous `draw(_:)` | Self | Do not change: the scrim sits over a frozen screenshot and is appearance-independent by design; the border already follows the system accent |
| Modal capture-failure alert makes "every display invalidated before commit" untestable | Test gap documented in the test file header | Self | Separate task if desired: a non-modal failure presentation seam |

## Pre-handoff self-check after the post-implementation test review (2026-10-28)

Item 1 (product code changed by the fix, compared clause by clause with the
spec): not applicable; the fix for test-review findings 3-8 changes only tests,
the test-file header and records.

## Review of the fix for test-review finding 10 (2026-10-28)

Change: `cancelCapture(generation:)`, active-selection branch, also clears a
pending replacement request and restores its reserved workspace.

- Underlying premises: a request in flight while a selection is active is
  always a replacement sharing that selection's activity (`workflow.capture`
  reuses the owner's lease), so releasing the activity makes the request
  unable to commit (`captureRequestCanCommit` checks the lease). Reproduced
  before the fix by `displayChangeWhileReplacingAbandonsPendingCapture`
  (deadline at the admission wait; a shortcut pressed in that window was
  refused and its fresh lease released, with no overlay).
- Runnability: callers of the active branch while a replacement is pending are
  the display-change cancellation (the defect) and `abandonPendingCapture`,
  which clears the request first, so `replacement` is `nil` there and the
  workspace is not restored twice. The stale freeze then takes the
  generation-mismatch path (no overlay or workspace change) and its admission
  wrapper releases nothing, because the lease equals the owner. A capture
  admitted in between gets a new activity; the stale `perform` compares
  `captureLease` with its own lease and leaves the new one alone. Escape
  surface of the old behaviour: upper (a user shortcut silently dropped).
- Security: no new surface.
- Consistency: matches `Esc` while pending, which already cleared the request
  at once; REQ-005/AC-05 now states the consequence and AC-01 the admission.

Self-check item 1 (product code against the spec, clause by clause):
REQ-005/AC-01 "准入后立即……显示……选区遮罩" holds for a shortcut pressed after
the replaced selection ended (A12); AC-05's added sentence describes exactly
this branch; no other clause is touched.

## Review of the overlay window-open animation fix (2026-10-28, user report)

User report on the installed 0.1.2: after the shortcut the dim did not cover
the screen at first and then quickly grew to full size.

- Underlying premises: the overlay panel used AppKit's default
  `animationBehavior`, which scales a newly ordered window up from slightly
  smaller than its frame. The window's frame does not change during this, so
  no in-process observable (window frame, layer bounds, rendered layer) shows
  it; it is visible only in the composited output. Measured by screen
  recording (`measurements.md`, on-screen section).
- Runnability: `animationBehavior = .none` on the overlay panel; nothing else
  changes. Ordering, key status, exclusion from the frozen frame and the
  commit/rollback paths are unaffected (targeted run: App suite 29 tests,
  three native cases, overlay controller tests all pass,
  `logs/targeted-animation-fix.log`).
- Security: no new surface.
- Consistency: the menu-bar panel already sets `animationBehavior = .none` for
  the same reason. Class check, all app windows enumerated
  (`grep -rn -E 'NSPanel\(|NSWindow\(|: NSPanel|: NSWindow|animationBehavior' VLMSnapper Sources`):
  menu panel (already `.none`), capture overlay (fixed), capture toolbar panel
  (default; a small panel shown after the selection, not reported, left
  unchanged), management center, result workspace and onboarding (titled
  windows where the standard animation is expected).

Test: `FrozenCaptureOverlayControllerTests` gained "the pending overlay covers
each display without an opening animation" (visible overlay windows after
`presentPending` have `animationBehavior == .none`). Red first with the line
removed: failed on that expectation only, overlays present
(`logs/animation-red.log`); green with the fix (3 of 3 tests,
`logs/animation-green.log`). The property is the only in-process observable:
frame and window-server bounds already equal the screen during the animation
(`measurements.md`).

The finding was missed earlier because every check of the overlay looked at
its final state (still screenshots after presentation, rendered layers,
window frames); none looked at the frames during presentation.
