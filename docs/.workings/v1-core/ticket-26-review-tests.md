# Ticket 26 — test review

Ticket: [26 — Make the DeepSeek reasoning timeout test deterministic](issues/26-deterministic-reasoning-timeout-test.md).

## Design review (2026-10-28)

Implementation base: `8c00b2d` (`origin/main`). Scope: the one rewritten test in
`Tests/VLMSnapperCoreTests/ProviderAdapterExecutorTests.swift`.

### Test design table

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| T1 | v1-core §6 (reasoning refreshes the first-text deadline), Seam 2 | `ProviderAdapterExecutor.stream` with injected transport and timeout clock (existing seam: other tests here inject `ProviderTimeoutClock`) | DeepSeek stream: reasoning, reasoning, text, `[DONE]`; after each reasoning event the transport waits until the clock has armed a new first-text deadline, then fires the deadline armed before that event | events = `sourceDelta("Hello")`, metadata `chat_reasoning`, `completed` (unchanged literals); a deadline that was not superseded fires and fails the stream with `.firstTextTimeout` | recorded DeepSeek chat-completions SSE shape (`reasoning_content`, then `content`), unchanged from the current test | none |

### Dimension 1: Coverage

Same behaviour as before (§6 reasoning refresh); the race on real time is removed. The manual clock
also drives the failure branch: if reasoning did not supersede the deadline, firing it ends the stream.

### Dimension 2: Case design

Public seam with the existing clock injection; no internal state read. The clock completes a sleep only
when the test fires it and ends it on cancellation, as the real clock does.

### Dimension 3: False greens (design-time checks)

The test turns red when a deadline survives a reasoning event (to be shown with a temporary mutation of
the coordinator). A guard bounds the wait for a new deadline so a missing re-arm fails instead of
hanging. Expected events are literals.

### Dimension 4: Resource reuse

No expensive resource.

### Findings

None.

## Post-implementation check (2026-10-29)

Ticket: v1-core ticket 26 (linked above). First round, no incremental range.
Implementation checked: `8c00b2d..2903f68`; the test file at `2903f68` is blob `bade3e4`, identical in the
working tree. `2138d9b` and `7997e66` (HEAD at check time) change only `docs/.workings/`
(`git diff --stat 2903f68 HEAD -- Tests Sources Package.swift` is empty). Scope: the rewritten test
`deepSeekReasoningKeepsFirstTextDeadlineAlive` and its doubles `DeepSeekReasoningStreamingTransport` and
`ManualTimeoutClock` in `Tests/VLMSnapperCoreTests/ProviderAdapterExecutorTests.swift` (line numbers below
refer to that file unless another file is named).

Sources read in full: ticket 26; spec v1-core §6 (timeouts bullet), Failure Modes 9, Seam 2; the design
review above; `ticket-26-review-code.md`; `ticket-26-doc-sync.md`; all seven files in `ticket-26-logs/`;
the test file; `Sources/VLMSnapperCore/ProviderStreamTimeout.swift` and `ProviderAdapterExecutor.swift`;
ticket 17 and its section in `review-tests.md` (:733–760); `docs/agents/docs-layout.md` and
`issue-tracker.md`; `AGENTS.md`. Hidden and ignored files: `ls -la docs/.workings/v1-core` and
`git status --porcelain --ignored --untracked-files=all -- docs Tests CONTEXT.md AGENTS.md CLAUDE.md README.md`
list none. References to the test or ticket
(`grep -rn -I -l -e deepSeekReasoningKeepsFirstTextDeadlineAlive -e ticket-26 -e 26-deterministic -e ManualTimeoutClock --exclude-dir=.build --exclude-dir=.git .`):
the test file, tickets 17 and 26, `review-tests.md`, `ticket-26-review-code.md`, `ticket-26-doc-sync.md` and
this record. Not checked, with reason: `docs/features/`, ADRs and `CONTEXT.md`, because the change is
test-only and no finding below changes a product statement; `checklist.md` and `final-regression.md`, because
their ticket 17 rows were already judged in `ticket-26-doc-sync.md` and only finding 4 could affect them.

### Run evidence

