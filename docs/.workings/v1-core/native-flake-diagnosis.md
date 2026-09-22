# Native test instability — diagnostic checkpoint, 2026-09-08

Scope: diagnose the historical Paste key-window deadline and capture-toolbar deadline, not change production behavior or relax test gates. Current source includes the accepted visual alignment and short English update title on `codex/align-confirmed-visuals` (base `0febbb4`).

## Observed historical failures

- `/private/tmp/visual-align-final-paste.log`: XCTest failed at the wait for `NSApp.keyWindow === management` (then line 81), before Paste dispatch. This is not evidence that paste normalization or validation failed.
- `/private/tmp/ticket23-capture-isolated-check.log`: capture test failed at its historical toolbar wait. The log contains a deadline location, not the selection/event/window state needed to identify why the toolbar was absent.

## Current reproduction attempts

All runs used the existing real native controls with isolated synthetic credentials, pixels, HTTP and persistence. No real API key, screen pixels, app configuration or installed binary was changed. Tests ran sequentially, not competing for desktop focus in parallel.

1. Ten separate-process runs of each current test:
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --skip-build --filter ProviderApplicationTestsNativeMenu.testNativeMainMenuPasteValidatesThroughRealKeyWindow`: 10/10 passed, XCTest durations 1.279–1.999 seconds.
   - Same command with `ProviderApplicationTests.nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive`: 10/10 passed, durations 1.356–2.077 seconds.
   - Logs: `/private/tmp/vlmsnapper-flake-baseline-<full-test-filter>-<1..10>.log`.
2. Three sequences of the whole App suite followed immediately by isolated Paste: all passed; every App run completed 11 tests. Logs: `/private/tmp/vlmsnapper-flake-sequence-<1..3>-<app|paste>.log`.
3. Full non-App → App → Paste sequence: 333 non-App tests, 11 App tests and one native Paste case passed. Logs: `/private/tmp/vlmsnapper-flake-full-sequence-<nonapp|app|paste>.log`.
4. Historical drag-delivery control: temporarily removed only `pumpNativeEvents(window)` between synthetic drag events, rebuilt, ran the capture case three times. All passed (1.456, 1.259, 1.317 seconds). Logs: `/private/tmp/vlmsnapper-flake-unpumped-<1..3>.log`. This does NOT establish event-loop servicing as the root cause; this environment did not reproduce that older failure either.
5. Restored the exact original helper and rebuilt/reran capture successfully: `/private/tmp/vlmsnapper-flake-restored.log`. Test-file SHA-256 before and after experiment: `9f9aa06401cb3da4280134009f8422fe84c038c87b98bb1e14dae58911ff5506`. The temporary `[DEBUG-flake-0908]` comment was removed. `git diff --check` passed.

## Conclusion and next evidence needed

The existing commands detect the reported deadlines, but a current high-rate reproduction has not been established. Diagnosis is still in reproduction, not a confirmed hypothesis or fix. Passing repeats do not close Ticket 23 stability. Prior installed-app manual acceptance remains valid and is not replaced by these tests.

The next useful change is narrow test-only failure diagnostics at the key-window and toolbar waits: record own-process activation/key/main-window identifiers, target visibility/readiness, event types delivered and observation timestamps, without field contents, clipboard text or screen capture. Correlate these with a failing run before choosing any production or fixture correction. Do not add sleeps, loosen deadlines, silently retry failed acceptance, or assert that event-loop starvation / external focus competition is the cause without a distinguishing failing experiment.

At the preceding checkpoint no test or production source change remained. No install, commit, push, PR or ticket closure.

## Test-only diagnostic follow-up

User authorized adding diagnostics at the two waits. `NativeWaitTrace` now buffers up to 64 distinct state transitions, with monotonic timestamps, own-process window identifiers/visibility/key eligibility/levels/content sizes, AppKit activation policy and external foreground PID only. It records drag event types before/after delivery and emits once on normal/error unwind. It never reads field values, window titles, clipboard contents, credentials or pixels. Production source, deadlines and event delivery are unchanged by this increment.

- Five separate rebuilt runs per case passed: Paste 5/5, 1.345–1.583 s; capture 5/5, 1.544–1.672 s. Logs: `/private/tmp/vlmsnapper-diag-<full-test-filter>-<1..5>.log`.
- A passing Paste trace observed foreground PID already equal to the test process while `NSApp.isActive` was false and key window absent; later the actual key-window condition became true. A passing capture trace observed mouse-up delivery before the toolbar became visible. These are intermediate observations, NOT explanations of the historical failures.
- Negative control 1: temporarily ordered management out inside the key-window poll. The rebuilt Paste test failed at that specific wait, and its trace showed the target invisible with no key window. **It also aborted subsequently**, so this is not a clean timeout-only control.
- Negative control 2: temporarily omitted mouse-up delivery. The rebuilt capture test failed at the toolbar wait; trace showed a visible overlay and invisible/zero-sized toolbar. This verifies diagnostic discrimination for an unfinished synthetic selection, not reproduction of the historical event failure.
- Fault logs: `/private/tmp/vlmsnapper-diag-fault-<full-test-filter>.log`. Both `[DEBUG-diag-check]` fault lines were then removed individually, preserving pre-existing changes.
- Restored/rebuilt runs passed: Paste 1.498 s; capture 1.614 s; closed-window completion 3.838 s; App suite 11 tests in 6.184 s. Each command exited 0. Logs: `/private/tmp/vlmsnapper-diag-restored-<full-test-filter>.log` and `/private/tmp/vlmsnapper-diag-restored-app-suite.log`. Zero-test framework footers are not the acceptance evidence; the named XCTest/Swift Testing completions are.

### Separate teardown-crash lead

The controlled Paste timeout process PID 54107 produced `~/Library/Logs/DiagnosticReports/xctest-2026-09-08-224438.ips`. The triggered thread reports `SIGABRT`, `___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED`, `swift::TaskLocal::StopLookupScope::~StopLookupScope()`, `swift_task_deinitOnExecutorMainActorBackDeploy`, and `GlobalShortcutCoordinator.__deallocating_deinit`, while releasing `VLMSnapperApplicationModel`. The same key frame sequence exists in this day's `xctest-2026-09-08-132209.ips` (PID 40633) and `xctest-2026-09-08-131328.ips` (PID 15650).

This establishes a recurring teardown crash signature, not the original key-window or toolbar timeout cause, nor proof of a Swift runtime defect. The scope evidenced is the XCTest host; installed-app exposure is unverified. Recommended next diagnostic step: independently reproduce/minimize teardown around the isolated main-actor deinitializer, then compare toolchain/runtime or lifetime controls one variable at a time. Keep this investigation under Ticket 23's existing native stability item; no product workaround is authorized or applied here.

### Scoped review and remaining limits

- 【① 底层前提】Passing repeats do not establish stability; the controlled faults establish the intended wait failure points only. No root-cause claim.
- 【② 可运行性】Both traces compile and emit on success and thrown failure; restored native cases and App suite passed. Buffer is bounded and contains strings, not retained windows. An abort before defer can lose the trace; the observed abort occurred after trace emission.
- 【③ 安全正确性】Only test-state metadata is recorded; no real key/text/pixels and no new external request. Snapshot work can perturb scheduling, so instrumented passes cannot rule out the uninstrumented timing defect.
- 【④ 一致性】No deadline, retry policy, event-pump behavior or production API changed. Earlier approved visual/OCR edits were preserved. Diagnostics remain explicitly temporary investigation support, to retire after a genuine reproduction and regression are established.
- 【测试维度 1：覆盖】Enumerated scope: Paste key-window wait and capture toolbar wait, two negative controls, three restored isolated native cases plus the App suite. Physical input, installed-app focus and the full historical failure distribution remain outside these probes.
- 【测试维度 2：设计】Existing public native routes/assertions remain; trace reads do not replace them. Negative controls are deliberately artificial, never product acceptance fixtures. Crash after the Paste deadline is separately recorded, not attributed to the wait assertion.
- 【测试维度 3：假通过】Both injected controls rebuilt and reached their intended failing wait; only the two injected lines were restored, and named positive completions were verified. No retry converts failures to acceptance. Historical instability remains unresolved.

Only test diagnostics and this evidence record remain from this increment; no install, commit, push, PR or ticket closure.

## Standalone teardown minimization — 2026-09-08

Environment verified live: macOS 26.0.1 (25A362), Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), arm64, Swift language mode 6. Default experiment deployment target: macOS 14.4. Temporary source/binaries/logs: `/private/tmp/vlmsnapper-deinit-probe.roR2x3/`. A retained, explicitly diagnostic copy of the minimal source is `debug/isolated-deinit/Minimal.swift`, outside all Package.swift targets.

### Reproduction and reduction

1. Compiled the unchanged production `Sources/VLMSnapperCore/GlobalShortcutCoordinator.swift` directly with a tiny driver and a fake backend that traps if registration is attempted. Creating/releasing the coordinator from a main-queue closure without TaskLocal passed. No UI, HTTP, credentials, Carbon backend or shortcut registration was involved.
2. Wrapped that release in a synchronous `@TaskLocal` value scope: the real coordinator aborted. Repeated baseline: 3/3 exits 134. Driver records `hasTask=false` with `withUnsafeCurrentTask` immediately before release. Logs: `real-BASELINE-<1..3>.log`.
3. Replaced the entire production class with a main-actor class containing only `isolated deinit {}`: 3/3 exits 134. The code explicitly drops the last strong reference and verifies the weak reference clears on successful variants. Logs: `minimal-<1..3>.log`.
4. LLDB confirmed the same distinctive frames as the original XCTest reports: invalid free → `TaskLocal::StopLookupScope::~StopLookupScope` → `swift_task_deinitOnExecutorImpl` → back-deployment thunk → isolated class deallocation. Full captured stack: `minimal-lldb-stack.log`. LLDB's own exit 0 is not a successful probe: its inferior stopped on SIGABRT; direct invocations exited 134.

One command previously run against the compiled minimal reproducer:

```sh
/private/tmp/vlmsnapper-deinit-probe.roR2x3/minimal
```

Observed output: `PROBE before release hasTask=false`, exit 134; no after-release marker. To rebuild the retained diagnostic from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -swift-version 6 -parse-as-library -target arm64-apple-macos14.4 -g \
  docs/.workings/v1-core/debug/isolated-deinit/Minimal.swift \
  -o /private/tmp/vlmsnapper-deinit-probe.roR2x3/minimal-retained
```

