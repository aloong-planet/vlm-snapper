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

- [x] Test design review (`/review-tests`), recorded in `review-tests.md`
- [x] Vertical slices with `/tdd`: resolver (`e91ba54`), overlay click/hover, adapter and app wiring
- [x] Targeted verification: `logs/targeted-snap.log` (strict build, build-tests, non-app 374, App 34, three
  native cases; all exit 0) at `e91ba54`
- [x] Code review: `review-code.md`; two bugs fixed red-first in `5c96041`
- [x] Full gate before review: `logs/gate-snap-prereview.log` at `5c96041`, every stage PASS (non-app 375, App 35)
- [ ] Post-implementation test review (independent sub-agent) — running
- [ ] Archive, features catalogue (step 8), full gate, install, PR

## Spec final check (2026-10-28, code at `5c96041`)

| AC | Spec text (short) | Implementation | Evidence |
|---|---|---|---|
| 01 | shown at the pointer without moving; follows; no new text | controller passes the pointer when the list arrives; tracking area per view; existing selection layers | U5/U6 rendered alpha |
| 02 | topmost ordinary window as a whole incl. title bar; occluded window keeps full frame | resolver returns the first matching window's bounds | C1, C2, U1, A1 |
| 03 | status item alone; rest of menu bar whole | layer-24/25 windows are ordinary entries in z-order | C3 |
| 04 | Dock strip whole, no single icons; auto-hide falls through | Dock windows match only inside the frame/visible-frame strip | C4 |
| 05 | desktop → whole display | fallback `display.frame` | C5, A1 desktop |
| 06 | own/transparent/off-screen/overlay windows skipped; clipped to the display; < 2 × 2 px skipped | guards in the resolver; clip and pixel check | C6, C7 |
| 07 | ≤ 3 pt is a click; more is a manual rectangle | view threshold; release far from press is a drag | U1, U2, existing drag tests |
| 08 | click before frames / before the list completes later | completed-before-frame; click held until the list | U3, A2 |
| 09 | list fixed at trigger; no list → no highlight, click selects nothing, drag works | one listing per request; `.unavailable` | U4, A3 |
| 10 | Esc, retrigger, display changes unchanged | existing paths; lists only reach the newest overlay | existing REQ-001/005 tests, U7, A5 |
| 11 | instant hover; list does not delay the overlay | local hit-test; listing detached off the main thread | A4; hover cost not measured separately |

No missing or partial item. Implementation-time decision written back to the spec: a window list only
reaches the newest overlay (Implementation Decisions). No unrecorded scope.
Installed-build checks (pending until the local install): the real window list in the signed sandboxed
app, real Dock/menu-bar geometry, hover from physical mouse movement.
