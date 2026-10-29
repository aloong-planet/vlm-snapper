# Capture selection adjustment, Copy and Save — code review

No ticket (`/to-tickets` no-ticket entry). Date 2026-10-29. Scope: `c38e2bb..a08f0b5` plus the fixes below
(uncommitted at the time of review, committed with this record): the session `.selected` state, overlay
handles, move, resize and re-selection, toolbar Copy and Save with the floppy icon, clipboard and save
adapters, model wiring (latest crop for actions, display monitoring until an action starts), the
user-selected files entitlement. Logs below are in `logs/`; each starts with the `HEAD` and working-tree
status it ran on.

## Underlying premises

- The session refuses `beginSelection` while it crops (`acceptsSelection` is `.selecting` or `.selected`,
  not `.cropping`), and the model drops `inactiveSession` silently. This premise was never questioned when
  re-selection was added; it is the cause of finding 1 (confirmed by its red run).
- The session crops the pixel rectangle with its corners rounded outwards (`floor` of the minimum, `ceil`
  of the maximum). The overlay's first two-pixel check used the unrounded size, so the two disagreed
  (finding 4).
- Pressing outside a selection was implemented per panel, but the controller has no coordination between
  panels: nothing withdrew a settled selection on another display (finding 2).
- `NSSavePanel.runModal` keeps other windows from receiving events, so the overlay takes no selection while
  the panel is open (REQ-009/AC-04): AppKit modal-session behaviour, not exercised by a test (the fixture
  saver returns at once) — installed-build check. "Later saves open where the panel was last used" relies on
  the panel remembering its directory when none is set — installed-build check (REQ-009/AC-01).
- New comments checked for causes: "Many apps paste only TIFF images" stated an unverified cause; checking it
  would overwrite the user's clipboard, so it now states only what the code does and why (a TIFF
  representation next to the PNG lets apps that read either type paste), and the spec's implementation
  decisions record the TIFF representation. "The session takes no new selection while it crops" and "a
  second click (a double click) is ignored" are confirmed by the red runs of findings 1 and 3. "While a
  replacement is pending, the current panels belong to the previous capture, which a rollback shows again"
  matches `rollback()` and `presentPending`. "The capture overlay sits at the screen saver level" matches
  the panel's `level`.

## Runnability

States enumerated for the overlay view: hover; pressing a new selection; drawing; settled without a frame;
settled under 2 × 2 px; confirmed; resizing (edge or corner); moving; closed (Esc, cancel, close,
display invalidation). For the model: selecting; cropping (one or several queued); toolbar shown; action
running (Extract/Translate, Copy, Save with the panel open); ended; back to the selection (save cancelled,
copy or save failed).

1. **Bug, fixed (same-layer escape).** Two releases before a crop finished (two quick adjustments, or a
   click and an immediate new selection) left the overlay on the second rectangle while the toolbar and the
   copied or saved image used an earlier one: the second selection hit the session while it cropped and was
   dropped. Fix: the model crops selections one after another (each waits for the previous) and keeps only
   the newest selection's result. Test `secondAdjustmentDuringCropIsWhatCopyUses` was red first
   (`logs/review-red-race.log`: copied `[600, 400]`, the selection before both adjustments, expected
   `[500, 350]`), green after (`logs/review-green.log`).
2. **Bug, fixed (same-layer escape).** With a confirmed selection on one display, pressing on another display
   started a new selection there but left the old one with its handles on the first display (REQ-007/AC-04:
   the old selection and toolbar are withdrawn). Fix: a press that starts a new selection on a current panel
   withdraws the settled selection on every current panel and hides the toolbar; presses on pending panels
   do not touch the current panels, which a rollback may show again. Not testable here (one display); gap
   noted in the overlay test file header, installed-build check with two displays. The single-display path
   still passes `pressOutsideStartsNewSelection`.
3. **Bug, fixed (same-layer escape).** A double click on Save opened two save panels (and a double click on
   Copy wrote twice and ended the capture twice): every click started its own action. Fix: toolbar actions
   run one at a time; clicks while one runs are ignored, and the lock clears when the action returns (save
   cancelled or failed, copy failed) or the capture ends. Test `doubleClickOnSaveOpensOneSavePanel` was red
   first (`logs/review-red.log`: 2 save requests), green after.
