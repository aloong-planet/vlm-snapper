# Capture region snapping — test review

No ticket (`/to-tickets` no-ticket entry): spec implementation of v1-core::REQ-006 on
`feat/capture-region-snapping`.

## Design review (2026-10-28)

Implementation base: `f427514`. Scope: every test planned for REQ-006 AC-01–11 and FM-47.

### Test design table

Seams: S1 the public snap-region resolver in VLMSnapperCore (pure); S2 the public
`FrozenCaptureOverlayController` API with events sent to its real panels (VLMSnapperUITests, as U1/U2);
S3 the application composition fixture with an injected window-list adapter (VLMSnapperAppTests, as
the REQ-005 tests). Window-list fixtures follow the real `CGWindowListCopyWindowInfo` sample recorded on
2026-10-28 (1512 × 982 display): front-to-back order; an input-method window at layer 2147483629 with
alpha 0 first; status items as separate layer-25 windows of another process; the menu bar as a
layer-24 window of the window server; the Dock as one layer-20 window covering the whole display;
ordinary windows at layer 0 with overlapping, partly off-display bounds; visible frame leaving a 34 pt
top band and a 48 pt bottom band.

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| C1 | AC-02 | S1 | point inside the front Terminal window | region = Terminal bounds (literal from the sample) | real sample | none |
| C2 | AC-02 | S1 | point in the overlap of Terminal (front) and Chrome; point in Chrome only | Terminal bounds; Chrome bounds clipped to the display (literals) | real sample | none |
| C3 | AC-03 | S1 | point on a status item; point on the menu bar between items | the item's bounds; the menu bar bounds (literals) | real sample | none |
| C4 | AC-04 | S1 | point in the bottom band with the pinned visible frame; same point with a visible frame reaching the bottom (auto-hide) | strip (0, 934, 1512, 48); the window/desktop below (literal) | real sample + auto-hide variant | none |
| C5 | AC-05 | S1 | point with no window under it | whole display frame (literal) | real sample (corner not covered) | none |
| C6 | AC-06 | S1 | own-process windows (full-screen overlay at 1000, a layer-0 window in front), alpha-0 window, off-screen window, layer > 102 window, each above a known window | the known window below (literal) | real sample + own-PID entries | none |
| C7 | AC-06 | S1 | window spanning two displays; point on display 2; a 0.5 pt-wide window at scale 2 in front | part inside display 2 (hand-computed); the sub-2 px window skipped | two-display variant | none |
| U1 | AC-07, AC-02 | S2 | resolver attached, mouse down/up 2 pt apart inside a window region | `onSelection` once with `screenFrame` = that region in global AppKit points (hand-computed from Quartz) | controller fixture resolver | none |
| U2 | AC-07 | S2 | mouse down, drag 40 pt, up | `screenFrame` = the dragged rectangle, not the region | same | none |
| U3 | AC-08 | S2 | click before any resolver, then attach one | selection completes with the region at the click point after attach | same | none |
| U4 | AC-09 | S2 | resolver marked unavailable, click | no selection with a non-empty frame (empty selection only, as without snapping) | same | none |
| U5 | AC-01 | S2 | resolver attached with an injected pointer location inside a window | rendered overlay: clear (alpha 0) inside the region, dimmed outside (rendered layer pixels) | same | none |
| U6 | AC-01 | S2 | mouse-moved event to another window's region | rendered clear area moves to the new region | same | none |
| A1 | AC-02, AC-05, FM-47 | S3 | shortcut, frames available, window list with one window; click inside it; second run clicking the desktop | toolbar left edge = window minX and top under window bottom; desktop → toolbar for the whole display (placement rule of the toolbar spec) | fixture list in the sample's shape | app composition (existing per-test fixture) |
| A2 | AC-08 | S3 | frames held, click on the window, then release | toolbar appears after release at the window's edge | same | same |
| A3 | AC-09 | S3 | window list unavailable; click; then drag | no toolbar after the click, overlay still shown; drag completes | same | same |
| A4 | AC-11 | S3 | window list held (never returns) | overlay still appears at once (existing pending-overlay observable) | same | same |

AC-10 is covered by the existing REQ-001/REQ-005 suite (Esc, retrigger, display changes), which runs
unchanged with the window-list adapter injected; no new row.

### Dimension 1: Coverage

Every AC of REQ-006 maps to a row except AC-10 (existing suite) and the parts that need the window
server: the real window list in a signed sandboxed app, real Dock/menu-bar geometry and hover from
physical mouse movement — recorded as gaps in the test-file headers, to be verified on the installed
build. FM-47 items map to C1–C7, U1–U4, A1–A3. Fixtures are not spec-shaped only: the resolver
fixture copies the structure of the recorded real window list (the full-screen Dock window and the
alpha-0 high-layer window are features of the sample, not of the spec).

### Dimension 2: Case design

All rows act through public entry points (resolver API, controller API plus panel events,
application shortcut and overlay events) and read results through public observables (returned
rectangle, selection callback, rendered layer, toolbar window). U5's pointer location is injected
through the controller's initializer — an injection seam, not internal state.

### Dimension 3: False greens (design-time checks)

- Always-true assertions: expected rectangles are literals from the sample, distinct from the
  neighbouring candidates (whole display, other windows), so a wrong rule changes the result.
- Tautology: expectations are not recomputed with the resolver's algorithm; Quartz → AppKit
  conversions in U1 are hand-computed for the fixture display.
- Stale path: the selection callback and toolbar are the paths the app uses today (REQ-005 tests).

### Dimension 4: Resource reuse

New rows use no expensive resource beyond the application composition, built per test by the
existing `withApplication` fixture; it is mutable application state with no copy mechanism, as for
every REQ-005 test (App suite: 29 tests in 23.9 s, under 1 s each on average). No shared resource is
cleared by these rows.

### Findings

None.