Pre-review run log `ticket-26-logs/gate-full.log`, checked against the gate's log requirements:

- Version: `git rev-parse HEAD` is `2903f68…`, the end of the handed-over range. The version list holds only
  the stray untracked `:-` (`208ccf6…`, same hash today, a file from 2026-09-01). Of the files present, only
  the log itself was written by the run.
- Command: one, `bash Scripts/test-local-regression.sh --offline`, recorded with its PATH prefix as the
  placeholder `<scratch rg shim>`. The prefix only decides which `rg` runs the two `rg -F` checks at
  `Scripts/test-local-regression.sh:53,55`. Their output (log :27–29, :32–34) matches the appended
  native-paste and native-closed logs (:197–201, :172–176). The reviewed test's result comes from the
  non-app stage, which does not use `rg`. No conclusion here depends on the elided path.
- Exit code: `== exit: 0`, and the recorded command line has no pipe.
- Output: script stdout plus all nine stage logs. On 2026-10-29 each appended section was byte-identical
  (`cmp`) to the stage log still in `/var/folders/…/vlmsnapper-full-regression.GIauFZ/`.
- The reviewed test in this run starts at :494 and reports `✔ … passed after 0.247 seconds` at :1196, inside
  `Test run with 363 tests in 77 suites passed` (:1363).

Conclusion: the log meets the requirements and is this round's run evidence.

Own measurements cover only the rewritten test. Setup: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
`swift build --build-tests` (exit 0), then
`swift test --skip-build --filter deepSeekReasoningKeepsFirstTextDeadlineAlive` at HEAD `7997e66`:

- Plain, 5 runs: all passed in 0.114–0.119 s, each reporting `Test run with 1 test in 1 suite`.
- Under `bash docs/.workings/v1-core/ticket-26-logs/stall.sh <filter> <log>`, 5 runs: all passed in 0.111,
  0.402, 0.418, 0.117 and 0.416 s. Only the three runs near 0.4 s were paused while the test ran.

The raw output is in the session scratchpad (`rt26/plain-*.log`, `rt26/stall-*.log`), which is not durable.
The lines above are the needed excerpt.

### Written test vs the test design table

| Column | Table (T1) | Written test | Match |
|---|---|---|---|
| Seam | `ProviderAdapterExecutor.stream` with injected transport and `ProviderTimeoutClock` | :109–113 | yes |
| Driving input | after each reasoning event, wait for the re-armed first-text deadline, then fire the deadline armed before that event | Before the first event, also waits for the request-start deadline (:296). Fires the snapshot of all earlier first-text deadlines (:298, :303). Then pauses 50 ms of real time (:305) so that a still-live deadline reaches the stream before the text. | partly (finding 2) |
| Assertion and expected-value source | event literals; a deadline that was not superseded fails the stream with `.firstTextTimeout` | Event literals unchanged (:126–130). The stream failure surfaces as the error thrown by the loop at :116. Adds `armIDs(of: .firstText).count == 3` (:132), which is not in the table. | no (finding 2) |
| Fixture shape | recorded DeepSeek SSE shape, unchanged | Payload bytes unchanged. Only the reasoning text is now interpolated (:300). | yes |
| Expensive resources | none | none | yes |

The design review's dimension 3 says "a guard bounds the wait … so a missing re-arm fails". In the written
test the guard (:380–388) gives up silently after 5 s, and the failure comes from :132. The outcome matches,
but the table does not describe the mechanism (finding 2).

### Dimension 1: Coverage

The test file has no header gap note. As written, no untestable path in this test's scope needs one. Whether
one is needed later depends on how findings 1 and 4 are handled. The fixture is unchanged from ticket 17,
whose review established its provenance. Coverage outside the rewritten assertions: finding 4 (pre-existing).

### Dimension 2: Case design

The test goes through the public seam and reads no internal state. `armIDs` is the double's own record of the
calls the product makes through the injected clock. Instances are created per test and nothing is shared.
The design review says the clock "ends it on cancellation, as the real clock does". That does not hold:
`ManualTimeoutClock` delivers cancellation through an unstructured task (:371–373), so the sleep ends later,
with no ordering against `fire` (finding 1). No pattern that masks a defect was found.

