# Instant capture overlay implementation tasklist

Base: `850f64d` (origin/main, 2026-10-28). Requirement source: the user asked
to remove the visible delay between the capture shortcut and the selection
overlay after comparing VLMSnapper with a static reverse-engineering report of
Snipaste 2.7.2; `docs/specs/v1-core.md` already requires the overlay to appear
immediately after the shortcut.

## Success criteria

1. After a capture is admitted, the selection overlay covers every display
   before the freeze finishes (application seam, held capturer).
2. A rectangle dragged before frozen frames arrive is completed against those
   frames once they arrive; the operation toolbar then appears.
3. `Esc` while frames are pending exits capture: no overlay, no toolbar, no
   history, the capture activity is released, and a reserved result workspace
   becomes usable again.
4. Freezing failure while a previous selection exists withdraws the pending
   overlay and restores the previous overlay and toolbar unchanged.
5. Termination preparation while frames are pending withdraws the overlay.
6. Existing capture regression tests stay green (replacement retirement,
   display invalidation, observer registration, termination, exclusivity).
7. Presenting the pending overlay costs a few milliseconds on the main thread
   and dragging no longer redraws the frozen frame on the CPU (measured with
   the production overlay controller).
8. Rendered overlay matches the existing appearance (scrim, border, 1:1 frozen
   pixels), checked from a rendering of the production controller.

## Tasks

- [x] Test design review recorded in `review-tests.md` before any test change.
- [x] Vertical slice 1: pending overlay before freeze completes (criteria 1, 6).
- [x] Vertical slice 2: selection made while pending completes after commit (criterion 2).
- [x] Vertical slice 3: `Esc` and termination while pending (criteria 3, 5).
- [x] Vertical slice 4: failed freeze restores previous selection and toolbar (criterion 4).
- [x] Overlay controller unit tests adapted to present/commit/rollback.
- [x] Targeted verification (build, affected tests, lint per gate).
- [x] Measurement and rendering evidence (criteria 7, 8), recorded in `measurements.md`.
- [ ] Step 5: `/review-code`, recorded in `review-code.md`.
- [ ] Full verification gate (pre-review run).
- [ ] Step 6: `/review-tests` post-implementation check.
- [ ] Spec final check; ADR, spec, CONTEXT, feature catalog updates.
- [ ] Full verification and delivery.

## Targeted verification (2026-10-28)

- Bug reproduction first red on unfixed code: `overlayCoversDisplaysBeforeFreezeCompletes`
  failed with `deadline` at the wait for an overlay while the capturer is held
  (provider setup had passed), then passed after the change.
- Strict build with CI flags (`-warnings-as-errors`, `-Wall -Wextra -Werror`): exit 0.
- `swift test --filter VLMSnapperUITests`: 77 Swift Testing tests and 29 XCTest cases passed.
- `swift test --filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu`: 27 tests passed.
- Affected-test search: `grep -rl "import VLMSnapperUI\|import VLMSnapperApp\|@testable import VLMSnapperApp" Tests`
  lists the `VLMSnapperUITests` files (run above), `ProviderApplicationTests.swift`
  (run above, plus its three `ProviderApplicationTestsNativeMenu` XCTest cases run
  one by one as CI does: all passed) and `Tests/AXFixture/main.swift`, an executable
  fixture that does not reference the overlay or toolbar and builds in the strict
  build. No test reads a changed configuration or data file.
