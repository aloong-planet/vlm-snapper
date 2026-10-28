# Ticket 26 — code review

Ticket: [26](issues/26-deterministic-reasoning-timeout-test.md). Date 2026-10-28. Scope: `8c00b2d..HEAD` on
`fix/deterministic-reasoning-timeout-test` — one test and its test doubles in
`Tests/VLMSnapperCoreTests/ProviderAdapterExecutorTests.swift`; no product code.

## Underlying premises

- The failure is timing, not behaviour: the old test slept 150 ms on the real clock between events against
  250 ms deadlines. Reproduced: with the test process paused for 300 ms at a time (`ticket-26-logs/stall.sh`)
  the unfixed test failed 5/5 with the CI error `ProviderAdapterExecutorTests.swift:106:6: Caught error:
  firstTextTimeout` (`ticket-26-logs/unfixed-with-300ms-pauses.log`). Plain CPU load did not reproduce it
  (15/15 passed, `unfixed-under-cpu-load-summary.txt`); the CI runner's stall is the trigger.
- The coordinator arms deadlines in their own tasks, so registration order with the clock is not
  guaranteed; the test fires a snapshot of earlier deadlines rather than relying on arm indices.
- New comments state behaviour of the test doubles; the causal one ("so host load cannot end the stream")
  is shown by the fixed test passing 5/5 under the same pauses (`fixed-with-300ms-pauses.log`).

## Runnability

The manual clock ends a sleep only when fired or cancelled; cancellation before suspension is recorded
and honoured. A fired deadline that was superseded is no longer pending, so firing it is a no-op. The
5-second guard bounds waiting for a re-armed deadline. A 50 ms real pause after firing lets a still-live
deadline reach the stream before the text; it matters only when the behaviour is broken. No finding.

## Security

Test-only change. No finding.

## Consistency

Same seam as the neighbouring timeout tests (`ProviderTimeoutClock` injection); assertions unchanged plus
one on the armed deadlines. Mutations (`ticket-26-logs/mutations.log`): old deadline not cancelled → red
at the stream (`:106`, `firstTextTimeout`); reasoning not re-arming → red at the armed-deadline count
(`:132`). Sources restored. Refactoring list: none.
