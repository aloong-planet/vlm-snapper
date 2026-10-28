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
build. FM-47 items map to C1–C7, U1–U4, A1–A3. Corrected 2026-10-28 (post-implementation findings 2 and 6):
that mapping did not drive pointer jitter, the release-only drag or a settled click (now U8–U11), nor
the window list's timing, single read and own-window exclusion (now A6). Fixtures are not spec-shaped only: the resolver
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

### Increment: rows added for the code-review fixes (2026-10-28)

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| U7 | AC-09, AC-10 (CONTEXT invariant) | S2 | capture 1 committed with list A; replacement pending gets list B; rollback; click at a point only B covers | selection = the whole display (A has no window there) | two single-window lists | none |
| A5 | AC-09, AC-10 | S3 | selection completed, replacement pending with frames held; lists returned newest first; click after both returned | toolbar at the visible-frame left edge (replacement's list: desktop), not +200 | per-call lists | app composition |

Order: both tests were written while fixing the review findings and reviewed here afterwards — the
increment rule asks for review before writing; recorded as it happened. Review of the rows:
Dimension 1 — they drive the two state paths found in review (rollback, late list of a replaced
capture). Dimension 2 — public seams only; A5 clicks after the fixture reports both list calls
returned plus 100 ms, so the earlier capture's list is handed over before the click (otherwise the
first list would resolve the click and hide the bug). Dimension 3 — both were red on the unfixed code for
the asserted reason (`logs/snap-rollback-red.log`, `logs/snap-late-red.log`). Dimension 4 — no new
resource. Findings: none.

## Post-implementation check (2026-10-28)

No ticket, so this record is the change's no-ticket path. First round: no fix range was handed over, so
every check covers all tests this change adds. Implementation version: code at `5c96041`, range
`8c00b2d..5c96041`; `135ed01` and `14336d6` after it change only documentation and logs
(`git show --stat`). Date, version and range apply to every dimension below. The design review section
above is left as written; corrections it needs are listed under Findings.

Objects (`git diff --stat 8c00b2d..5c96041 -- Tests/`: insertions only, no existing test line changed):

- `Tests/VLMSnapperCoreTests/CaptureSnapRegionResolverTests.swift`: C1–C7 in six test functions.
- `Tests/VLMSnapperUITests/FrozenCaptureOverlayControllerTests.swift`: U1–U7 in six test functions
  (U5 and U6 share `hoverShowsAndFollowsSnapRegion`) and the new helpers below line 243.
- `Tests/VLMSnapperAppTests/ProviderApplicationTests.swift`: A1–A5 in six test functions (A1 is
  `clickOnWindowSelectsWholeWindow` and `clickOnDesktopSelectsWholeDisplay`), `withSnapFixture`,
  `frozenMainOverlay` and `FixtureWindowListing`, which `ApplicationFixture` now injects into every App
  test (default: no list).

Capability declaration: opening `capabilities.toml` at the repository root with Python's `tomllib`
raises `FileNotFoundError` — 项目无能力声明文件; 未确认 mutation-testing; 未确认 working-language
(finding 1). This round neither runs the mutation check nor treats it as disabled; every "goes red
when" answer below is derived from the code under test and the expected-value source. Fixed names
follow this record's English precedent.

### Run evidence

Handed-over log, not rerun: `logs/gate-snap-prereview.log`, byte-identical (`cmp`) to the scratchpad
log it was copied from.

| Log requirement (full verification gate) | Log content | Verdict |
|---|---|---|
| Tested version | `git rev-parse HEAD` = `5c96041…`, the end of the handed range; porcelain lists only `:-` with hash `208ccf64…` (same hash today) | Matches |
| Every command | `bash Scripts/test-local-regression.sh --offline`; the `PATH` prefix is logged as `<scratch rg shim>`. The scratchpad `gate.sh` and `bin/rg` show the prefix only puts an `exec -a rg` of Claude Code's binary first on `PATH`, used by the script's two native-log checks (script lines 53, 55), whose input logs are in this log verbatim | Present; the elision changes no stage result |
| Exit code not taken through a pipe | `== exit: 0`, from `code=$?` right after a redirect (`gate.sh`) | Present. The two version commands log no exit code; their outputs (a commit hash, a porcelain line) prove themselves |
| Full output | Top-level output plus all nine stage logs | Present |
| Skipped commands | None; this change adds test files, so none may be skipped | Correct |

Reviewed tests in the log: the six resolver tests pass at lines 1057–1073; U1–U7 at 1319, 1337, 1346,
1354, 1360, 1367; A1–A5 at 137–147. Totals: non-app 375 tests (line 21), App 35 (line 24: the 29
earlier App tests plus the six new ones). Conclusion: the log meets the gate's log requirements and is
this round's run evidence.

### Test design table check

| Row | Written test | Verdict |
|---|---|---|
| C1, C2 | `snapsTopmostWindow` (resolver tests :65) | Matches |
| C3 | `snapsStatusItemAndMenuBar` (:77) | Matches |
| C4 | `snapsDockStrip` (:84) | Pinned case matches; the auto-hide case has only the desktop below, not "the window/desktop below" (finding 3) |
| C5 | `snapsDesktopToDisplay` (:104) | Matches |
| C6 | `skipsWindowsOutsideTheFrozenFrame` (:109) | Matches |
| C7 | `clipsToDisplayAndSkipsTinyWindows` (:122) | Differs: the row plans a 0.5 pt-wide window at scale 2; the test uses a 1.5 pt-wide window at scale 1 (:126, :129) (finding 4) |
| U1 | `clickSelectsSnapRegion` (UI tests :59) | Matches |
| U2 | `dragIgnoresSnapRegion` (:78) | Matches (one drag event 50 pt away) |
| U3 | `clickBeforeSnapRegionsCompletesLater` (:99) | Matches; also holds the frame and checks nothing completes before it |
| U4 | `clickWithoutSnapRegionsSelectsNothing` (:120) | Matches |
| U5, U6 | `hoverShowsAndFollowsSnapRegion` (:139) | Matches |
| U7 | `rollbackKeepsPreviousSnapRegions` (:162) | Matches |
| A1 | `clickOnWindowSelectsWholeWindow` (App tests :1261), `clickOnDesktopSelectsWholeDisplay` (:1275) | Matches |
| A2 | `clickWhileFreezingSelectsWindowOnceFramesArrive` (:1288) | Matches |
| A3 | `clickWithoutWindowListSelectsNothingButDragStillWorks` (:1306) | Differs: neither "no toolbar after the click" nor "overlay still shown" is asserted, only the position of the drag's toolbar (finding 8) |
| A4 | `heldWindowListDoesNotDelayOverlay` (:1355) | Matches |
| A5 | `lateWindowListOfReplacedCaptureIsIgnored` (:1321) | Matches |

Resource columns match: no resource beyond the per-test application composition.

Test-file gap notes: the resolver header (:5–11) names the real list in the signed sandboxed app and
real Dock/menu-bar geometry; the UI comment above U1 (:54–57) names physical hover and real lists; the
App header (:11–49) carries the generic synthetic-input and window-server hit-testing gaps. Recorded
nowhere: multi-display snapping (finding 7), AC-11 hover latency (finding 6), the real auto-hide visible
frame (finding 3).