### Dimension 3: False greens

Mutation testing was not run because `mutation-testing` is unconfirmed (finding 3). The "when does it go red"
question is answered from the code instead. In this table, "timeout" refers to
`Sources/VLMSnapperCore/ProviderStreamTimeout.swift` and "executor" to `ProviderAdapterExecutor.swift`.

| Broken behaviour | Mechanism | Red at | Deterministic |
|---|---|---|---|
| Reasoning does not cancel the earlier first-text deadline (timeout :74) | `fire(before)` resumes the live sleep, which calls `timeout(.firstText)` and then `fail(.firstTextTimeout)` (timeout :103–114) | error thrown at :116 (Swift Testing reports :106) | Only if the timeout reaches the coordinator before `complete()`. The two 50 ms real-time pauses (:305) are that window. Inferred: whole-process stalls do not defeat it, because the resumed timer job is queued before the producer wakes. Not shown under scheduling reorders within the process. |
| Reasoning cancels but does not re-arm, or re-arms as `.stalled` (timeout :75–79) | `waitForNewArm` gives up after 5 s per event | :132 (count 1) | yes (about 10 s) |
| No first-text deadline at request start | the initial wait gives up after 5 s | :132 (count 2) | yes |
| The decoder stops flagging non-empty reasoning (executor :168) | no cancel and no re-arm | :116 and :132 | as in the first two rows |
| Reasoning surfaces as a public event, or the event order changes | n/a | :126 | yes |
| Activity restarts the total deadline, or durations differ from 10, 10 and 90 s | the double never fires `.total` and ignores `duration` | never | n/a (finding 4) |

Corroboration: `ticket-26-logs/mutations.log` shows red at :106 (`firstTextTimeout`) and at :132 for runs
labelled `old-deadline-kept` and `no-rearm`. It records neither the mutation diffs nor the build, so it can
only corroborate the analysis above, not stand on its own.

False-green patterns:

- Tautology: none. The expected values are literals. The value 3 comes from spec §6: one first-text
  deadline at request start, plus one for each non-empty reasoning event before text, still first-text
  because text has not started.
- Always-true assertion: none.
- Stale path: none. The executor is the production path (`VLMSnapperApplicationModel.swift:179`,
  `ProviderPreparedOperationStreamer.swift:9`).
- Conditional skip: none. The 5 s give-up is silent, but the count assertion follows it.
- Assertion that may not run: none. The `#expect`s are awaited at top level after the loop, and the loop
  throws on stream failure.

This change also introduces a command-line check, `stall.sh`, used as evidence for acceptance 1. It was
checked against review-code `false-greens.md`:

- It has gone red: the old test failed 5 of 5 runs at :106.
- Its exit code comes from `wait` without a pipe.
- Whether a pause hit the test shows only in the run time. In the committed fixed-test log, 4 of 5 runs took
  about 0.4 s and one took 0.114 s; in mine, 3 of 5 were paused. So the "5/5 under pauses" wording counts one
  run that was never paused. That does not change the conclusion that the test survives stalls of the whole
  process.
- SIGSTOP pauses every thread together, so `stall.sh` cannot reorder tasks inside the process. It therefore
  cannot reveal the dependency in finding 1 (pattern 3: the command cannot tell whether the claimed property
  holds).

### Dimension 4: Resource reuse

The design table lists no expensive resource. The written test creates only in-memory doubles per test and
loads or builds nothing per test (the test bundle build is shared by the whole run). The gate log has
nothing to count. No test clears a process-shared resource, so the collection-order rule does not apply.

### Document sync

The findings below add sync items. The main agent must add them to `ticket-26-doc-sync.md`:

- Findings 1 and 2: this record's T1 row and dimension 2 text, the test comments, and
  `ticket-26-review-code.md` (statements listed in finding 1). Pending.
- Finding 3: `capabilities.toml` through `/repo-scaffold`, by user decision.
- Finding 4: user decision. If it becomes a ticket, add a pointer in ticket 17's Comments.

### Findings

