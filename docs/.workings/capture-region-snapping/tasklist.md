# Capture region snapping — task list

Scope: v1-core::REQ-006 (AC-01–11), FM-47, ADR-0014; prototype confirmed by the user on 2026-10-28.
No ticket; implemented directly from the spec on `feat/capture-region-snapping` (base `8c00b2d`).

## Design (from the code as of `f427514`)

- Core, pure: a snap-region resolver over a front-to-back window list in global top-left (Quartz)
  coordinates — the same space as `CaptureDisplayGeometry.logical*`. Inputs: entries (owner PID, layer,
  alpha, on-screen, bounds), the current process PID, the Dock PID, and per display its frame, visible
  frame and point-to-pixel scale. Rules: skip own PID, alpha ≤ 0, off-screen, layer > 102; the Dock's
  windows never match themselves — when one is reached in z-order and the point lies in the strip
  between the display frame and its visible frame on the Dock's side, the strip is the region;
  otherwise the window's bounds clipped to the display, skipping clips under 2 × 2 pixels; nothing
  matched → the whole display.
- Adapter: window list taken once per capture, off the main thread, with on-screen-only and
  desktop-elements-excluded options; the Dock PID looked up by bundle identifier. Injected through
  `ApplicationModelDependencies` like the frozen-display capturer; tests inject a fixture.
- App model: start the window list when the pending overlay is presented (alongside the freeze), hand
  it to the overlay controller when it arrives if the request still owns the overlay.
- Overlay: each panel's view gets a resolver in local AppKit coordinates; a tracking area delivers
  mouse movement on every display; the snap region is drawn with the existing selection layers; a
  click (≤ 3 pt movement) completes the selection with the snap rectangle's corners; a press moved
  further is the existing drag. Click before frames → existing completed-before-frame path; click
  before the window list → resolved when it arrives; no window list → click ignored.

## Success criteria (one per acceptance condition)

| AC | Observable |
|---|---|
| 01 | Overlay shows the snap region at the pointer without movement; it follows movement; no new UI elements |
| 02 | Click on a window selects its full frame (crop pixel size = window size × scale, toolbar at its bottom-left) |
| 03 | Status item → that item; elsewhere on the menu bar → the menu bar |
| 04 | Dock strip → the strip; auto-hidden Dock (no strip) → what is below |
| 05 | Desktop → the whole display |
| 06 | Own windows, transparent, off-screen, layer > 102 skipped; clipped to the display; sub-2 px clips skipped |
| 07 | ≤ 3 pt press movement = click; more = manual rectangle |
| 08 | Click before frames completes after frames; click before the window list resolves when it arrives |
| 09 | Snapshot fixed at trigger; no snapshot → no highlight, click ignored, drag works |
| 10 | Esc, retrigger, display changes unchanged |
| 11 | Hit-testing is local per event; window list does not delay the overlay |

## Steps

- [ ] Test design review (`/review-tests`), recorded in `review-tests.md`
- [ ] Vertical slices with `/tdd`: resolver → adapter/dependency → overlay click → hover/tracking → app wiring
- [ ] Targeted verification
- [ ] Code review (`/review-code`), `review-code.md`
- [ ] Full gate before review (pre-review run)
- [ ] Post-implementation test review (independent sub-agent)
- [ ] Spec final check, archive, features catalogue (step 8), full gate, install, PR