### Dimension 1: Coverage

| Spec item | Driven by | Verdict |
|---|---|---|
| AC-01 region at the pointer at once, follows movement | U5/U6 rendered alpha | Covered on the primary display; other displays: finding 7 |
| AC-02 topmost window whole, occluded window keeps its frame | C1, C2, U1, A1 | Region covered; the crop of the snapped rectangle is not asserted: finding 5 |
| AC-03 status item / rest of menu bar | C3 | Covered |
| AC-04 Dock strip; auto-hide falls through | C4 | Bottom Dock only; side branches never run; auto-hide fall-through indistinguishable: finding 3 |
| AC-05 desktop → display | C5, A1 desktop | Covered |
| AC-06 own/transparent/off-screen/overlay skipped; clipped; < 2 × 2 px skipped | C6, C7 | Resolver clauses covered; pixel rule only partly (finding 4); own-PID wiring in the app (finding 6) |
| AC-07 ≤ 3 pt click, > 3 pt manual rectangle | U1 (2.24 pt, no drag event), U2 (50 pt) | Boundary, jitter through drag events, release-only move and the settled state not driven: finding 2 |
| AC-08 click before frame / before list | U3, A2 | Covered |
| AC-09 list fixed at trigger; no list → no region, click selects nothing, drag works | U4, A3 (no list); U7, A5 (newest-overlay rule) | No-list half covered; "taken at trigger, never re-read" not driven: finding 6 |
| AC-10 Esc, retrigger, display changes | Existing REQ-001/REQ-005 App tests, which now run with the fixture's default "no list" (`.unavailable`); U7, A5 with lists | Covered: a region is drawn inside its panel's view, every path that retires a panel sets `contentView = nil` (`retire`, controller :171–176), and the existing tests observe that withdrawal |
| AC-11 instant hover regardless of window count; list does not delay the overlay | A4 | Second half covered; first half neither driven nor recorded as a gap: finding 6 |
| FM-47 jitter ≤ 3 pt is still a click | None (U1 sends no drag event) | Finding 2 |
| FM-47 window changes during selection | None | Finding 6 |

Touched regression points: the drag path was rewritten (`mouseDown`/`mouseDragged`/`mouseUp`,
`complete`, `finishSelection`). The earlier drag tests (`selectionDraggedWhileFreezingCompletesWithFrozenFrames`
:1040, `selectionStartedBeforeFramesFinishesAfterThem` :1229, `completeSelection`) still pass in the
log, in the `.unavailable` state; U2 covers a drag with a list attached. The fixture default keeps the
earlier tests' meaning (a click without a list is an empty selection, as before snapping).

Fixture shape: the resolver fixture was compared with a fresh read-only `CGWindowListCopyWindowInfo`
probe (2026-10-28, scratchpad `winlist/`; 48 windows; display 1512 × 982, visible frame (0, 48, 1512,
900) in AppKit = (0, 34, 1512, 900) top-left): the alpha-0 input-method window at layer 2147483629
first, sixteen layer-25 Control Center status items (one reaching x 1514, past the display), the
layer-24 Window Server menu bar (0, 0, 1512, 33), the layer-20 Dock window covering the display, then
overlapping layer-0 windows. The fixture keeps every structural feature; the only unmodelled one, a
1 pt row between the menu bar (to y 33) and the visible frame (from y 34), resolves to the whole display
under the same rules. The auto-hide variant is assumed rather than sampled (finding 3).

Conclusion: findings 2–7.

### Dimension 2: Case design

All 18 test functions act through public entry points (resolver API; controller API with events sent
to its real panels; shortcut and overlay events through the production model) and read public
observables (returned rectangle, `Selection.screenFrame`, rendered layer alpha, toolbar window frame).
U5's pointer is injected through an initializer parameter that production fills with
`NSEvent.mouseLocation`. `FixtureWindowListing` replaces only the external adapter at
`ApplicationModelDependencies.windowListing`, the seam production fills with
`CoreGraphicsCaptureWindowListing`. No test reads internal state or builds a state the public paths
cannot reach: U7's sequence is the failed-replacement rollback, A5's newest-first release is a legal
completion order of two asynchronous calls. Isolation: the UI suite is `.serialized` and closes its
controller in `defer`; each App test builds its own fixture; resolver tests are pure.

Conclusion: no finding.

### Dimension 3: False greens

Mutation check: not run (finding 1).