1. **`ManualTimeoutClock` handles cancellation asynchronously, so "host load cannot end the stream" claims
   more than the evidence shows.** Category: untrue record or evidence.
   - Facts, confirmed from the code:
     - `receivedActivity` cancels the old timer task and starts the new one in a separate task
       (`ProviderStreamTimeout.swift:74–79`).
     - The double's cancellation handler does not remove the pending sleep. It spawns
       `Task { await self.cancel(id) }` (:371–373).
     - The producer fires the snapshot as soon as it sees the new deadline armed (:302–303).
     - Nothing orders that cancel task before `fire`. If `fire` runs first, the superseded sleep returns
       normally, and the timer calls `timeout(.firstText)` unconditionally
       (`ProviderStreamTimeout.swift:103–104`). The stream then fails with `.firstTextTimeout` even though the
       product code is correct.
   - Not reproduced: 10 runs, 5 of them under `stall.sh`. `stall.sh` cannot provoke it, because SIGSTOP stops
     the whole process.
   - Likelihood, inferred as low: the cancel task normally reaches the clock actor first. It loses only if its
     thread stalls inside the process until both the re-arm and the producer's next poll have run. This is the
     same kind of host-load false red the ticket set out to remove. The code review already treats task order
     as unguaranteed for arms (`ticket-26-review-code.md:14–15`), but not for cancellation.
   - Statements that go beyond the evidence:
     - test :108 ("so host load cannot end the stream"), :284 ("superseded ones are already cancelled") and
       :390 ("cancelled ones are no longer pending");
     - the design review's dimension 2 ("as the real clock does");
     - `ticket-26-review-code.md:16–17` and :22;
     - ticket 26 acceptance 1, which is evidenced only for stalls of the whole process. Commit `2903f68` also
       calls the test deterministic. The commit cannot be changed, but the PR description should not repeat
       the claim.
   - Required handling: bring the statements in line with the evidence. Because acceptance 1 is the purpose of
     the ticket, the recommended alternative is to remove the dependency inside the test double, which is
     within the ticket's scope. Two options:
     - Make `ManualTimeoutClock` a lock-guarded class whose `onCancel` removes and resumes the continuation
       synchronously. The superseded sleep is then gone before `receivedActivity` returns.
     - Before firing, wait (bounded) until every superseded id has left `pending`.

     Either option keeps the "deadline not cancelled" break red. Afterwards, re-review the T1 row under the
     design review's increment rule and rerun the test.
2. **Test design table row T1 does not describe the written test.** Category: untrue record.
   - Missing from the row:
     - the assertion `armIDs(of: .firstText).count == 3` (:132), with its expected-value source (spec §6, see
       dimension 3);
     - in the driving input: the initial wait for the request-start deadline (:296), firing the snapshot of
       all earlier first-text deadlines (:298, :303), and the 50 ms real-time pause after each fire (:305),
       which the red path depends on.
   - Dimension 3's "a missing re-arm fails" is achieved by :132 after the guard gives up silently
     (:380–388), not by the guard itself.
   - Required handling: update T1 and re-review the row under the design review's rules, including the 50 ms
     window as the red path's remaining dependence on real time. If the double changes under finding 1, do
     both together.
3. **项目无能力声明文件：未确认 `mutation-testing`.** Category: global capability rule.
   - `capabilities.toml` is absent at the repository root, checked directly, and
     `git log --all -- capabilities.toml` is empty. Mutation testing was therefore not done this round. The
     registry's recommended answer is `[mutation-testing] enabled = false` (the default).
   - Also unconfirmed and relevant to this ticket's flow:
     - `working-language`: this record follows the English names of the existing section; the recommended
       answer is `"en"`.
     - `lint` and `e2e-suite`: the gate chooses its commands by them, and the gate log records no decision;
       the recommended answer is `enabled = false`.
   - `AGENTS.md` keeps an i18n declaration under "项目能力". The global rule forbids putting declarations in
     a rules file.
   - Required handling: ask the user, or run `/repo-scaffold`. If `mutation-testing` turns out to be enabled,
     run mutation testing on this test as an increment of this check. If it is declared disabled, the
     dimension 3 answer above stands, and this record should state that the step was skipped for that reason.
