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
does not re-arm. Item 3 (corrected after incremental finding 6): no product function changed. The double's
"cancelled while pending" branch runs in every passing run (superseded and final timers), and "fired while
pending" runs under the old-deadline mutation. Its "cancelled before suspension" branch is reached only
when a cancellation lands between arming and suspending, which no run forces or reports; its correctness
rests on reading the code (the handler records the id under the lock and the suspension resumes at once).
Item 4: fixture unchanged. Item 5: the double is private to this test file
(`grep -rn ManualTimeoutClock Tests Sources Scripts` → this file only). Findings: none.

## Post-implementation check, incremental round (2026-10-29)

Ticket: v1-core ticket 26 (linked at the top). This is an incremental round of the post-implementation check
above (first round, 2026-10-29). Fix under review: `7997e66..96f7e7f`. `685805f` (HEAD) only adds
`ticket-26-logs/change-scope-after-findings.txt`. The test file is blob `1555a21` at `96f7e7f`, at HEAD and in
the working tree; `git status` lists only the stray `:-`. Line numbers refer to
`Tests/VLMSnapperCoreTests/ProviderAdapterExecutorTests.swift` at that blob unless another file is named.
"timeout" means `Sources/VLMSnapperCore/ProviderStreamTimeout.swift` and "executor" means
`ProviderAdapterExecutor.swift`.

Sources read in full: ticket 26; the fix diff; the test file; timeout; executor; `Package.swift`;
`ticket-26-review-code.md`; `ticket-26-doc-sync.md`; this record; `targeted-sync-clock.log`;
`mutations-sync-clock.log`; `sync-clock-plain.log`; `sync-clock-with-300ms-pauses.log`;
`change-scope-after-findings.txt`; `mutations.log`; `stall.sh`; `docs/agents/docs-layout.md`; `AGENTS.md`;
`CODEX.md`. Read in part: spec v1-core §6, Failure Modes and Seam 2.

### Increment scope

- `git diff --name-only 7997e66 96f7e7f` lists the test file and seven files under `docs/.workings/v1-core/`
  (ticket 26, `ticket-26-review-code.md`, this record, and four logs). `git diff --name-only 96f7e7f 685805f`
  lists one log.
- Changed test code: the hunks at :108 and :132 (test `deepSeekReasoningKeepsFirstTextDeadlineAlive`),
  :282–305 (`DeepSeekReasoningStreamingTransport`) and :352–405 (`ManualTimeoutClock`).
- Tests that depend on the changed helpers:
  `grep -rn -e ManualTimeoutClock -e DeepSeekReasoningStreamingTransport Tests Sources Scripts Package.swift`
  finds only :109, :111, :286, :287 and :355 of this file, and both types are `private`.
  `grep -rln ProviderAdapterExecutorTests Tests Scripts` finds only this file. The only test in scope is
  therefore `deepSeekReasoningKeepsFirstTextDeadlineAlive`.
- Changed rows of the test design table: T1, rewritten under "Increment: row T1 rewritten".

The following conclusions are carried over from the first round of this check and were not re-checked: the
fixture's provenance (dimension 1), the assessment of `stall.sh` (dimension 3; the file is unchanged), and
the status of findings 3 and 4.

### Run evidence

This round checks the handed-over targeted log, `ticket-26-logs/targeted-sync-clock.log`, against the gate's
log requirements:

- Version: :1 gives HEAD `7997e66…` "+ working tree". :2–10 list the porcelain status: the test file, ticket 26,
  the code review record and this record as modified, plus `:-` and the four new logs as untracked. The
  modified and new files are exactly the files that `96f7e7f` changes. The log lacks two required items: the
  `git hash-object` output for each listed file, and the commands that took the version. As a result, it does
  not show which content of the test file ran (finding 5).
- Commands: three (`swift build -Xswiftc -warnings-as-errors …`, `swift build --build-tests`,
  `swift test --skip-build --skip ProviderApplicationTests`). Each ends with `== exit: 0`, and no recorded
  command line contains a pipe.
- Output: complete for each command. It contains no warning, no failure and no continuation message. The
  reviewed test starts at :721 and passes at :1194 (0.221 s), inside `Test run with 363 tests in 77 suites
  passed` (:1359).
- Product sources: the porcelain lists no file under `Sources/`, so the product mutations behind
  `mutations-sync-clock.log` had been reverted before this run.
- Corroboration only, not a substitute for the version list: the test file's mtime, 00:15:15, is earlier than
  the run (00:17:14), and the file's current content is blob `1555a21`.