### Ranked predictions and single-variable controls

After reduction, three predictions were stated before running controls: (1) no-current-task plus task-local/isolated-deinit interaction should disappear inside a real Task; (2) if TaskLocal alone is responsible, ordinary deinit should still fail; (3) if this is only a low deployment-target thunk issue, targeting the current OS should avoid it.

| Variant | Direct process result | Interpretation |
| --- | --- | --- |
| Empty isolated deinit + synchronous TaskLocal, no current task | 3/3 abort, exit 134 | Minimal failing combination on this machine |
| Same, `-D IN_TASK` | 3/3 pass, exit 0, `hasTask=true`, weak ref cleared | Task context distinguishes the failure |
| Same baseline, `-D NO_LOCAL` | 3/3 pass, exit 0, `hasTask=false`, weak ref cleared | TaskLocal scope is load-bearing in this reproducer |
| Same baseline, `-D NONISOLATED` | 3/3 pass, exit 0, weak ref cleared | TaskLocal alone does not explain failure |
| Same baseline, target macOS 26.0 instead of 14.4 | 1/1 abort, exit 134 | Raising deployment target alone did not avoid it |
| Unchanged real coordinator, TaskLocal release inside real Task | 3/3 pass, exit 0, `hasTask=true` | Control maps back to the real type, not only the empty class |