4. **Pre-existing: §6 timer invariants outside this test's assertions are not driven by any test.** Category:
   missed regression; this change did not introduce it.
   - No test fails if activity restarts the total deadline (spec §6: "单次请求总超时为 90 秒" and
     "只刷新当前无活动计时"), or if the 10, 10 and 90 s defaults change (`ProviderStreamTimeout.swift:15–17`).
     - Searches: `grep -rn -e 'ProviderStreamTimeouts(' -e 'ProviderTimeoutClock' -e 'total_timeout' Tests Scripts`
       and `grep -rn -e 'seconds(90)' -e 'seconds(10)' -e 'firstText:' -e 'stalled:' -e 'timeouts' Tests`
       find no such assertion.
     - `totalDeadlineTerminatesOperation` runs without any activity.
     - Ticket 17's review (`review-tests.md:742`) cites the existing timeout cases for "total timer
       未被活动路径取消", but none of them drives activity.
   - Impact: a change to `receivedActivity` or to the defaults that lets a long stream run past 90 s, or that
     changes a timeout, would pass all tests.
   - Recommended: a separate small local ticket, because ticket 26 is scoped to determinism with its
     assertions unchanged. The manual clock already receives `kind` and `duration`, so the test is cheap.
   - Destination: no durable home yet; the user decides whether it becomes a ticket or is dropped. Ticket 17's
     review line is an original record and is not rewritten.

## Handling of post-implementation findings 1–4 (2026-10-29)

Read in full from the Findings subsection above; hand-back titles match the record.

- Finding 1: the clock double cancels synchronously (lock-guarded class; the cancellation handler removes
  and resumes the pending sleep itself), so a superseded deadline is gone before `receivedActivity`
  re-arms and firing it cannot end a correct stream. Statements corrected below and in the test and the
  code review record.
- Finding 2: row T1 rewritten (increment below).
- Finding 3: `capabilities.toml` is deferred by the user's decision of 2026-10-28 to a separate PR; until
  then mutation testing under the skill is not declared. Manual product mutations were run and kept
  (`ticket-26-logs/mutations.log`, repeated for the fix below); this record does not present them as the
  skill's mutation check.
- Finding 4: pre-existing gap outside this ticket; raised with the user for a decision (ticket or drop).

### Increment: row T1 rewritten

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| T1 | v1-core §6 (reasoning refreshes the first-text deadline), Seam 2 | `ProviderAdapterExecutor.stream` with injected transport and timeout clock | DeepSeek stream: wait for the request-start first-text deadline; for each of two reasoning events: snapshot the first-text deadlines armed so far, yield the event, wait (bounded, 10 s) for a newly armed one, fire the snapshot, pause 50 ms real time; then text and `[DONE]` | events = `sourceDelta("Hello")`, metadata `chat_reasoning`, `completed` (literals); three first-text deadlines armed — request start plus one per reasoning event (spec §6: reasoning refreshes the deadline); a deadline that survived a reasoning event fails the stream with `.firstTextTimeout` | recorded DeepSeek chat-completions SSE shape, unchanged | none |

Review: Dimension 1 — unchanged coverage; the armed-deadline count drives the re-arm. Dimension 2 — public
seam; the double's cancellation is synchronous, so the passing path no longer depends on task order or
time; the remaining real-time parts are the 10 s guard (passing path: only a stall longer than 10 s per
wait) and the 50 ms window (failing path only: lets a fired live deadline reach the stream before the
text). Dimension 3 — both product mutations to be rerun on the new double. Dimension 4 — none.
Findings: none.

### Self-check of the findings fix

Item 1: no product code changed. Item 2: the strengthened double turns both product mutations red at the
intended assertions (`ticket-26-logs/mutations-sync-clock.log`); the count assertion is red when reasoning
does not re-arm. Item 3: no product function changed; the double's branches — cancelled before
suspension, cancelled while pending, fired, fired after cancellation — are driven by this test's passing
run (cancellation of superseded and final timers) and by the old-deadline mutation (fired while pending).
Item 4: fixture unchanged. Item 5: the double is private to this test file
(`grep -rn ManualTimeoutClock Tests Sources Scripts` → this file only). Findings: none.
