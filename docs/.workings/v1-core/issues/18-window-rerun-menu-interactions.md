# Ticket 18: Result window, rerun history, and menu interactions

## Reported regressions

1. The result workspace remains above other applications after the user clicks elsewhere.
2. Running **Try Again** for the same screenshot and operation creates another history row instead of updating the current row.
3. Menu-panel actions only respond over their text and do not provide the confirmed full-row hover treatment.

## Confirmed behavior

- The result workspace is brought forward when it is first opened or explicitly requested, then behaves as a normal window and may move behind other applications.
- A rerun belongs to the existing screenshot-operation slot. A successful rerun replaces that history record's result instead of inserting another record.
- Capture, recent-record, History, and Settings actions use their complete visible bounds as the hit target and show a hover state across those bounds.

## Existing prototype evidence

- `docs/prototypes/companion-shell/prototype-companion-directions.html` already depicts the result workspace behind the menu panel and defines full-row hover states for the capture, recent-record, and footer actions.
- `docs/prototypes/core-result/prototype-layout-directions.html` already contains the confirmed result workspace and rerun action. No new visual direction is introduced by this repair.

## Implementation checklist

- [x] Add red tests for normal window level and non-presenting content refresh.
- [x] Add a red persistence test proving a rerun reuses one history identity and replaces its result.
- [x] Add a red menu interaction contract for full-width hit targets and hover presentation.
- [x] Repair the narrow production seams.
- [x] Run targeted and full verification.
- [x] Complete code review, test review, and documentation consistency.
- [x] Prepare the pull request and wait for merge confirmation.

## Verification

- Strict Swift/C warnings-as-errors build passed.
- Full Swift Testing run passed: 246 tests in 65 suites.
- Ticket 13 production rendering passed: 44 bilingual light/dark images.
- Window-level, menu hit-target, and hover mutations each failed at the intended assertion and returned green after restoring only the mutation.
- A locally installed build still requires WindowServer acceptance for physical hover and cross-application background ordering.
