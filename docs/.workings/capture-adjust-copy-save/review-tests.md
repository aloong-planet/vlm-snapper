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
| A4 | REQ-007/AC-05 | S3 | select; drag a handle; then Copy | clipboard PNG has the adjusted size; toolbar moved to the new left edge | same | same |
| A5 | REQ-007/AC-07 | S3 | select; then the selection's display geometry changes | overlay and toolbar withdrawn; history unchanged | display notifications fixture (existing) | same |

Not covered by tests (gap notes in the test files): the real system save panel and clipboard (installed
build), the modal failure alerts of REQ-008/AC-02 and REQ-009/AC-04 (modal `NSAlert`, as the existing
diagnostics export), cursor shapes over handles (AppKit cursor rects; installed build).

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