Conclusion: the log shows a passing result but cannot tie it to `96f7e7f` (finding 5). As the skill requires,
nothing was rerun to fill that gap.

Supplementary logs, cited by ticket 26 acceptance 1 and by the code review record:

- `sync-clock-plain.log`, `sync-clock-with-300ms-pauses.log` and `mutations-sync-clock.log` record neither
  the version nor the command.
- `mutations-sync-clock.log` prints the new :132 expression (`clock.armIDs…` without `await`), so its runs
  were built from the new test.
- In `sync-clock-with-300ms-pauses.log`, runs 1 and 4 took 0.114 s and 0.127 s, the unpaused time. Only 3 of
  the 5 runs were paused.

None of this changes a conclusion below, because the passing path's independence from time follows from the
code (dimension 2).

No measurements were taken this round. The code answers dimension 3, mutation testing does not apply, and
the rules do not allow a rerun to fill finding 5's gap.

### Written test vs the test design table

| Column | Table (T1, rewritten) | Written test | Match |
|---|---|---|---|
| Seam | `ProviderAdapterExecutor.stream` with injected transport and timeout clock | :109–113 | yes |
| Driving input | wait for the request-start first-text deadline; per reasoning event: snapshot, yield, bounded 10 s wait for a new arm, fire the snapshot, 50 ms pause; then text and `[DONE]` | :296 (the initial wait uses the same 10 s guard, :395); :297–306; :307–311 | yes |
| Assertion and expected-value source | event literals; three first-text arms (spec §6); a surviving deadline fails the stream with `.firstTextTimeout` | :126–130; :132; thrown at :116 | yes |
| Fixture shape | recorded DeepSeek SSE shape, unchanged | payload bytes unchanged; reasoning text interpolated at :300, as in the first round | yes |
| Expensive resources | none | none | yes |

The test file has no header gap note, and none is needed. No path in this test's scope is untestable. The red
path for an old deadline that is kept is probabilistic, not untestable (dimension 3).

### Dimension 1: Coverage

The fix changes the double and the comments. It does not change the driving input or the assertions, so
coverage of spec §6 (reasoning refreshes the first-text deadline) and of Seam 2's timeout contract is as in
the first round. Failure Modes 9 (a timeout stops the call) is still driven on the red path through
`.firstTextTimeout`.

The claim "request start plus one per reasoning event" matches the inputs. :296–302 produce exactly those
arms, and nothing else arms `.firstText` before text (timeout :60–79; executor :47, :68–71). The pre-existing
gap is finding 4, carried over.

### Dimension 2: Case design

The test uses the public seam with clock injection. It reads only the double's record of the calls that the
product makes through the injected protocol. Instances are created per test, and nothing is shared.

The double now follows the real clock's cancellation contract:

- `Task.cancel()` runs the `onCancel` handler (:378–385) synchronously on the cancelling thread. If the task
  was cancelled before it registered the handler, the handler runs immediately on entry instead. In both
  cases, the sleep is either resumed with `CancellationError` or marked in `cancelledBeforeSuspending` (:381),
  and the operation then throws (:372, :376). It never becomes pending.
- `receivedActivity` cancels the old timer (timeout :74) before it creates the replacement (:75–79). The
  replacement's body runs only after that.
- The producer fires only after it has seen the replacement armed (:302–303). By then every superseded ID has
  left `pending` or will never enter it, so firing a superseded deadline is a no-op whatever the task order.
- The design review's dimension 2 sentence ("ends it on cancellation, as the real clock does") was
  contradicted by finding 1 and now holds.
- Locking: every access to the four mutable fields happens under `lock`. Continuations are resumed outside it
  (:376, :384, :404). `fire` and `onCancel` therefore cannot both resume one continuation, and nothing resumes
  while holding the lock.

No pattern that masks a defect was found.

### Dimension 3: False greens

Mutation testing: 项目无能力声明文件；未确认 `mutation-testing` (`capabilities.toml` is still absent at
the repository root, checked directly). Mutation testing was not run. This is finding 3, which is still open;
the handling section above records the user's deferral. The question "when does it go red" is answered from
the code:

