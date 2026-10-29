# Capture selection adjustment, Copy and Save — task list

Scope: v1-core::REQ-007 (adjust a confirmed selection), REQ-008 (Copy), REQ-009 (Save), FM-48.
Branch `feat/capture-adjust-copy-save` from `c38e2bb`. User decisions (2026-10-29): four edge and four
corner handles, shown once confirmed; dragging inside moves; Save opens a save panel; Copy and Save close
the capture; Save icon is a floppy disk (custom vector; SF Symbols has none); prototype approved.

**Testing scope (user instruction 2026-10-29, "其他模块的测试不要测，只测截图")**: run only capture tests —
Core capture tests (`CaptureSelectionSession*`, `CaptureSnapRegion*`, `CaptureFreeze*`, `CaptureCoordinate*`),
the overlay and toolbar UI tests, and the App composition capture tests. The full local gate, which runs every
module, is not run for this change; deliveries state this.

## Design (code as of `c38e2bb`)

- Core `CaptureSelectionSession`: `finishSelection` currently crops, releases every frozen frame and
  becomes `completed`. New: it becomes `selected` and keeps the frames, so a later drag (adjusted rectangle
  or new selection) runs the same begin/update/finish path again and recrops; a new `commit()` releases the
  frames when an operation starts; `cancel()` also works from `selected`.
- App model: on a finished selection keep the display monitor running (REQ-007/AC-07: a display change ends
  the capture); each re-finish updates the PNG and moves the toolbar; Extract/Translate/Copy/Save commit the
  session first. Copy and Save use injected adapters (clipboard writer; save panel presenter + file write)
  so the composition tests read results back; live adapters use `NSPasteboard` and `NSSavePanel` (panel
  above the overlay level). Neither creates history.
- Overlay view: when settled, draw eight handles; mouse down on a handle resizes, inside moves, outside
  starts a new selection; cursor rects per handle and inside; on release send the new corners; a result under
  2 × 2 physical pixels reverts locally without calling back.
- Toolbar: Copy (existing `copy` icon) and Save (floppy vector) icon buttons before Close, localized tooltips
  "复制图片 / Copy Image", "保存图片 / Save Image".
- Entitlement `com.apple.security.files.user-selected.read-write`, asserted in `Scripts/verify-macos-app.sh`.

## Steps

- [x] Test design review (`review-tests.md`)
- [x] Slices: session re-selection/commit → overlay handles/adjust → toolbar buttons → app wiring (copy, save,
      adjust, display change) → entitlement
- [x] Targeted capture tests
- [x] Code review (`review-code.md`): five findings fixed with red-first tests; refactoring item R1 awaits the
      user's decision
- [ ] Capture-only pre-review run; independent post-implementation test check
- [ ] Spec final check, features catalogue, final regression, install, PR