Variant logs use `<variant>-<1..3>.log`, `target26.log`, and `real-IN_TASK-<1..3>.log` in the temporary probe directory. No auto-retries turn a failing execution into a pass.

### Root-cause boundary and external cross-check

The teardown crash is now reproducible without XCTest, AppKit, SwiftUI or application cleanup logic. It occurs in the runtime's isolated-deinitializer/task-local handling with no current Swift Task, matching the earlier crash stack. It is not evidence that the original key-window/toolbar deadline had this cause, nor that every production release hits it.

Swift's [issue 85663](https://github.com/swiftlang/swift/issues/85663) reports the same isolated-deinitializer invalid-free frames; [commit 29245e4](https://github.com/swiftlang/swift/commit/29245e4) corrects allocation of TaskLocal marker items when no task exists so allocation and freeing match. The independent local controls support this mechanism; we have NOT tested a runtime containing that patch, so an exact fixed macOS/Xcode version is not claimed.

### Next action and safety review

- Recommended next step under Ticket 23: test fixture-owned teardown that drains relevant autoreleased objects and completes their final release inside an actual main-actor Task, with deallocation evidence. Simply declaring the XCTest method `async` is insufficient evidence: the existing method already is async, and its crash was during later object release.
- Do not remove `isolated` from production cleanup as a blind fix. The coordinator calls a main-actor registration interface; the Carbon backend also has isolated cleanup. Full source-tree search found exactly these two explicit `isolated deinit` declarations. The empty-deinitializer reproduction proves cleanup bodies need not run for this fault; real Carbon registration/destruction was intentionally not exercised.
- Potential production impact: same-runtime code releasing either isolated type under the triggering context could be affected; an installed-app occurrence is unverified. Keep this distinct from the demonstrated XCTest crash. If a product compatibility workaround is needed, design/review explicit lifetime ownership and isolation guarantees separately rather than raising the OS minimum without approval.
- All experiments stayed in a temporary diagnostic directory; production source is unchanged. Original coordinator SHA-256 remains `3ffb9348874b6de3ffda3021dfcb2f6a6fa436c40bd3741280b40138a2d02caa`. No product fix, test gate change, installed-app update, commit or publication.