4. **Bug, fixed (self-harm, but a spec deviation).** A selection under 2 × 2 px — never cropped, so never
   given a toolbar — still showed handles, and a press on them resized it instead of starting a new selection
   (REQ-007/AC-01: handles appear with the toolbar). Test `tinySelectionHasNoHandles` was red first
   (`logs/review-red.log`: the press was taken as an adjustment). Then the overlay's own size check was
   unrounded while the session rounds outwards, so a 1.5 px selection straddling a pixel row was cropped
   (2 px) but got no handles. Fix: the session's rounding is public (`integralRect`) and the overlay judges
   the minimum with it. Test `selectionRoundedUpToTwoPixelsHasHandles` was red first
   (`logs/review-red-rounding.log`: the press started a whole-display selection), green after
   (`logs/review-green-rounding.log`).
5. **Prototype deviation, fixed.** Handles were filled white in both appearances; the confirmed prototype
   fills them with the surface colour, which is dark in dark mode. Fix: the theme's surface mapping
   (`controlBackgroundColor`). Test `handleFillFollowsAppearance` reads the rendered pixel in light and dark
   appearance: red first (`logs/review-red.log`), green after.

Paths judged without a change:

- A display change while the save panel is open ends the capture (REQ-001); if the user then confirms, the
  file is written where they chose and the outcome is ignored. Self-harm (that save only); the user chose to
  save, so writing is correct.
- An older crop that finishes while the next adjustment is being dragged moves the toolbar under the older
  rectangle until the next drag event moves it back. Self-harm, cosmetic, at most one drag event long.
- A crop error other than the known selection errors ends the capture, as before re-selection existed.
- Esc during an adjustment drag ends the capture; Esc in the save panel cancels the panel (REQ-009/AC-03).

## Security

Save writes only the PNG bytes to the URL the user picked in the system panel; the sandbox grants access to
that file through the user-selected read-write entitlement, which widens nothing else. The clipboard receives
only the image. Nothing is logged; the one new preference (`captureImageSavedBefore`) is a flag. No findings.

## Consistency

Rescanned after the runnability fixes.

- Class-level check of finding 1/3 (toolbar actions must use the newest crop and run once per click): all
  toolbar actions enumerated from `CaptureOperationToolbar`'s callbacks — `onStart` (Extract and
  Translate), `onCopy`, `onSave`; all three go through the same action runner; `onCancel` ends the capture
  and needs neither. 3 of 3 covered.
- Class-level check of finding 4 (a local two-pixel judgement that can disagree with the crop): every use of
  the minimum enumerated with `grep -rn -E '>= ?2\b|coversTwoPixels|selectionTooSmall' Sources VLMSnapper`
  — the session's `finishSelection`, the overlay's `coversTwoPixels` (handles and adjustment revert), and the
  snap-region resolver's window filter (REQ-006). The first two now use the same rounding. The resolver
  checks the unrounded size; outward rounding never makes a rectangle smaller, so every region it offers
  is one the crop accepts, and it can at most skip a sliver the crop would take (a click then selects what
  lies behind). Not a hit.
- REQ-001/AC-07 changed with this work (displays stay monitored until an action starts); the spec says so
  and `nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive` checks both halves.
- Smells: the adjustment state is a labelled tuple passed to one private helper (data clump) — exempt:
  private to the view, one producer and one consumer. The pixel-rounding rule was duplicated (finding 4) —
  removed. `renderedRGBA` and the existing `renderedAlpha` in the overlay tests repeat the same layer
  rendering — refactoring item R1.

## Refactoring list (for the user to decide)

| # | Content | Reason | Impact | Recommendation |
|---|---|---|---|---|
| R1 | Make the overlay tests' `renderedAlpha` read the alpha from `renderedRGBA` | Duplicated code (introduced here) | Self-harm: test helpers only | Done 2026-10-29 at the user's request |

## Installed-build feedback (2026-10-29, build `c568bf3`)

