# Capture selection adjustment, Copy and Save — test review

No ticket (`/to-tickets` no-ticket entry): spec implementation of v1-core::REQ-007–009 on
`feat/capture-adjust-copy-save`. Testing scope by the user's instruction (2026-10-29): capture tests only.

## Design review (2026-10-29)

Implementation base: `c38e2bb`. Scope: every test planned for REQ-007 AC-01–07, REQ-008 AC-01–02, REQ-009
AC-01–04 and FM-48.

### Test design table

Seams: S1 `CaptureSelectionSession` public API (Core); S2 `FrozenCaptureOverlayController` with events sent
to its real panels (as the REQ-006 tests); S3 the application composition fixture with injected clipboard and
save adapters (as the REQ-006 app tests). Expected values are literals or hand-computed corners.

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| C1 | REQ-007/AC-05, AC-07 | S1 | finish a selection, then begin/update/finish a second rectangle on the same display | first and second crops have the two rectangles' pixel sizes; state stays selectable until cancel; frames kept (second crop succeeds) | synthetic frozen display (existing helper) | none |
| C2 | REQ-007/AC-06 | S1 | after a selection, finish a 1 × 1 px rectangle | `selectionTooSmall`; a later valid re-selection still crops | same | none |
| C3 | REQ-007/AC-07 | S1 | after a selection, the display's geometry changes | display invalidated; re-selection on it fails `displayUnavailable` | same | none |
| C4 | REQ-008/009 (capture ends) | S1 | cancel after a selection | state cancelled; no further selection | same | none |
| U1 | REQ-007/AC-01 | S2 | complete a selection | rendered handles: opaque pixels at the eight handle centres; none at those points before completion | two-window resolver (existing) | none |
| U2 | REQ-007/AC-02 | S2 | drag the bottom-right corner handle by (−100, +50) points; then the top edge handle up 30 | `onSelection` frames: corner moves both sides, edge moves one (hand-computed) | same | none |
| U3 | REQ-007/AC-02 | S2 | drag the left edge handle past the right edge | normalized rectangle (hand-computed) | same | none |
| U4 | REQ-007/AC-03 | S2 | drag inside the selection by (40, −20); then towards the screen edge beyond it | moved frame, same size; clamped to the display | same | none |
| U5 | REQ-007/AC-04 | S2 | press outside the selection and click | a new selection (the snap region at that point) | same | none |
| U6 | REQ-007/AC-06 | S2 | resize to under 2 × 2 px | no `onSelection`; rendered selection back at the previous rectangle | same | none |
| A1 | REQ-008/AC-01 | S3 | select a window; press Copy | fixture clipboard holds PNG bytes of the selection's size (decoded width × height = window × scale); overlay and toolbar gone; history count unchanged; no provider request | snap fixture (existing) | app composition (existing per-test fixture) |
| A2 | REQ-009/AC-01–02 | S3 | select; press Save; fixture save panel returns a temp file URL | file holds the PNG (decoded size as A1); suggested name matches `vlmsnapper-yyyyMMdd-HHmmss.png`; capture closed; history unchanged | same | same |
| A3 | REQ-009/AC-03 | S3 | select; press Save; fixture panel cancels | overlay and toolbar remain; a following Copy still works | same | same |
| A4 | REQ-007/AC-05 | S3 | select; drag a handle; then Copy | clipboard PNG has the adjusted size; toolbar's top 4 pt below the new bottom edge (hand-computed) | same | same |
| A5 | REQ-007/AC-07 | S3 | select; then the selection's display geometry changes | overlay and toolbar withdrawn; history unchanged | display notifications fixture (existing) | same |
| U7 | REQ-007/AC-01, FM-48 | S2 | drag a 10 × 0.25 pt rectangle (under 2 px); press on its corner | no handles: the press starts a new selection, the whole display (literal screen frame) | two-window resolver, display pixels at the screen scale | none |
| U8 | REQ-007/AC-01, AC-06 | S2 | at 2 px per point drag 10 × 0.75 pt across a pixel row (cropped as 2 px); press on its bottom-left corner | handles present: the press adjusts and reports the same rectangle again (hand-computed) | two-window resolver, display at 2 px per point | none |
| U9 | REQ-007/AC-01 (prototype colours) | S2 | confirm a selection; render in light, then dark appearance | pixel inside the top-left handle: red above 230 in light, below 60 in dark (prototype surface `#ffffff` / `#2c3138`) | two-window resolver | none |
| A6 | REQ-007/AC-05, FM-48 | S3 | select; release two adjustments before the main actor yields; Copy | clipboard PNG has the second adjustment's size (250 × 175 pt × scale, hand-computed) | snap fixture | app composition (existing per-test fixture) |
| A7 | FM-48 (one action per click) | S3 | select; two clicks on Save before yielding, the panel cancels; then Copy | one save request; Copy still works after the cancelled panel | snap fixture | same |
| U10 | REQ-009/AC-04, FM-48 (alerts over the overlay) | S2 | show an alert through the controller; end it with the second button; click window A | the alert is the overlay's attached sheet; the response is the second button; once detached the overlay is key again and the click selects window A (literal) | two-window resolver | none |
| U11 | REQ-009/AC-04, FM-48 | S2 | pause selection; click and drag; another panel takes the keyboard; resume; click window A | no selection while paused; the overlay is key again after resuming; the click selects window A | two-window resolver | none |
| A8 | REQ-009/AC-04 | S3 | select; Save with the fixture panel held open; press outside and drag a handle; release the panel cancelled; Copy | toolbar stays; Copy gives the window's size (300 × 200 pt × scale) | snap fixture with a held save answer | app composition (existing per-test fixture) |

