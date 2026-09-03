# Capture self-exclusion test review

## 2026-09-03

### Dimension 1: coverage completeness

| Behavior or boundary | Evidence | Conclusion |
|---|---|---|
| A result workspace reserved for capture is usable after capture failure | `failedCaptureRestoresPreparedWorkspace` starts a real operation after restoring the public session state | Covered |
| A replacement overlay cannot destroy the current overlay when no replacement display can be presented | `failedReplacementKeepsCurrentOverlay` presents a screen-backed overlay, attempts an empty replacement, and checks the prior display identity remains | Covered |
| A replacement-capture failure remains visible above the retained selection overlay | `failureAlertStaysAboveRetainedOverlay` applies failure presentation to a real `NSAlert` and compares its window level with `.screenSaver` | Covered |
| Menu capture routes reach application readiness handling without waiting for popover dismissal | `captureRouteActions` checks all three public routes | Covered at the routing seam |
| Current-process exclusion uses the real macOS compositor | Unit construction of private ScreenCaptureKit objects would not prove compositing; `ConfirmedSurfaceContractTests` names the signed-App condition | Explicit integration gap: verify in a signed app on macOS 14.4+ |
| Application-model commit order across frozen capture, overlay presentation, and source retirement | The current model owns concrete ScreenCaptureKit and AppKit controllers and has no injectable integration seam | Explicit integration gap: verify in the signed app; no private-state test was added |
| Packaged minimum system is 14.4 | Fresh arm64 app verification plus `otool -l`; a copied artifact with `LSMinimumSystemVersion=14.0` is rejected by `verify-macos-app.sh` | Covered for build and packaged-app verification |
| Release appcast rejects another minimum version | The script compares the generated appcast value with 14.4, but the complete formal release requires signing, notarization, and release credentials | Explicit formal-release gate; syntax and source inspected, end-to-end run deferred to a real release exercise |

Conclusion: deterministic state transitions and the packaged minimum-version gate are covered. The two compositor-dependent behaviors are identified with their real signed-App test condition instead of being simulated.

### Dimension 2: case design

- Both new tests use public actor/controller behavior and observable outcomes. Neither casts to private state, mocks project code, or asserts internal call counts.
- The overlay test uses an actual `NSScreen` identity and a real panel presentation before attempting replacement; it cannot silently pass without entering the target branch.
- The workspace test drives `prepareForCapture`, restoration, and a subsequent operation through public methods. Its successful runner result proves the session was reopened rather than merely checking a copied flag.
- No external data fixture changed; the new behavior consumes system ScreenCaptureKit objects, for which the real signed-App observation is retained as the independent integration source.

Conclusion: case setup reaches the named states and assertions observe user-relevant effects without implementation-only shortcuts.

### Dimension 3: false-green review

- Workspace mutation: replacing `restoreAfterCaptureFailure` with a no-op compiled and failed at the intended test with `busy`. Restoring only the mutation returned the test to green.
- Overlay mutation: closing the current overlay before returning replacement failure compiled and failed at the intended display-identity assertion (`[]` versus the prior display ID). Restoring only the mutation returned the test to green.
- Alert mutation: leaving the alert at its default level compiled and failed at the intended level assertion (`0` versus `.screenSaver` at `1000`). Restoring only the mutation returned the test to green.
- Minimum-version mutation: changing a copied built app's plist from 14.4 to 14.0 made `verify-macos-app.sh` fail at `Unexpected LSMinimumSystemVersion` before signing checks.
- Full suite after restoration: 263 tests in 68 suites passed. The Swift Testing target label `macos14.0` is not used as minimum-version evidence; the packaged Mach-O `minos 14.4` and plist verifier are the relevant observations.

Conclusion: each new automated assertion has a demonstrated target failure mode, and no environment failure or unrelated red result is counted as evidence.
