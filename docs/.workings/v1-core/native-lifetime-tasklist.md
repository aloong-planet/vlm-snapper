# Native test lifetime correction

Scope: user-approved test-owned teardown under Ticket 23; no production isolation, product behavior, timeout or installed-app change. Continue the existing dirty feature branch to preserve the accepted visual changes; no new branch, commit or publication as part of this diagnostic increment.

Seams: existing application fixture startup/operation/stop boundaries and real native XCTest methods. Success requires named test completion AND process exit 0, plus observable release evidence; repeated passes alone do not prove final release context.

- [x] Baseline: rebuilt same-process `ProviderApplicationTestsNativeMenu`; Paste completed, then process aborted with signal 6. `/private/tmp/vlmsnapper-lifetime-before.log`.
- [x] Implement a bounded, test-owned lifetime correction, validate success and thrown-operation cleanup without retaining objects forever.
- [x] Repeated native suites, forced-failure cleanup and full regression; retain explicit exit codes.
- [x] Separate code-review pass: four layers, record findings in `review-code.md`. Main-agent self-review, not an independent reviewer.
- [x] Separate test-review pass: coverage/design/false-green audit, record findings in `review-tests.md`.
- [x] Document scope/results/remaining limits under Ticket 23. This is not full feature closeout.

## Final-code native regression

After removing temporary deinit/exit logging and all retention faults, ran ten alternating sequences, each with full `ProviderApplicationTests` (excluding NativeMenu), then all three `ProviderApplicationTestsNativeMenu` methods. Every command rebuilt if needed, required its completion report and exited 0; `set -e` stops on the first failed command or missing report. No retry hides an unsuccessful iteration.

- App: 10/10 complete, 11 tests per round, duration 5.826–6.324 seconds.
- Native XCTest: 10/10 complete, 3 methods per round, duration 5.841–6.351 seconds.
- Total: 140 test executions; the thrown-operation method additionally exercises both ordinary and cancelled exits each round.
- Logs: `/private/tmp/vlmsnapper-lifetime-terminal-app-<1..10>.log`, `/private/tmp/vlmsnapper-lifetime-terminal-native-<1..10>.log`.
- Earlier candidates and failures are retained in `native-flake-diagnosis.md`, including two App runs that returned 0 without completing. They are not passing regressions. CI now rejects those reports.
- Production `GlobalShortcutCoordinator.swift` SHA-256 is unchanged: `3ffb9348874b6de3ffda3021dfcb2f6a6fa436c40bd3741280b40138a2d02caa`.
- Final strict warnings-as-errors build and 333 non-App tests passed, exit 0. Logs: `/private/tmp/vlmsnapper-lifetime-terminal-strict.log`, `/private/tmp/vlmsnapper-lifetime-terminal-nonapp.log`.
- Six checklist parser tests, 58 requirement ownership rows, release-script syntax and `git diff --check` passed. CI changes were checked locally; no remote Actions run or release package build is claimed.

## Scope reconciliation

This is the user-approved stability subtask of Ticket 23, not a new product feature or the ticket's complete checklist discharge. No spec behavior changes, public interface, UI strings or installed-app changes. No feature sentence is made false and no new user-visible behavior needs cataloging by this increment; the full feature closeout remains required by Ticket 23. Per project capability declaration, RTL mirroring is not enabled and that check is skipped. Existing accepted visual work and historical wait diagnostics remain preserved. No commit, push, merge, tag or release.