Not covered by tests (gap notes in the test files): the real system save panel and clipboard (installed
build), the modal failure alerts of REQ-008/AC-02 and REQ-009/AC-04 (modal `NSAlert`, as the existing
diagnostics export), cursor shapes over handles (AppKit cursor rects; installed build), withdrawing a settled
selection when a new one starts on another display (needs two displays; installed build), and the window
layer the save panel and alerts land on (the test process keeps levels that the sandboxed app's modal
sessions change; measured with a sandboxed probe, checked on the installed build).

### Incremental design review (2026-10-29, code review)

Rows U7–U9, A6 and A7 come from the code review (`review-code.md` findings 1 and 3–5). They were written
as bug-reproduction tests together with these rows and run red before the fixes; the table was updated right
after the red runs rather than before the tests were written. Reviewed here on the same dimensions:
coverage — each maps to a FM-48 boundary or REQ-007/AC-01; the another-display boundary has no row (gap
above). Case design — public seams only (events to the production overlay, injected clipboard and saver).
False greens — expected values are literals or hand-computed; A6 decodes the PNG size; A7 asserts after a
later Copy has run, so both save clicks have been handled when the count is read; U9 reads rendered
pixels, not the layer's colour property. Resources — no new expensive resource. No findings.

### Dimension 1: Coverage

Every AC maps to a row except the modal failure alerts and cursor shapes (recorded gaps). FM-48 items map to
U2–U6, A1–A5. The fixture shapes are the existing synthetic frozen display and snap fixture; clipboard and
save adapters are injected doubles at the app boundary.

### Dimension 2: Case design

Public seams; results read through the selection callback, rendered layers, the injected adapters and the
history query, as the existing capture tests do.

### Dimension 3: False greens (design-time checks)

Expected rectangles are literals; PNG sizes are decoded from the bytes, not taken from the request; history
"unchanged" is compared against a count read before the action (non-zero not required, but read through the
public query).

### Dimension 4: Resource reuse

Application composition per test as existing capture tests; no new expensive resource.

### Findings

None.

### Incremental design review (2026-10-29, installed-build feedback: Save did nothing)

Rows U10, U11 and A8 (`review-code.md` findings 6–8). U10 replaces the old "failure alert stays visible
above a retained overlay" test, which only read the level property set before the modal session — the
property the sandboxed app's modal session then changed, so it could not catch this defect. A8 and U10 were
run red before their fixes (A8: `logs/save-red-hold.log`; U10: `logs/save-red-alert-key.log`). A real-panel
adapter test was written and removed (process exits silently after the panel closes; see `review-code.md`).
Coverage: AC-04 now has rows; the layer itself is a recorded gap. Case design: public seams (controller API,
events to the production overlay, injected saver). False greens: U10 waits until the sheet is detached
before the click, because AppKit drops presses during the sheet's exit animation; every capture run now
requires the test summary line. Resources: none new. No findings.