## User-approved test-owned lifetime correction

The scoped implementation changes only `ProviderApplicationTests` fixture teardown and CI verification. It keeps production `isolated deinit` and existing timeouts. The fixture snapshots its new windows before production stop, clears their first responder/hosting content inside an autorelease pool, and awaits weak release of a unique external shortcut-adapter lease. Both Model and Application fixture owners use this on success and error. A cancelled operation cannot cancel this bounded, awaited cleanup Task; cleanup failure retains both the operation and release errors.

### Experiments and rejected shortcuts

- Rebuilt original same-process native suite: Paste passed, then SIGABRT (`/private/tmp/vlmsnapper-lifetime-before.log`). Merely wrapping stop in an autorelease pool still aborted (`stop-pool.log`, `event-pool.log` with the same prefix).
- Enumerating windows after stop missed an error path. Capturing before stop and detaching hosting content corrected the tested ownership boundary; a blank NSView avoids nil-content layout-anchor warnings. Weak native-input checks were insufficient alone to establish real coordinator release, so the external-adapter lease observes that lifetime separately.
- Temporary real-coordinator deinit instrumentation observed `hasTask=true` for all three native cases after adding the release gate (`/private/tmp/vlmsnapper-lifetime-release-gate.log`). This instrumentation was removed, and production SHA remains unchanged.
- Removing content detachment appeared to pass while instrumented but aborted during the first uninstrumented repeat (`/private/tmp/vlmsnapper-lifetime-restored-1.log`; crash `xctest-2026-09-08-233922.ips`). That reduction was rejected. Earlier 10/10 native-only passes (`final-<1..10>.log`) preceded later cancellation changes and are not final-code acceptance.
- Strong-retention mutation of the weak lease produced the intended five-second deadline. Review additionally found that cleanup errors masked the original operation error. Aggregating them now yields `cleanup(operation: unexpectedOperation, release: deadline(...))`; a cancelled/paused-validation variant yields `cleanup(operation: CancellationError(), release: deadline(...))`. Evidence: `/private/tmp/vlmsnapper-lifetime-retention-errors.log`, `/private/tmp/vlmsnapper-lifetime-cancel-retention-fault.log`. Both temporary mutations were individually restored.

### Full-suite review exposed a second, test-only problem

The first final candidate passed ten native XCTest rounds but the broader App suite returned exit 0 without completing all tests: `/private/tmp/vlmsnapper-lifetime-app.log` stopped in the third case; `app-repeat.log` stopped in the second. **Neither is a passing suite.** A temporary `atexit` stack (`exit-trace.log`, same prefix) points to `swift_task_asyncMainDrainQueue` and `exit`, not application Quit.

Single-variable control removed only `pumpWindowActivationEvents()` from the new lifetime wait (which had introduced nested `RunLoop.current.run` into Swift Testing fixture cleanup). The App suite then completed all 11 tests (`no-runloop-app.log`). Final cleanup polls weak release inside an autorelease pool using the existing async `eventually`/Task.yield; it does not reenter RunLoop. This identifies the problematic new test interaction on this runtime, not a claim about every nested RunLoop or the historical focus deadline. Temporary exit-stack logging was removed before final repeats.

CI now checks a named App suite completion and a nonzero Swift Testing completion as well as command exit status. The same-process native step additionally requires the three XCTest methods to complete with zero failures. Archived incomplete logs fail the added completion checks; the forced-retention failure log fails the native completion check. These are tested counterexamples, not just an untested success-path grep.

Final verification results are tracked in `native-lifetime-tasklist.md`. The historical Paste key-window and capture-toolbar deadline causes remain unproven; full Ticket 23 stays open. No installed App, real credential, permission, signing identity, GitHub publication or release is changed.