| Test | Goes red when | Stays green although wrong |
|---|---|---|
| `snapsTopmostWindow` (C1, C2) | front-to-back order not honoured (overlap returns Chrome); the Dock's display-sized window hit as a window ((100, 300) returns the display); no clipping (Chrome 1200 wide); layer-0 windows skipped | pixel-rule changes (finding 4) |
| `snapsStatusItemAndMenuBar` (C3) | status items skipped or merged into the menu bar; layer cap below 25 | — |
| `snapsDockStrip` (C4) | wrong bottom strip; the Dock snapped whole while pinned | side Docks; "no strip → display" instead of falling through (finding 3) |
| `snapsDesktopToDisplay` (C5) | fallback other than the display frame | treating the Dock as a window (its bounds equal the display here; C1 catches it) |
| `skipsWindowsOutsideTheFrozenFrame` (C6) | any one of the PID, alpha, on-screen or layer clauses removed (that window's (60, 200, 400, 300) is returned instead of Terminal) | layer exactly 102 vs 103 (no spec number; no finding) |
| `clipsToDisplayAndSkipsTinyWindows` (C7) | no clipping to the pointer's display; sub-2-px rule removed | dropped scale, `>=`→`>`, dropped height clause, any threshold in (1.5, 66] px (finding 4) |
| `clickSelectsSnapRegion` (U1) | a ≤ 3 pt click not selecting the region (empty, wrong flip, threshold under 2.24 pt); a second callback | threshold anywhere in (2.24, 50) pt (finding 2); wrong `start`/`end` (finding 5) |
| `dragIgnoresSnapRegion` (U2) | a 50 pt drag treated as a click (gives the window (100, h−300, 300, 200)); wrong drag rectangle | — |
| `clickBeforeSnapRegionsCompletesLater` (U3) | a click before the list dropped, completed before the frame, or resolved at the wrong point | — |
| `clickWithoutSnapRegionsSelectsNothing` (U4) | a click without a list yields a non-empty frame | zero callbacks pass too, which AC-09 allows |
| `hoverShowsAndFollowsSnapRegion` (U5, U6) | no initial region from the injected pointer; mouse-moved not switching; nothing rendered (paired alpha checks) | the tracking area for non-key overlays (recorded physical-hover gap) |
| `rollbackKeepsPreviousSnapRegions` (U7) | the replacement's list reaching the restored overlay (red shown: `logs/snap-rollback-red.log`) | — |
| `clickOnWindowSelectsWholeWindow` (A1) | the click not selecting the window through the model (toolbar left edge ≠ window, toolbar above the window bottom, no toolbar → deadline) | crop size or offset (finding 5); wrong excluded PID (finding 6) |
| `clickOnDesktopSelectsWholeDisplay` (A1) | a desktop click selecting nothing, or a region starting right of the visible-frame edge | exact display rectangle (covered by C5, U7) |
| `clickWhileFreezingSelectsWindowOnceFramesArrive` (A2) | a click during the freeze lost or not snapped | listing moved after the freeze (finding 6) |
| `clickWithoutWindowListSelectsNothingButDragStillWorks` (A3) | the drag after the click failing or misplaced | a click that wrongly selects, unless its task finishes first (finding 8) |
| `lateWindowListOfReplacedCaptureIsIgnored` (A5) | an older capture's late list reaching the replacement overlay (red shown: `logs/snap-late-red.log`) | — |
| `heldWindowListDoesNotDelayOverlay` (A4) | the overlay or the frozen frame waiting on the list (deadline) | — |

Forms: always-true assertions — expected literals differ from the neighbouring candidates, except the
auto-hide expectation in C4 (finding 3); tautology — none, expectations are sample literals or
hand-flipped values; stale path — none, `onSelection`/`screenFrame` and the toolbar are the live paths;
conditional skip — none, `#require` throws; assertions that may not run — U4's `allSatisfy` passes on
an empty list by design (AC-09 allows no selection), App waits throw on deadline.

UI and rendered assertions (`review-code/false-greens.md`): effects, not existence, are asserted
(rendered alpha in pairs, toolbar geometry, frozen-frame opacity). Synthetic events: `sendEvent` skips
window-server hit testing and the tracking area; recorded as gaps (App header :44–46, UI comment
:54–57), except for multi-display (finding 7). Reading too early: A2's `captureToolbar() == nil` while
frames are held is a precondition the fixture guarantees; A5 polls the upstream `returned == 2` and
then sleeps 100 ms before clicking — the ignored list has no observable of its own, the sleep frees the
main actor for the already-resumed continuations, and the red log shows the bug is caught; no finding.
Geometry: A1's one-sided `maxY <=` bound is backed by U1's exact rectangle.

Conclusion: no false green in what the tests assert; coincident or missing expectations are findings
3, 4 and 8.

### Dimension 4: Resource reuse

| Resource | Built | Measured (handed-over log unless noted) | Expensive (≥ 1 s)? |
|---|---|---|---|
| Resolver window list (in memory) | per call to `Self.resolver()` | whole suite 0.135 s for six tests | No |
| Overlay panels and the 2 × 2 frame (`makeDisplay`) | per UI test | U2–U7 0.125–0.209 s each; U1 4.753 s in the gate run but 0.030 s in the isolated run (`logs/snap-rollback-red.log`), so main-actor contention from parallel suites, not setup | No |
| Application composition and full-screen synthetic frame (`withFixture`, `syntheticDisplay`) | per App test, as for every REQ-005 test | 0.176–0.536 s per test including the whole body | No |

No expensive resource, so there is no load count to compare; no test clears a shared resource, so the
collection-order rule does not apply. The new tests reuse the existing helpers (`withFixture`,
`syntheticDisplay`, `makeCaptureReady`, `eventually`, `sendMouse`, `drag`, `completeSelection`,
`makeDisplay`, `visibleOverlays`).

Conclusion: no finding.

### Document sync

Range checked: `docs/.workings/capture-region-snapping/` (enumerated with `find`, hidden entries
included: 11 entries, no dotfiles; `git check-ignore` matched none), `docs/.workings/v1-core/checklist.md`
(REQ-006 rows), `docs/specs/v1-core.md` (REQ-006, FM-47, Implementation Decisions, Testing Decisions),
`docs/features/v1-core.md`, `CONTEXT.md`, `docs/adr/0014-snap-regions-from-window-list.md` and the
three test files' gap notes. Content search: `/usr/bin/grep -a` over those nine documents (279,431
bytes) for thresholds, crop, Dock and auto-hide, pixel rule, PID, AC-09/AC-11 and multi-display terms;
all 81 hits read. Excluded: other `docs/.workings/<slug>/` directories (other changes;
`capture-instant-overlay/review-tests.md` read only as the run-evidence precedent), `docs/prototypes/`
(visual, no test claims), `docs/ops/` and `docs/postmortems/` (no statement about this change). The
feature catalogue, `CONTEXT.md` and ADR-0014 state behaviour, not coverage, and are unaffected (ADR-0014
:24 would change only if finding 3's inset is confirmed).

Statements these findings make untrue or incomplete (each finding names its own): `review-code.md`
:19–21; `tasklist.md` :32, :64, :66, :68, :70, :72–73; `final-regression.md` :14, :16, :51–52; this
record :27, :30, :39, :47–52; `docs/.workings/v1-core/checklist.md` :21. None of them may be closed
until the finding behind it is handled.

### Findings

1. **Capability declaration missing; `mutation-testing` and `working-language` unconfirmed.** Required
   by the global capability rule: 项目无能力声明文件; 未确认 mutation-testing; 未确认
   working-language. Evidence: `tomllib` → `FileNotFoundError`; the project `AGENTS.md` carries an
   inline 项目能力 section (i18n), which the rule keeps out of rule files. Impact: this round can
   neither run nor skip the mutation check (Dimension 3), and fixed names follow precedent. Handling:
   already decided by the user on 2026-10-28 — a separate PR after this feature (`final-regression.md`
   :47); recommended answers there are the registry defaults, `[mutation-testing] enabled = false` and
   `working-language = "en"`. Destination: that PR; nothing on this branch.

2. **AC-07 / FM-47: the click-or-drag decision is not driven at 3 pt, through drag events, on release
   only, or once settled.** Missed regression; untrue records. Evidence: the smallest click movements
   are 1.41 pt (A1) and 2.24 pt (U1), sent as down/up with no drag event; the smallest drag-event move
   is 50 pt (U2 :92); App drags move 141–224 pt (`drag()` :1821, REQ-005 test :1242). Hence (a) the
   `mouseDragged` guard (controller :404) can be removed with every test green, although physical
   jitter arrives as drag events — the real path of FM-47's "抖动不超过 3 pt 仍是单击"; (b) any
   threshold in (2.24, 50) pt and `>` vs `>=` pass; (c) the release-only rule (:415–418) can be
   removed: no test sends a far down/up pair without a drag event (`grep -rln
   "leftMouseUp\|leftMouseDown"` over `Tests`, `Sources`, `Scripts` and `VLMSnapper`, then every overlay
   event in the hits read: U2, the REQ-005 test at :1242–1249, `drag()` and the new
   clicks); (d) the `!selectionSettled` guards (:376, :382) that keep a clicked selection drawn while
   the pointer moves on are never driven. Impact: jitter turning clicks into too-small drags (the click
   then does nothing) or a moved threshold would ship green. Untrue records: `review-code.md` :19–21
   ("the existing tests send down/up without drag events" — none do); `tasklist.md` :64 ("existing
   drag tests" for the release-only rule); design review :50 maps FM-47's jitter to U1–U4.
   Recommended: fix now in the UI suite — a drag event 3 pt away then release (region selected), a
   move just over 3 pt such as (2.5, 2.5) (dragged rectangle), down/up 50 pt apart with no drag event
   (dragged rectangle), a mouse-moved after a click (rendered selection unchanged) — then correct the
   three records. Destination: this branch.

3. **AC-04: side Docks never run, and the auto-hide case cannot tell "falls through" from "whole
   display".** Missed regression. Evidence: `dockStrip`'s left and right branches (resolver :92–97)
   execute in no test — only the bottom-pinned and auto-hide variants put a point on the Dock window
   (C7's points lie outside it; the UI and App tests pass `dockProcessID: nil`). The auto-hide
   expectation (resolver tests :95) is the display frame, which is also the Dock window's own bounds
   (:51) and what "no strip → return the display" would give; no window lies under (700, 960), though
   row C4 promises "the window/desktop below". The auto-hide visible frame reaching the bottom exactly
   is assumed, not sampled; a few-point inset at the Dock edge with an auto-hidden Dock is commonly
   reported for `visibleFrame`, and if real the resolver would snap that band as a strip, against
   AC-04 (unverified: sampling it means changing the user's Dock setting). Impact: side-Dock and
   auto-hide regressions ship green. Recommended: resolver cases for a left and a right Dock (visible
   frame inset on that side, literal strip) and an auto-hide case with a window under the bottom band
   (expected: that window); record the real auto-hide visible frame as an installed-build check (spec
   Testing Decisions :392 list, resolver header, `tasklist.md` :72–73) or sample it with the user's
   consent; correct row C4 (:27). Destination: this branch.

4. **AC-06: the 2 × 2 physical-pixel rule is not driven through the scale, at its boundary, or in
   height.** Missed regression; untrue record. Evidence: the only small window is 1.5 × 300 pt at
   scale 1 (resolver tests :126, :129). With it, dropping `* display.pointPixelScale` (resolver
   :79–80), `>=` → `>`, dropping the height clause, or any threshold up to 66 px (the smallest kept
   region, the 38 × 33 pt status item at scale 2) all stay green; the controller's
   `pointPixelScale: backingScaleFactor` (controller :239) never meets a small window. Row C7 (:30)
   plans a 0.5 pt window at scale 2, which is not what the test does and would not tell points from
   pixels either. Impact: on Retina displays a 1 pt-wide window (2 px) could be skipped, or
   sub-2-pixel windows kept, with every test green. Recommended: at scale 2, a 1 pt-wide window (2 px,
   kept) and a 0.75 pt-wide one (1.5 px, skipped), plus a window narrow only in height; update row C7.
   Destination: this branch.

5. **AC-02 / AC-07: the crop of a snapped selection is never asserted.** Missed regression; untrue
   records. Evidence: spec Testing Decisions (:392) has the App tests judge the selected region "以单击
   后的裁切像素尺寸与操作栏位置"; they read only the toolbar frame, placed from `selection.screenFrame`
   (model :1328–1332), and U1, U3, U7 compare only `screenFrame`. The crop comes from
   `selection.start`/`end` (model :1316–1318), produced by the rewritten `finishSelection` (controller
   :455–467); no test reads them. A crop under 2 × 2 px hides the toolbar (`selectionTooSmall`) and
   turns A1/A2 red; a wrong-sized or offset crop stays green. Untrue records: `tasklist.md` :32
   (success criterion "crop pixel size = window size × scale" has no test behind it);
   `final-regression.md` :16 (Testing Decisions paragraph rated "True"). Recommended: assert the crop
   as the spec says — e.g. A1's crop pixel size equals 300 × 200 pt × the display scale, or U1's
   `start`/`end` pixel points against a display geometry with real pixel sizes. Destination: this
   branch.

6. **The app's window-list wiring is not driven: when the list is taken, how often, and which process
   it excludes.** Missed regression; untrue records. Evidence: (a) the listing call in `beginCapture`
   (model :1139) can move after `startCapture` or be repeated at commit with every test green — the
   fixture returns the same list on each call, and no test counts calls or checks the call happens
   while frames are held (A2 and A4 pass either way); this is AC-09's "截图触发时与冻结同时取得…选区期间
   窗口…变化不改变吸附结果", FM-47's "选区期间窗口变化" and the "不轮询系统" part of AC-11 and
   Implementation Decisions (spec :362). (b) `excludedProcessID: ProcessInfo.processInfo.processIdentifier`
   (model :1297) can be any value: every App-fixture window is owned by PID 4242, and the UI and
   resolver tests build their own resolvers. (c) AC-11's "no perceptible delay regardless of window
   count" is neither tested nor recorded as a gap (`tasklist.md` :68 says "hover cost not measured
   separately"). Impact: a list re-read after the trigger (snap regions no longer matching the frozen
   frame) or VLMSnapper's own windows becoming regions would ship green. Untrue records: design review
   :47 ("Every AC of REQ-006 maps to a row except AC-10…"); `tasklist.md` :66 cites U4/A3 for "one
   listing per request". Recommended: an App test that holds frames, fires, sees `fixture.windows`
   called once before release, uses per-call lists so a second read would change the click result, and
   still counts one call after hover, click and commit; a fixture entry owned by the test process over
   the click point that the click must not select; AC-11's latency recorded as an installed-build check
   in the test header. Destination: this branch.

7. **Multi-display overlay paths are neither driven nor recorded as a gap.** Missed regression.
   Evidence: every UI and App test uses the primary display, whose panel origin is (0, 0), so the offset
   terms in `snapRegion(at:resolver:)` (controller :241–247) and `localPoint(fromGlobal:)` (:251–254)
   run with zero offsets, and the `nil` pointer on another display (:130) and `mouseExited` clearing a
   region when the pointer leaves a display (:381–385) never run. This machine has one display (probe).
   No test header, `tasklist.md` installed-build list (:72–73), `final-regression.md` :14, spec Testing
   Decisions (:392) or the v1-core checklist row (:21) names multi-display snapping. Impact: an offset or
   flip error on a secondary display (wrong regions there) ships green and unrecorded. Recommended:
   record the gap now — UI comment :54–57, the tasklist installed-build list, the spec Testing Decisions
   list and the checklist row — with the condition "two displays, installed build"; optionally move the
   conversion into a pure function and unit-test it with a non-primary panel frame. Destination: this
   branch (records); the two-display check before delivery.

8. **A3 does not assert what its design row promises.** Untrue record. Evidence: row A3 (:39) promises
   "no toolbar after the click, overlay still shown"; the test (:1306–1318) asserts only that the
   toolbar after the following drag sits at the drag's left edge. Whether it would catch a click that
   wrongly selects depends on which of the two queued `finishSelection` tasks completes first; "click
   selects nothing" is covered deterministically by U4. Recommended: change row A3 to "a drag after the
   click still completes and the toolbar is the drag's", citing U4 for the click; if the row's
   assertions are wanted instead, add them only after showing they go red with a list present
   (false-greens: make X happen once first). Destination: this record.


## Handling of post-implementation findings 1–8 (2026-10-28)

Read in full from the Findings subsection above before handling; the hand-back titles match the
record (8 findings, numbers 1–8).

- Finding 1: no action on this branch (user decision 2026-10-28: `capabilities.toml` in a separate PR).
- Findings 2–6: tests added below after this increment review; records corrected as listed in each row.
- Finding 7: multi-display snapping cannot run here (one display); recorded as a gap in the UI test
  header, `tasklist.md`, spec Testing Decisions and the v1-core checklist row, and listed as deferred
  acceptance in the delivery note.
- Finding 8: row A3 rewritten below; U4 covers "a click selects nothing" deterministically.

### Increment: rows for findings 2–6 and 8

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| A3 (rewritten) | AC-09 | S3 | no window list; click; then drag | the toolbar that appears is the drag's (left edge at the drag start); the click selecting nothing is U4's | as before | app composition |
| C4 (rewritten) | AC-04 | S1 | bottom-pinned strip; auto-hide (visible frame reaching the bottom) with a window behind the Dock under the point; left Dock (visible frame inset 60 pt left); right Dock (inset 60 pt right) | strip (0, 934, 1512, 48); the window below (literal); (0, 34, 60, 948); (1452, 34, 60, 948) — hand-computed | real sample + side/auto-hide variants (auto-hide inset unverified: installed-build check) | none |
| C7 (rewritten) | AC-06 | S1 | display at scale 2: 1 pt-wide window (2 px), 0.75 pt-wide window (1.5 px), 0.75 pt-high window; plus the second-display clip | 1 pt window kept; the two others skipped for the display (literals) | sample display | none |
| U8 | AC-07, FM-47 | S2 | down; drag event exactly 3 pt away; up there | selection = the snap region (literal) | two-window resolver | none |
| U9 | AC-07 | S2 | down; drag event (2.5, 2.5) away (3.54 pt); up | selection = the 2.5 × 2.5 dragged rectangle | same | none |
| U10 | AC-07 | S2 | down/up 50 pt apart with no drag event | selection = the dragged rectangle | same | none |
| U11 | AC-07 | S2 | click on region A while frames are pending, then mouse moved over region B | rendered: A stays clear, B dimmed (selection does not follow) | same | none |
| U12 | AC-02, AC-07 | S2 | display geometry with real pixel sizes (frame × scale); click on region A | selection start/end pixel points = A's corners × scale, flipped (hand-computed) | same | none |
| A6 | AC-09, AC-11, AC-06 | S3 | frames held; per-call lists (first: own-process window in front over the click point + window at local x 200; second: no window); window-list calls counted | one call before frames are released; click → toolbar at +200 (own window skipped, first list used); still one call after commit | per-call lists | app composition |

Review of the rows. Dimension 1: they drive the paths the findings name — the drag-event guard, the
release-only rule, the settled guards (U8–U11), side and auto-hide strips and the scale/height pixel
rule (C4, C7), the crop end points (U12), the listing's timing, count and own-PID exclusion (A6).
Remaining gaps recorded, not tested: multi-display offsets and leaving a display (finding 7), AC-11
hover latency with many windows, the real auto-hide visible frame — installed-build or two-display
checks. Dimension 2: public seams only; A6 counts calls on the injected adapter, an injection seam.
Dimension 3: expected values are literals or hand-computed; U8 and U9 sit on either side of the
threshold so a moved threshold or `>`/`>=` change turns one red; U10 turns red without the
release-only rule; U12 compares pixel points, not the frame used for the toolbar; A6's second list
would change the toolbar position if the list were read again before the click; a read after the
click leaves the toolbar alone and is caught only by the call count (corrected after incremental
finding 11). Dimension 4: no new resource.
Findings: none.

### Self-check of the findings fix (2026-10-28)

- Item 2 (new assertions), corrected after incremental finding 11: the first batch
  (`logs/snap-mutations.log`) turned red U8 (drag guard removed; `>` → `>=`), U10 (release-only rule
  removed), U11 (settled guard removed), the pixel-minimum test's scale-1 point (pixel scale dropped),
  the left-Dock expectation (left branch disabled) and A6's toolbar position (own PID not excluded).
  It did not cover U9, C4's fall-through, the right Dock, the narrow and low windows, U12 or A6's call
  count; those were shown red in the second batch (`logs/snap-mutations-r3.log`, listed under the
  handling of findings 9–12). U12 compares against values of 200 px and more with a 0.001 tolerance.
- Item 3 (changed functions): no product function changed in this fix; test helpers `makeDisplay`
  (new `pixelScale`, default unchanged), `committedSnapOverlay`, `SelectionLog`, `FixtureWindowListing.calls`.
- Item 4 (data): side-Dock and auto-hide displays reuse the sampled frame; the auto-hide visible frame
  reaching the edge is assumed and recorded as an installed-build check (resolver test header, spec).
- Item 5 (shared helpers): `FixtureWindowListing` and `makeDisplay` are used only in their own test
  files (`grep -rln "FixtureWindowListing\|makeDisplay(" Tests Sources Scripts` → the App and UI test
  files, plus `CaptureSelectionSessionTests.swift`, which declares its own private `makeDisplay`
  unrelated to the changed one); both files run in the targeted verification below.
- Findings of the self-check: none.


## Post-implementation check — incremental round (2026-10-28)

No ticket (no-ticket path, as above). Incremental round for the handed fix range `14336d6..48610ef`
(one commit; whole change `8c00b2d..48610ef`). Implementation version: `48610ef`. Product code is
unchanged since `5c96041` (`git diff --stat 5c96041..48610ef -- Sources VLMSnapper Package.swift
Package.resolved Scripts` is empty): the fix changes tests, test helpers and records only. Date,
version and range apply to every dimension below. Everything outside the objects below is carried over
from the first round ("Post-implementation check (2026-10-28)" above).

### Objects

- Tests changed in the range (`git diff --stat 14336d6..48610ef -- Tests/`: 3 files, +180 −10; every
  hunk read):
  - resolver tests: `snapsDockStrip` (:86, auto-hide case rewritten), new `snapsSideDockStrips` (:110)
    and `appliesPixelMinimumAtDisplayScale` (:163), helper `resolver(front:back:dockVisible:)` (new
    `back`), header note;
  - UI tests: new U8 `jitterWithinThresholdIsClick` (:188), U9 `moveJustOverThresholdDrags` (:199), U10
    `farReleaseWithoutDragEventsDrags` (:210), U11 `clickedRegionDoesNotFollowPointer` (:219), U12
    `clickedRegionMapsToPixels` (:236); helper `makeDisplay(id:screen:pixelScale:)` (new parameter), new
    `SelectionLog` and `committedSnapOverlay`; gap comment above U1;
  - App tests: new A6 `windowListIsReadOnceAtTriggerWithoutOwnWindows` (:1357); `FixtureWindowListing.calls`;
    header note.
- Tests depending on the changed helpers. Every changed helper is `private`, so only its own file can
  use it; searched over the whole tree anyway:
  `grep -rn --include=*.swift -E "FixtureWindowListing|committedSnapOverlay|SelectionLog|makeDisplay\(|func resolver\(|Self\.resolver\(" Tests Sources VLMSnapper Scripts`.
  Result: resolver tests — `Self.resolver(` in all 8 test functions; UI tests — `makeDisplay(` at :22,
  :69, :88, :115, :130, :172, :246, :270 and inside `committedSnapOverlay` (:397, used by U8–U10), i.e.
  11 of the 14 functions (not `pendingOverlayAppearsWithoutOpeningAnimation`, U5/U6, U11);
  `CaptureSelectionSessionTests.swift` declares an unrelated private `makeDisplay(id:width:height:)`;
  App tests — `FixtureWindowListing()` only at :2168 inside `ApplicationFixture`, built only by
  `withFixture` (:2091), which every App test reaches (`grep -n 'withFixture\|withSnapFixture'`: all 36
  Swift Testing functions and the three `ProviderApplicationTestsNativeMenu` cases at :64, :108, :157).
- Test design table rows changed in the range: "Increment: rows for findings 2–6 and 8" — A3, C4, C7
  (rewritten), U8–U12, A6; plus the correction sentence in the design review's Dimension 1 (:50–52),
  which is not a row.

The helper changes keep their defaults: `back: []` appends nothing, `pixelScale: nil` keeps the 2 × 2
geometry, `calls += 1` changes neither the returned list, its order nor any suspension point. The
dependents therefore run the inputs of the first round; their rows and "goes red when" answers are the
first round's (snap tests) or their own features' (pre-existing App and UI tests, which have no row in
this table and whose assertions the range does not touch). Below, only what the new code reaches is
judged again.

Capability declaration: `tomllib` on `capabilities.toml` → `FileNotFoundError` — 项目无能力声明文件;
未确认 mutation-testing; 未确认 working-language. Same item as finding 1 (user decision 2026-10-28:
separate PR); not a new finding. This round runs no mutation and edits no code; "goes red when" answers
are derived from the code under test, citing the fix's mutation logs where they exist. Fixed names
follow this record's English precedent.

### Run evidence

Handed-over log, not rerun: `logs/targeted-snap-findings.log`, byte-identical (`cmp`) to the
scratchpad log; written by the scratchpad `targeted-snap.sh`, whose echo lines it reproduces.

| Log requirement (full verification gate) | Log content | Verdict |
|---|---|---|
| Tested version | `git rev-parse HEAD` = `14336d6…`; porcelain lists 9 modified and 4 untracked files with `git hash-object` hashes. Each equals `git rev-parse 48610ef:<path>`; the only file of `48610ef` not listed is this log, written by the run; `:-` (`208ccf64…`) as before | Matches `48610ef` |
| Every command | strict build; `build --build-tests`; non-App suite (`--skip ProviderApplicationTests`); App suite (`--filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu`); three native cases | Present |
| Exit code not taken through a pipe | `== exit: N` from `local c=$?` right after a redirect (`run()` in the script); all 0, `== overall: 0` | Present |
| Full output | Build and test output of every command | Present |

Reviewed objects in the log: resolver 8 tests (:952–1010, suite :1127), UI 14 (:1271–1415, suite
:1416), App 36 (:1437–1535, A6 :1509), native 3 (:1537–1593). Totals: non-App 382 (:1425) = 375 + 7
new; App 36 (:1535) = 35 + A6. Conclusion: the log meets the log requirements and is this round's run
evidence.

### Test design table check

| Row | Written test | Verdict |
|---|---|---|
| A3 (rewritten) | `clickWithoutWindowListSelectsNothingButDragStillWorks` (App :1308) | Matches |
| C4 (rewritten) | `snapsDockStrip` (:86), `snapsSideDockStrips` (:110) | Matches (row literals) |
| C7 (rewritten) | `appliesPixelMinimumAtDisplayScale` (:163), `clipsToDisplayAndSkipsTinyWindows` (:144) | Matches |
| U8, U9, U10 | UI :188, :199, :210 | Match (U10's pair is 50 pt apart on each axis) |
| U11 | UI :219 | Matches (pending overlay, no commit) |
| U12 | UI :236 | Matches |
| A6 | App :1357 | Matches |

Resource columns match. Gap notes: resolver header (:10–12) adds the auto-hide visible frame; UI comment
(:54–59) adds hover latency and the three two-display paths; App header (:46–47) adds hover latency and
the real window list — matching spec Testing Decisions (:392) and `tasklist.md` :72–76.

### Dimension 1: Coverage

| Spec item | Rows of this range | Verdict |
|---|---|---|
| AC-04 pinned strip, side Docks, auto-hide falls through | C4 | Covered; real side-Dock and auto-hide geometry is derived from the bottom-Dock sample and recorded as installed-build checks |
| AC-06 < 2 × 2 physical pixels *after clipping to the display* | C7 | Scale, the 2 px boundary, width and height covered; "after clipping" not driven: finding 10 |
| AC-06 own windows in the app | A6 | Covered |
| AC-07 / FM-47 ≤ 3 pt click, > 3 pt rectangle, region stops following | U8–U11 | Release threshold on both sides, release-only and settled hover covered; jitter under 3 pt as drag events and the rectangle shown once a drag event passes 3 pt not driven: finding 9. Settled guard in `mouseExited`: inside the recorded two-display gap (leaving a display) |
| AC-02 / AC-07 crop of a click | U12 | Covered at the controller (pixel corners); corners → crop is the existing selection-session tests' |
| AC-09 / FM-47 list taken at trigger, not re-read; "不轮询" | A6 | A re-read before the click is covered; after the click it rests on an assertion never shown red: finding 11 |
| AC-11 latency | — | Recorded as installed-build check |

Touched regression points: none in product code. Fixture shape: the window behind the Dock, the
sub-pixel windows and A6's lists keep the recorded sample's structure (front to back, layer 0, global
top-left bounds); A6's own entry carries the test process PID, as production excludes its own. Side-Dock
and auto-hide visible frames are constructed from the sampled frame, not sampled (recorded).

Conclusion: findings 9, 10, 11.

### Dimension 2: Case design

The new tests act through public entry points and read public observables (`region(at:on:)`,
`Selection.screenFrame`, `Selection.start`/`end`, rendered layer alpha, toolbar frame, the injected
adapter's call count). `makeDisplay(pixelScale:)` gives the geometry production has (pixels = frame ×
scale) over a 2 × 2 image; the mapping reads only the geometry, and a controller reading the image size
would turn U12 red, not green. `committedSnapOverlay` and U11 take the real pointer for the opening
region; each test presses before asserting, which replaces it. Isolation as in the first round.
Basic check "drives the target behaviour": U9's drag event does not decide its result — the release
alone gives the same rectangle (finding 9).

Conclusion: finding 9.

### Dimension 3: False greens

Mutation check: not run (finding 1). Red evidence below is from `logs/snap-mutations.log` and the
scratchpad `mut-*.log` it summarises (failure lines and values checked).

| Test | Goes red when | Stays green although wrong |
|---|---|---|
| `snapsDockStrip` (C4) | wrong bottom strip; the Dock window snapped whole or "no strip → display" (both (0, 0, 1512, 982) ≠ the window below); strip returned without a Dock window | auto-hide inset (recorded) |
| `snapsSideDockStrips` (C4) | left branch removed (shown, :116 → display); right branch removed (→ Chrome clip (400, 60, 1112, 700)); strip from `frame.minY` or of wrong height | — |
| `appliesPixelMinimumAtDisplayScale` (C7) | scale dropped (shown, :171); `>=` → `>`; width clause dropped (:172); height clause dropped (:173); threshold ≤ 1.5 or > 2 px | unclipped bounds measured (finding 10); a threshold in (1.5, 2] px (no realistic alternative; no finding) |
| `clipsToDisplayAndSkipsTinyWindows` (C7, carried) | as first round | unclipped bounds measured (finding 10) |
| U8 | `mouseDragged` guard removed (shown, :195); `>` → `>=` (shown, :195); threshold under 3 | guard `<` or `!=`, or a `mouseDragged` that never starts a drag (finding 9) |
| U9 | shared threshold ≥ 3.54 pt; per-axis distance; wrong rectangle | anything in `mouseDragged` (finding 9); a sum-of-axes distance (no realistic alternative; no finding) |
| U10 | release-only rule removed (shown, :215) | — |
| U11 | settled guard removed from `mouseMoved` (shown, :231, :232) | settled guard in `mouseExited` (two-display gap) |
| U12 | corners swapped or mixed, press point instead of the region, missing flip or scale (expected ≥ 200 px, tolerance 0.001) | — (not shown red) |
| A6 | own PID not excluded (shown, :1385, 80 pt off); listing moved after the freeze (`calls == 1` before release hits the deadline); a second read before the click (empty list → display edge; count 2) | a second read after the click: only :1386 sees it, never shown red (finding 11) |
| U2 `dragIgnoresSnapRegion` (dependent) | as first round | a `mouseDragged` that never starts a drag — the release 40 × 40 pt away gives the same rectangle (finding 9) |
| Other dependents | inputs unchanged; answers as first round / their features | — |

Forms: always-true — none (expected literals differ from the neighbouring candidates: region vs dragged
rectangle in U8–U10, window below vs display in C4, kept window vs display in C7); tautology — none
(literals, hand-computed corners); stale path — none (`screenFrame`, `start`/`end` are what the model
consumes, model :1303–1330); conditional skip — none (`#require` throws); assertions that may not run —
none (U12 `#require(corners.first)` plus the count; App waits throw on deadline).

UI and rendered assertions (`review-code/false-greens.md`): U11 asserts effects in pairs, and its "does
not follow" was made to happen once (settled-move mutation red on both lines). A6's "no second read"
(:1386) was never made to happen ("not mutated", self-check item 2) and is read after polling the
toolbar (:1383), not the count: finding 11, which also covers the self-check's claim that every new
assertion was turned red.

Conclusion: findings 9, 10, 11.

### Dimension 4: Resource reuse

| Resource | Built | Measured (targeted log) | Expensive (≥ 1 s)? |
|---|---|---|---|
| Resolver window list (`Self.resolver`, now with `back`) | per call | 8 tests, suite 0.116 s (:1127) | No |
| Overlay panels and `FrozenCaptureDisplay` (`makeDisplay`, optionally pixel-sized geometry over the same 2 × 2 image; `committedSnapOverlay`) | per UI test | U2–U12 0.109–0.321 s (:1349–1410). The suite's first three tests report 7.033, 3.298 and 4.731 s (:1271, :1310, :1335), the values unrelated suites report at the same moments (:1278, :1280; :1308–1315; :1331–1334): a shared main-actor stall, not setup. Run alone (`logs/snap-findings-unit.log`): 0.018–0.147 s each | No |
| Application composition with `FixtureWindowListing` (`withFixture`, `withSnapFixture`) | per App test, as before | A6 0.329 s (:1509), other snap tests 0.088–0.422 s; `injectedUpdateEventsReachTheApplicationPresentation` 0.025 s for composition plus body (:1523) | No |

No expensive resource, so no load count to compare; no reviewed test clears a shared resource, so the
collection-order rule does not apply. The new tests reuse the existing helpers (`twoWindowResolver`,
`primaryOverlay`, `send`, `click`, `renderedAlpha`; `withSnapFixture`, `eventually`, `sendMouse`,
`pumpNativeEvents`, `mainScreenOverlay`, `captureToolbar`).

Conclusion: no finding.

### Document sync

Range as in the first round (same documents and exclusions). `find docs/.workings/capture-region-snapping`
(hidden entries included): 15 files, one subdirectory, no dotfiles; `git check-ignore` matched none.
Changed facts, from the range only: the tests and gap notes under Objects, the targeted run (all pass;
382 / 36 / 3), the records the fix corrected. Content search: `/usr/bin/grep -a -n -E` for test IDs,
counts, installed-build, two-display, auto-hide, latency, crop, single-read and mutation terms over
`final-regression.md`, `review-code.md`, `tasklist.md`, `logs/change-scope-after-findings.txt`,
`docs/.workings/v1-core/checklist.md`, `docs/specs/v1-core.md`, `docs/features/v1-core.md`,
`CONTEXT.md`, ADR-0014, `AGENTS.md`, `CODEX.md` (276,486 bytes; 107 hits, all read); this record,
`review-code.md` and the three test headers read in full.

First round's list of statements to correct: corrected — `review-code.md` :19–22; `tasklist.md` :32,
:64, :66, :68, :72–76; checklist :21; this record (increment rows, :50–52). Not corrected —
`final-regression.md` :14, :51–52 (finding 12).

Statements this round's findings make untrue or incomplete: `tasklist.md` :63 (AC-06 evidence, finding
10), :64 ("threshold both sides", finding 9), :70 ("No missing or partial item", findings 9–11),
:82–86 (finding 12); this record :50–52 (jitter "now U8–U11", finding 9), :437–446 (drag-event guard,
A6's second list; findings 9, 11), :451–457 (finding 11); App tests :1367 (finding 11). Spec, feature
catalogue, `CONTEXT.md`, ADR-0014 and checklist :21 state behaviour or passing tests, not depth, and are
unaffected. None of the listed statements may be closed before its finding is handled.

### Findings

9. **AC-07 / FM-47: the drag-event path is pinned only at exactly 3 pt; jitter under 3 pt and the
   rectangle shown while dragging are not driven.** Missed regression. Evidence: every drag event in the
   suite is exactly 3 pt (U8 :193) or beyond it (U9 3.54 pt, U2 50 pt, REQ-005 test 141 pt, `drag()`
   184–224 pt; `grep -rn 'leftMouseDragged'` over `Tests`, `Sources`, `VLMSnapper`, `Scripts`), and no
   test reads the overlay between a drag event and the release (`renderedAlpha` only in U5/U6 and U11;
   the App suite's `overlayShowsFrozenFrame` reads the frozen frame at the centre). With the guard in
   `mouseDragged` (controller :404) turned to `<` or `!=`, U8's 3 pt event still starts no drag, and U9,
   U2 and every other drag still end in the same rectangle, because `mouseUp`'s release-only rule
   (:415–418) starts it at the release; a `mouseDragged` that never starts a drag passes the same way.
   Impact: with `<`/`!=`, a click with 1–2 pt of jitter — physical jitter arrives as several small drag
   events — becomes a tiny rectangle the app rejects as too small, so the click does nothing (FM-47
   "按下后抖动不超过 3 pt 仍是单击"); with a dead `mouseDragged`, no rectangle is drawn while dragging and
   the snap region stays highlighted until release (AC-07 "改为手绘矩形，吸附区域停止跟随"). Recommended: U8
   sends drag events at 1 pt and 2 pt before the 3 pt one; U2 asserts after its drag event, before the
   release, rendered alpha 0 inside the dragged rectangle (e.g. (270, h − 185)) and > 100 at a point of
   window A outside it (e.g. (150, h − 250)); show each red once by temporarily inverting the guard;
   update rows U8 and U2 and the statements listed under Document sync. Destination: this branch.

10. **AC-06: the 2 × 2 pixel rule is never applied to a window larger than its part on the display.**
    Missed regression. Evidence: the resolver measures the clipped rectangle (resolver :78–80), as AC-06
    requires ("裁到该显示器后不足 2 × 2 物理像素的窗口跳过"), but every small test window lies wholly inside
    its display (C7 :151, pixel-minimum :164–168), so clip and bounds coincide, and the only clipped
    window, Chrome, keeps 88 × 700 pt (:156). Measuring `window.bounds` instead passes every test.
    Impact: a window reaching under 1 pt onto a display (parked past an edge, or overlapping the
    neighbouring display) becomes a one-pixel region there; a click on it gives a selection under
    2 × 2 px, which the app drops (`selectionTooSmall`, model :1333), instead of selecting what lies
    below. Recommended: add to `appliesPixelMinimumAtDisplayScale` a front window straddling the left
    edge, e.g. (−100, 700, 100.75, 100) at scale 2 (clip 0.75 pt = 1.5 px), expecting the display frame
    at (0.3, 750); update row C7. Destination: this branch.

11. **The fix's red evidence is narrower than its record says, and A6's guard against a re-read after
    the click is unproven.** Untrue record and evidence; the A6 part backs a missed-regression
    conclusion. Evidence: self-check item 2 (:451) says each new assertion was turned red by a temporary
    mutation; the logs show red only at UI :195 (two mutations), :215, :231–232, resolver :171, :116 and
    App :1385 — none for U9 (:206), C4's fall-through (:98–101), the right Dock (:122), the narrow and
    low windows (:172–173), U12 and A6's count (the last two acknowledged). For A6, the row review
    (:445–446, "A6's second list would change the toolbar position if the list were read again") and
    the test comment (App :1367) hold only for a read before the click: a second read after it, such as
    a refresh at commit, finds the click resolved and the view settled (`attachSnapRegions` ignores a
    settled view, controller :338), leaves the toolbar at +200 and is visible only to
    `#expect(calls == 1)` (:1386), which runs after polling the toolbar (:1383), not the count, and was
    never made to fail (false-greens: 凡断言「X 不发生」先让 X 发生一次; 读得太早). A6 is the only test of
    "窗口列表只在触发时读取一次" (spec Testing Decisions :392) for reads after the click. The Dimension 3
    answers above show the other assertions do go red. Recommended: rewrite item 2 to list the
    assertions actually shown red; correct :445–446 and the App comment ("a read before the click moves
    the toolbar; a later one is caught by the call count"); make :1386 fail once with a temporary second
    read at commit, confirming the failure lands there, and keep that log. Destination: this branch.

12. **`final-regression.md` was not brought in line with the gaps the fix recorded.** Untrue record.
    Evidence: :14 still lists REQ-006's pending checks as "real window list, Dock/menu-bar geometry,
    physical hover", while spec Testing Decisions (:392), `tasklist.md` :72–76 and checklist :21 also
    list the auto-hide visible frame, hover latency and the two-display acceptance; :51 claims
    convergence "as of `5c96041` plus the documentation commits", but :16 now rests on tests added in
    `48610ef`. The first round listed :14 and :51–52 for correction; `tasklist.md` :82–86 reports
    `final-regression.md` corrected and "records listed above now match the tests". Recommended: extend
    :14's pending list (installed build: auto-hide visible frame, hover latency; two displays: deferred
    acceptance) and restate :51 against `48610ef`. Destination: this branch.

## Handling of incremental-round findings 9–12 (2026-10-28)

Read in full from the incremental round's Findings subsection; hand-back titles match the record.

### Increment: rows for findings 9–11

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| U8 (extended) | AC-07, FM-47 | S2 | down; drag events 1 pt, 2 pt, 3 pt away; up at 3 pt | selection = the snap region (literal) | two-window resolver | none |
| U13 | AC-07 | S2 | pending overlay; down at (250, h − 200); drag event to (290, h − 170); read before release | rendered: clear inside the dragged rectangle at (270, h − 185); dimmed at (150, h − 250), inside window A but outside the rectangle | same | none |
| C7 (extended) | AC-06 | S1 | scale 2; window (−100, 700, 100.75, 100) straddling the left edge (0.75 pt = 1.5 px on the display) | point (0.3, 750) → the display frame (literal) | sample display | none |
| A6 (strengthened) | AC-09, AC-11 | S3 | as before; after the toolbar appears wait 100 ms, then read the call count | one call; a temporary second read at commit must turn this red | per-call lists | app composition |

Review: Dimension 1 — U8/U13 drive the drag-event guard below 3 pt and the rectangle shown while
dragging; C7's straddling window drives the clipped measurement; A6 drives a read after the click.
Dimension 2 — public seams. Dimension 3 — each to be shown red by a temporary mutation (guard `<`,
dead drag start, bounds instead of clip, second read at commit), with the earlier unproven assertions
mutated in the same batch. Dimension 4 — no new resource. Findings: none.

### Mutation evidence for findings 9–11 (`logs/snap-mutations-r3.log`; sources restored, build exit 0)

| Mutation | Test turned red (line) |
|---|---|
| drag guard `>` → `<` | U8 jitter (UI :198), U13 mid-drag (UI :225) |
| drag never starts in `mouseDragged` | U13 (UI :225) |
| threshold 3 → 4 | U9 (UI :209) |
| start corner uses maxY | U12 (UI :274) |
| bounds instead of the clipped part | straddling window (resolver :176) and the two clip cases (:72, :154) |
| Dock without strip returns the display | auto-hide fall-through (resolver :98), plus :69–72, :140 |
| right-Dock branch disabled | right Dock (resolver :122) |
| height clause dropped | low window (resolver :175) |
| width clause dropped | narrow window (resolver :174), :159, :176 |
| second window-list read at commit | A6 call count (App :1389) |

### Records corrected for findings 11–12

Self-check item 2 and the A6 row review rewritten above; A6's test comment and a 100 ms wait before
the count; `final-regression.md` pending list and convergence statement restated.

### Self-check of this fix

Item 1: no product code changed. Item 2: every new or strengthened assertion shown red (table above).
Item 3: no product function changed. Item 4: the straddling window extends the sampled display; no
new data shape. Item 5: no shared helper changed in this fix. Findings: none.