| Broken behaviour | Mechanism | Red at | Deterministic |
|---|---|---|---|
| Reasoning does not cancel the earlier first-text deadline (timeout :74) | That deadline is still pending at `fire(before)` (:303), resumes, and its timer calls `timeout(.firstText)` and then `fail(.firstTextTimeout)` (timeout :103–104, :111–114) | thrown at :116 (reported at :106) | Only if the resumed timer reaches the coordinator before `complete()`. The window is the 50 ms pause (:305), twice, plus text processing; otherwise :132 still counts 3 and the test passes. Inferred, unchanged from the first round: whole-process stalls do not defeat it, because the resumed timer job is queued before the producer wakes. |
| Reasoning cancels but does not re-arm, or re-arms as `.stalled` (timeout :75–79) | `waitForNewArm` gives up after 10 s per event; `fire` is a no-op | :132 (count 1) | yes (about 20 s) |
| No first-text deadline at request start (timeout :60–65, executor :47) | The initial wait gives up after 10 s | :132 (count 2) | yes |
| The decoder stops flagging non-empty reasoning (executor :168) | No cancel and no re-arm; the request-start deadline is fired while still live | :116 if the timer wins the race, otherwise :132 (count 1) | yes, at one of the two |
| Reasoning is treated as text | It re-arms `.stalled` instead of `.firstText` | :132 (count 1) | yes |
| Reasoning surfaces as a public event, or the event order changes | n/a | :126 | yes |
| Activity restarts the total deadline, or the 10, 10 and 90 s durations change | The double never fires `.total` and ignores `duration` | never | n/a (finding 4, carried over) |

Corroboration: `mutations-sync-clock.log` shows red at :106 (`old-deadline-kept`) and at :132 (`no-rearm`).
It records neither the mutation diffs nor the version, so it corroborates only.

False-green patterns:

- Tautology: none. The expected values are literals, and 3 comes from spec §6.
- Always-true assertion: none.
- Stale path: none. The executor is the production path (first round).
- Conditional skip: none. The 10 s give-up is silent, but the count assertion follows it.
- Assertion that may not run: none. Both `#expect`s run at top level after the loop, and the loop throws on
  stream failure.

This round introduces no new command-line, UI or gate check.

### Dimension 4: Resource reuse

The test design table lists no expensive resource. The written test creates only in-memory doubles per test.
Counting from the targeted log: there is no per-test load or build output, and the build runs once per
command, before the tests run. No test clears a process-shared resource, so the collection-order rule does not
apply.

### Document sync

Scope, following `implement/document-sync.md`:

- Task inputs: ticket 26; spec v1-core §6, Failure Modes and Seam 2; this record; both handed-over logs.
- Working-record directory: `docs/.workings/v1-core/`, including the `ticket-26-*` files, all 12 files in
  `ticket-26-logs/`, `issues/26` and `issues/17`, plus the feature-level `review-tests.md`, `checklist.md`
  and `final-regression.md` as associated references.
- Root files: `AGENTS.md`, `CODEX.md` (only `@AGENTS.md`) and `CONTEXT.md`. `README.md`, `CLAUDE.md` and
  `capabilities.toml` were checked directly and are absent.
- Authoritative docs: `docs/features/`, `docs/adr/` and `docs/specs/`.
- Excluded: `docs/prototypes/`, because they hold UI prototypes and this change is test-only. Other
  `docs/.workings/<slug>/` directories are also excluded: there, only the original gate logs of
  `capture-instant-overlay` name the test, as output lines of earlier runs.
- Hidden and ignored files:
  `git status --porcelain --ignored --untracked-files=all -- docs Tests CONTEXT.md AGENTS.md CODEX.md CLAUDE.md README.md capabilities.toml`
  lists nothing, and `find docs -name '.*' -not -path docs/.workings` finds nothing.
- References:
  `grep -rn -I -l -e deepSeekReasoningKeepsFirstTextDeadlineAlive -e ManualTimeoutClock -e ticket-26 -e 26-deterministic -e "DeepSeek reasoning activity keeps" --exclude-dir=.build --exclude-dir=.git .`
  finds the test file, the `ticket-26-*` files and logs, tickets 17 and 26, `review-tests.md`, and three
  `capture-instant-overlay` gate logs.
  `grep -rn -I -i -E "reasoning|推理|首字|first.text|ManualTimeoutClock|timeout clock" docs/features docs/adr docs/postmortems docs/ops CONTEXT.md AGENTS.md CODEX.md`
  finds only product statements (features :47, ADR 0011 :23 and :42, CONTEXT :95).

Facts changed by the range: the clock double cancels synchronously, and the guard is now 10 s; the test
comments; ticket 26 acceptance 1; the code review record; this record (handling section, T1 increment,
self-check); the new logs. The handling section also leaves finding 4 awaiting a user decision.

Judgements:

- Ticket 26 acceptance 1 (:26) matches the code. On the passing path, the only dependence on time or task
  order is the 10 s guard; the failing path keeps the 50 ms window. The pause evidence is 3 paused runs (run
  evidence), and the code argument holds independently.
- `ticket-26-review-code.md` :16–23, :27–30 and :38–42 match the code. "with 300 ms pauses 5/5" counts 2 runs
  that were not paused; no conclusion depends on it.
- The test comments at :108, :282–285, :352–354, :392–393 and :401 are true. At :283, "every deadline armed
  before the event" means every first-text deadline (:298); the total deadline is never fired. No conclusion
  depends on this wording.
- This record:
  - The handling section and the T1 increment are true.
  - Self-check item 3 is not (finding 6).
  - The design review's original T1 row and the first round's "5 s" text describe the test as it was on
    their dates. They remain as original records.
- `ticket-26-doc-sync.md` has not changed since `7997e66` and lacks the sync items created by the first
  round's findings (finding 7).
- Ticket 17's Comments entry of 2026-10-28 ("ticket 26 drives its deadlines with a manual clock") is still
  true.
- The spec, features, ADR 0011 and `CONTEXT.md` are unchanged. They contain only product statements, and the
  change is test-only.
- The feature-level `review-tests.md`, `checklist.md` and `final-regression.md` contain no statement about
  the double (the `ManualTimeoutClock` search above), so they are unaffected.

### Findings

5. **The targeted verification log has no per-file version hashes, so it cannot show that the fix's test
   content was run.** Category: untrue record or evidence.
   - Missing per the gate's log requirements:
     - the `git hash-object` output for each file listed at :2–10 of `targeted-sync-clock.log`;
     - the commands that took the version.
   - Consequence: the passing result at :1194 is not tied to blob `1555a21` of `96f7e7f`. The listed file set
     and the test file's mtime (run evidence) only corroborate the tie.
   - Required handling: provide a targeted-run log for the reviewed version that meets the gate's log
     requirements, then point this round's run evidence to it. As the skill requires, this check did not rerun
     anything to fill the gap.
6. **Self-check item 3 claims that the passing run drives the double's "cancelled before suspension" branch,
   but nothing forces that branch and no output shows it.** Category: untrue record or evidence.
   - Facts:
     - The branch (:372 after :381) runs only when a cancellation lands between arming (:363–368) and the
       continuation's lock (:371), or before the handler is registered.
     - The passing run cancels five deadlines:
       - The request-start deadline: the producer sees its arm by 1 ms polling, and only then is the
         reasoning event decoded. It is normally already pending when cancelled.
       - The two re-armed first-text deadlines: each is cancelled by the next event, which the producer
         sends only after a 50 ms pause, so each is pending.
       - The total deadline: pending since the request started.
       - The stall deadline armed by the text event: it races with `complete()`. Inferred: `Package.swift`
         enables no upcoming features, so the nonisolated `sleep` runs off the coordinator, concurrently with
         `complete()`.
     - The branch is therefore reached only by timing, and the test output records no per-branch data.
   - Why it matters: this branch keeps a superseded deadline from becoming pending when a stall lands between
     arming and suspending, which is the case the fix exists for. A regression in the branch would show only
     as a rare false red, and passing runs cannot reveal it. Its correctness currently rests on reading the
     code (dimension 2), not on runs.
   - Required handling: bring item 3 in line with the evidence. It should say that the branch is reached only
     by timing and that its correctness is established by reading the code. This finding requires no test
     change.
7. **The ticket's document sync checklist lacks the sync items created by first-round findings 1, 2 and 4.**
   Category: untrue record (a document that the record-ownership rules require to be synchronized).
   - The first round's "Document sync" subsection asked for these items to be added to
     `ticket-26-doc-sync.md`. `git log -- docs/.workings/v1-core/ticket-26-doc-sync.md` shows only `7997e66`.
   - Missing rows:
     - The corrections under findings 1 and 2, done in `96f7e7f`: the test comments, ticket 26 acceptance 1,
       `ticket-26-review-code.md` and this record's T1 row. Status `已完成`, linking `96f7e7f`.
     - Finding 4's follow-up, a pointer in ticket 17's Comments if the user files a ticket. Status `待处理`,
       because its applicability waits on the user's decision.
   - Rule: `implement/document-sync.md` requires that sync items added by changes, review findings or status
     events go into the ticket's checklist.
   - Required handling: add the rows, with statuses set as `to-tickets/ticket-artifacts.md` specifies.

Carried over and not renumbered: finding 3 stays open (deferred by the user, per the handling section), and
finding 4 is awaiting the user's decision.