The user reported that clicking Save did nothing; everything else worked. R1 (above) was approved and done
(`renderedAlpha` now reads `renderedRGBA`).

6. **Bug, fixed (upper-layer escape: the save action and the capture hang behind an invisible panel).**
   Premise that failed (underlying premises layer): "setting `panel.level` above the screen saver level
   puts the save panel above the overlay". The installed app's log
   (`logs/save-installed-syslog-excerpt.log`) shows the panel was opened (`beginServicePanel` 12:30:47), a
   system beep at 12:30:51 (a press outside a modal window) and the panel ending at 12:30:54 — it was open
   but not visible. Measured in a sandboxed probe app with a full-screen non-activating overlay at the screen
   saver level (`logs/save-probe-sandboxed-app.log`, source `logs/save-probe-main.swift.txt`): `runModal`
   puts the save panel at layer 8 under the overlay at 1000; `NSApp.runModal(for:)` does the same; a panel
   shown with `begin` keeps level 1001 in front; an alert run modally is also at layer 8, while an alert
   shown as a sheet of the overlay is in front at 1000. Fix: the save panel is shown without a modal session
   (`begin`, awaited); alerts over the overlay are sheets of the key overlay panel. Because nothing is modal
   any more, the app keeps the guarantees itself: the overlays take no selection while the panel or an alert
   is shown (REQ-009/AC-04), toolbar actions stay locked while their action (including its alert) runs, and
   closing the panel or alert returns the keyboard to the overlay.
   - Class-level check (a window shown with a modal session over the overlay): every `runModal`,
     `beginSheetModal` and `prepareFailurePresentation` use enumerated with
     `grep -rn -E 'prepareFailurePresentation|runModal\(|beginSheetModal' Sources VLMSnapper` — the save panel
     (fixed), the Copy/Save failure alert (fixed), the capture-failure alert with Retry shown over a retained
     overlay (pre-existing since #21; same defect, fixed with the same sheet presentation), and three that are
     not over the overlay (diagnostics export panel and its alert, the workspace's close confirmation) — not
     hits.
   - The test process does not reproduce the level change: in a red reproduction run with `swift test`, an
     alert run modally stayed at layer 1001 in front of the overlay. Automated tests therefore cannot guard
     the layer; they guard the structure. Gap: which layer the panel and alerts land on is checked on the
     sandboxed installed build.
7. **Bug, fixed (same-layer escape), found by the new alert test.** After a sheet (or the save panel)
   closed, no window had the keyboard: Esc no longer ended the capture and the next press on the overlay
   only activated it. Test `alertIsSheetOfOverlay` was red first (`logs/save-red-alert-key.log`: overlay not
   key, no key window, the following click selected nothing). Fix: pausing selection remembers the overlay
   panel that had the keyboard and resuming makes it key again. `pausedSelectionIgnoresPresses` covers a
   panel taking the keyboard during the pause.
8. **REQ-009/AC-04 without a modal session.** Test `overlayTakesNoSelectionWhileSavePanelIsOpen` was red
   before the pause existed (`logs/save-red-hold.log`: a press during the open panel started a new selection
   and hid the toolbar), green after.

A test of the real save panel adapter in the test process was tried and removed: it showed the panel's
level and non-modality as intended, and a mutation without the level line failed it
(`logs/save-mutation-level.log`), but after the panel closed the test process exited with status 0 before
reporting a summary, which would skip later tests in the same run and look green. The capture test script
now also fails a `swift test` run that prints no passing summary.

## Findings and outcome

Findings 1–8 fixed; 1, 3, 4, 5, 7 and 8 with tests red first and green after, 2 without a test (two
displays), 6 with the sandboxed probe as its red and green evidence and structural tests. Capture-only test
run after all fixes: `logs/save-capture-after-fix.log` (52 Core and UI tests, 30 App composition tests, all
passing, each run with its summary line). Spec updated: FM-48 gains the crop order, one action per click,
another display, no handles under two pixels, and the keyboard returning after the panel or alert; the
implementation decisions record the crop order, the click lock, the TIFF representation, the non-modal save
panel, alerts as sheets of the overlay and why; the testing decisions record that the window layer is
checked on the installed build.
