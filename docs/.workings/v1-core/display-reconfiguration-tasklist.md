# Live display reconfiguration — implementation

Scope: accepted US-03 / ADR-0010 and `issues/01-live-display-reconfiguration.md`. Continue the existing dirty closeout branch without discarding accepted visual/lifecycle work. This is not permission to merge or install.

UI admission: restore the existing per-display selection cancellation lifecycle; no new visual state, copy, icon or layout. The confirmed toolbar is unchanged. Do not invent an unavailable-screen panel. Measure native panel visibility and retained content rather than asserting a new visual design.

Seams: production application composition with isolated notification centers and display-geometry reads at the macOS boundary; existing real overlay controller and selection session. Do not mock internal selection/coordinator logic. System display notifications are on the main actor; screen sleep additionally arrives through NSWorkspace.

- [x] Red: native selection remains visible after display sleep/configuration loss before mouse-up.
- [x] Green: revalidate after freezing; observe configuration and sleep during selection/cropping, revalidate again after registration, invalidate only affected displays, release listeners on terminal paths.
- [x] Cover unchanged/new display snapshots, replacement, Escape, active-selection termination and successful crop in the application; retain core changed-display/crop race tests. A post-freeze registration-gap test is red/green.
- [ ] Hardware acceptance: actually disconnect one of two displays, change scale/rotation/arrangement and sleep/wake; verify the surviving display and Escape focus. Notifications in tests are injected, not real hardware events. Pending-freeze termination generation guards are code-reviewed, not claimed as a new controlled integration test.
- [ ] Strict build and complete non-App/App/native test gates.
- [x] Separate scoped review-code, including async/generation/resource boundaries and explicit hardware evidence limits.
- [x] Separate scoped review-tests, including injected event delivery and targeted failure evidence.
- [x] Spec/feature/checklist and three-stage scoped consistency update; keep full Ticket 23 open where unrelated criteria remain.

## Evidence — 2026-09-09

- Missing sleep wiring red: `/private/tmp/vlmsnapper-display-red.log`, exit 1 at the pre-mouse-up cancellation deadline; initial green `/private/tmp/vlmsnapper-display-green.log`.
- Registration gap red: `/private/tmp/vlmsnapper-display-race-red.log`, exit 1 because capture remained active; second snapshot fixes it.
- Config-forwarding mutation: `/private/tmp/vlmsnapper-display-mutation.log`, rebuilt App module, `DISPLAY-CONFIG-MUTATION reached` independently confirms arrival. Disconnect/scale/rotate/move fail at `!overlay.isVisible`; only the temporary callback mutation was restored.
- A test initially observed the published activity too early. It now waits for `.capture` before posting cancellation. That failure was test synchronization, not a second production defect.
- Final strict build: `/private/tmp/vlmsnapper-display-strict.log`, exit 0. Non-App: 333 tests / 73 suites, 19.940 s. App: 14 tests, 7.521 s (five change cases in one parameterized test). Logs: `/private/tmp/vlmsnapper-display-nonapp.log`, `/private/tmp/vlmsnapper-display-app-final.log`.
- Full native gate: `/private/tmp/vlmsnapper-display-native.log`, exit 1, 3 tests / 1 failure at key-window activation; tracked in #24, no retry and no full-green claim. Checklist: six parser tests + 58 ownership rows; shell syntax and diff checks pass.
- No new UI copy, glyph, color or layout; no literal-key additions. Existing confirmed toolbar remains unchanged. No commit, push, merge, release or installation.
