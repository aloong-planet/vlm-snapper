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
- Cancellation order (corrected 2026-10-29 after the post-implementation check, finding 1): the first
  version of the clock double delivered cancellation through a separate task, so a superseded deadline
  could in principle be fired before its cancellation arrived. The double now handles cancellation
  synchronously: `Task.cancel()` on a sleeping timer removes and resumes its pending sleep before
  `receivedActivity` arms the replacement, so the passing path depends neither on task order nor on time.
  Remaining real-time parts: a 10 s guard per wait (passing path fails only past a 10 s stall) and a 50 ms
  window after firing (failing path only). Evidence on the new double: plain 5/5, with 300 ms pauses 5/5
  (`ticket-26-logs/sync-clock-plain.log`, `sync-clock-with-300ms-pauses.log`).

## Runnability

The manual clock ends a sleep only when fired or cancelled, and handles cancellation synchronously;
cancellation before suspension is recorded and honoured. A fired deadline that was superseded is no longer pending, so firing it is a no-op. The
10-second guard bounds waiting for a re-armed deadline. A 50 ms real pause after firing lets a still-live
deadline reach the stream before the text; it matters only when the behaviour is broken. No finding.

## Security

Test-only change. No finding.

## Consistency

Same seam as the neighbouring timeout tests (`ProviderTimeoutClock` injection); assertions unchanged plus
one on the armed deadlines. Product mutations, repeated on the synchronous double
(`ticket-26-logs/mutations-sync-clock.log`; the first double's run in `mutations.log`): old deadline not
cancelled → red at the stream (`:106`, `firstTextTimeout`); reasoning not re-arming → red at the
armed-deadline count (`:132`). Sources restored. Refactoring list: none.
