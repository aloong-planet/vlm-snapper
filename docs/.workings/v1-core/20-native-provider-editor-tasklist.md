# Ticket 20 implementation

Base: origin/main eba012f. New branch starts with no additional commits. Other tickets' draft worktree is untouched.

## Admission and seams

- Confirmed management-center prototype covers secure field, clear/reveal icons, separate validation, status and error hints. No layout, color, icon or new state shape is designed here. Pure input-policy hint wording reuses the existing hint line.
- Production seams: ManagementCenterWindowController with real AppKit editing; ProviderSetupSession and injected external credential/model boundaries. Dummy keys only.
- Local ticket source: original uncommitted Ticket 20. Ticket 21 reconciliation and Ticket 22 capture exclusivity remain excluded.

## Tasks

- [x] Read ticket, spec and ADR; create branch from latest main.
- [x] TDD: native paste and typing policy, selection and visibility preservation.
- [x] TDD: coherent draft, clear, reload, Return/click and duplicate submission.
- [x] TDD: immutable Provider/key identity, stale load and draft lifetime.
- [x] Reconcile Ticket 20 ownership and acceptance evidence.
- [x] Run strict build and full verification gates.
- [x] Step 5: review-code, record findings independently.
- [x] Step 6: review-tests and mutation validation, record findings independently.
- [x] Spec terminal check and archival.
- [x] features-catalog and scoped cross-document regression.
- [ ] Commit, push, open PR; stop before merge.

## 2026-09-06 admission conflict and experimental result

- The production-window regression `ProviderCredentialInteractionTests.pasteReplacesSelectionWithoutTrimming` is intentionally red on main: pasting ` new\t\r\n` over `old` preserves CRLF and places the caret at UTF-16 offset 7 instead of 5. Reproduction: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ProviderCredentialInteractionTests/pasteReplacesSelectionWithoutTrimming`; log `/private/tmp/ticket20-paste-red.log`, exit 1, two precise assertion failures.
- An experimental custom NSTextView returned by a secure cell crashes when AppKit configures secure text storage (`setBulletCharacter:` sent to ordinary NSConcreteTextStorage). The experiment and its production wiring were removed; the original secure field implementation is unchanged. Log `/private/tmp/ticket20-native-green.log` records failure, not green evidence.
- Apple's archived Working With the Field Editor guide describes NSSecureTextField's specialized editor and security behavior, including disabling copy/cut. We must not replace this with an ordinary text editor or private API.
- Pending user decision: spec User Story 1 forbids a field-specific paste bypass, while Ticket 20 requires per-paste normalization. Proposed clarification: permit a narrowly scoped standard Paste action adapter for the API Key field, preserving the system secure editor, selection replacement, and shared Command-V/Edit Paste route. No heuristic inference from text-change notifications or clipboard matching.
- Work is paused at this decision, not marked complete. No commit, push, PR or installed-app change has occurred. The only source-tree change is the intentionally failing regression test; local ticket/tasklist documents record the pending work.

User approved the narrow standard Paste action adapter on 2026-09-06. Implementation resumed; spec now records the exception. Preserve the native secure editor and route keyboard/menu Paste through the same action adapter. The previous direct `readSelection` probe identified the native baseline; acceptance now exercises the approved standard menu action boundary, not a replaced editor.

## 2026-09-06 verified checkpoint — not ticket completion

- Implemented native NSSecureTextField/NSTextField editing, selection-preserving visibility, standard Paste routing, and the single-trailing-newline policy. The system secure editor ignores the delegate/context-menu property paths tested here; the current adapter retargets existing Paste actions on the public menu-tracking notification. No keyboard/mouse monitor or replacement secure editor was added.
- Added a shared local safety boundary (empty, remaining newline, or over 4096 UTF-8 bytes). UI refuses Validate and Return; the coordinator checks before any store mutation. The production-window regression was red with two submissions for each invalid input; the coordinator regression was red with the previous credential replaced. Both are now green.
- Return must be tested with a Return event through AppKit's key interpreter. Directly calling `insertNewline` bypassed the command delegate and was not equivalent. Ordinary-field fallback is checked at the native responder boundary (one Paste action and unchanged clipboard payload); it is not presented as a standalone NSTextView rendering test.
- Strict build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror`, exit 0, log `/private/tmp/ticket20-strict-final.log`.
- Full suite after the final source correction: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, exit 0, **280 tests / 71 suites**, log `/private/tmp/ticket20-full-final-2.log`. This is regression evidence, not proof that all Ticket 20 requirements exist.
- Production-window rendering was read from this run's `/private/tmp/vlmsnapper-credential-empty.png`: input is left-aligned and vertically within the field, with no simultaneous placeholder. The snapshot is an inactive test window; it does not accept final active-window colors or complete visual parity.
- Native context-menu smoke produced one explicit PASS (`/private/tmp/ticket20-appkit-smoke.log`), but later launches could not reliably acquire the actual key window. SwiftPM popup tracking also terminated without a completed test report despite exit 0; that run is rejected, not green.
- The attempted context-menu mutation did not reach Paste: it failed at key-window acquisition. Its validity is **unproven**. The mutation was precisely reverted (`menuBeganTracking` again calls `routePaste`), then the strict/full checks above were rerun.
- A desktop automation app-selection call subsequently took about 97 minutes. That path was stopped; no further desktop automation acceptance is claimed. The separately created smoke App was terminated. No production app, real clipboard value, real Keychain credential, or installed VLMSnapper bundle was modified.
- Do not repeat the broad desktop automation call as an unbounded acceptance step. The next native smoke attempt needs a reliable, bounded activation/foreground environment and an explicit PASS marker; neither process exit 0 nor setup-only failure can substitute.
- Remaining ticket work: coherent baseline/dirty state and revert handling; loading/close/card-switch generations; immutable Provider/key capture and exactly-once submission; native context-menu repeatability/mutation; checklist ownership; formal review-code/review-tests; spec/features consistency and PR. Review skills were read for guidance, but their independent ticket gates have **not** been completed. Ticket 21/22 drafts in the old worktree remain untouched.

## 2026-09-06 bounded native acceptance follow-up

Scope requested by the user: first stabilize native interaction acceptance; do not install the app or broaden product changes. Continue this worktree without overwriting pending Ticket 20 changes. This follow-up changes only the runner and smoke-stage diagnostics; it introduces no product visual change, so no new prototype is required. Per-ticket code review and test review remain separate, pending the rest of the ticket.

- [x] Reproduce/check current native behavior with an external deadline. Existing harness passed 10 times in the current environment; the earlier focus failure did not reproduce. Do not claim the competing SwiftUI window was the proven root cause or remove it on that assumption.
- [x] Valid negative control: temporarily suppress credential insertion in the actual Paste router, rebuild, then run the smoke. It failed in 1.514 seconds at `context Paste did not normalize at the insertion boundary`, not activation. Restore only that changed line, rebuild, and repeat successfully. Evidence: `/private/tmp/ticket20-native-mutation.jsonl` and `/private/tmp/ticket20-native-restored.jsonl`.
- [x] Add `scripts/verify-native-provider-editor.py`: default invocation builds current source first; then runs 10 fresh native processes, each with a 20-second deadline. Both exit 0 and exactly one completion marker are mandatory. Failures and timeouts stop the batch. Explicit `--binary` is only for prebuilt artifacts/negative controls and bypasses the build deliberately.
- [x] Gate negative controls: `/usr/bin/true` exits 0 without the marker and is rejected with runner exit 1; running the native artifact with `--timeout 0.01` returns 124. Timeout kills/reaps the spawned test child, not the installed application.
- [x] Stage diagnostics report window creation, key-window acquisition, context-menu tracking and Paste invocation. No credential contents are logged. On timeout the runner retains captured stages.
- [x] Final native gate: 10/10 passes, 0.951–1.628 seconds per run; all four stages and the completion marker present. Evidence: `/private/tmp/ticket20-native-checkpoint-gate.jsonl`.
- [x] Existing `ProviderCredentialInteractionTests`, `ProviderAPIKeyFieldTests`, and `ApplicationMenuTests`: 10/10 repeated batches passed, each with 10 test declarations in 3 suites (including parameterized cases). Evidence: `/private/tmp/ticket20-native-interaction-repeat.log`.
- [x] Full suite after restoring production logic: exit 0, 280 tests / 71 suites, `/private/tmp/ticket20-native-full-tests.log`.
- [x] Scoped review-code and review-tests: see `20-native-acceptance-review.md`. These do not replace whole-ticket review or missing acceptance requirements.

Repeatable command (from this worktree):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 scripts/verify-native-provider-editor.py
```

Evidence boundary: native smoke uses the real AppKit event loop and real secure context menu, then invokes its action programmatically. Other tests drive native controls/key interpretation through public APIs. Neither is physical input automation nor installed-app/live-Keychain/network acceptance. Final visual parity, actual user mouse/keyboard acceptance and remaining Ticket 20 state lifecycle work are still pending. No CUA retry, installation, commit, push or PR was performed.

## 2026-09-06 submission identity and in-flight duplicate slice

- Ticket 19 status synchronized to completed/merged in this worktree and the original ticket draft; merge evidence is PR #23, `eba012fa929e34d0bc3e744eaa7ff2715b15d3e0`. Other original draft changes were preserved.
- Red: `pendingValidationSuppressesDuplicates` showed extra boundary requests while the first validation was suspended, including after an A/B/A card switch. Green: a per-Provider in-flight guard now suppresses duplicates and releases with `defer`; parameterized success/failure termination both allow a later new request. Logs: `/private/tmp/ticket20-duplicates-red.log`, `/private/tmp/ticket20-duplicates-green.log`.
- Red: `submittedValidationUsesExplicitProvider` showed wrong-Provider validation and model/phase contamination when dispatch occurred after a card switch. Green: the explicit Provider overload retains the submitted identity and updates presentation only for the matching Provider/generation. Logs: `/private/tmp/ticket20-identity-red.log`, `/private/tmp/ticket20-identity-green.log`.
- Both native Validate and Return callbacks now carry `(ProviderID, String)` from the displayed card; application dispatch does not reread mutable selection or key after scheduling. Native interaction tests assert the callback Provider and returned text rather than reading a mutable backing key as the result.
- This is a behavior-preserving UI wiring correction against the already-confirmed submission contract; no new visual state or geometry. The no-visible-change prototype exemption was declared; native symbol/theme anchors and existing localized strings were retained.
- Gates: 282 tests / 71 suites pass (`/private/tmp/ticket20-submission-full.log`); strict Swift/C build passes (`/private/tmp/ticket20-submission-strict.log`); rebuilt native menu gate passes 10/10 (`/private/tmp/ticket20-submission-native.jsonl`); `git diff --check` passes.
- Scope check: same-Provider in-flight suppression is not unchanged-key suppression and does not claim the cross-Provider/capture gate owned by Ticket 22. Same-key resubmission after completion, draft baseline/reversion, late Keychain reads and close/reopen remain open in Ticket 20/21 as assigned. Whole-ticket review-code, review-tests, checklist/spec/features reconciliation remain pending; these passing slices do not authorize a PR or install.

## 2026-09-06 complete editor lifecycle and review checkpoint

- Revert red: /private/tmp/ticket20-revert-red.log; green: ticket20-revert-green.log. Restoring the exact loaded value originally still dispatched a validation.
- Post-success duplicate red: ticket20-repeat-red.log; green: ticket20-repeat-green.log. A proposed Task-owned editor callback did not run within the synchronous native test; that setup failure was rejected, and production async dispatch remains at the application boundary after a synchronous immutable claim.
- A/B/A read red: ticket20-load-red.log; green: ticket20-load-green.log. Unique per-visit tokens replace provider-only admission.
- Pending card-switch red: ticket20-switch-red.log; green: ticket20-switch-green.log. Per-Provider jobs protect another card's draft.
- Pending rejoin red: ticket20-rejoin-red.log; green: ticket20-rejoin-green.log. Original-provider completion is independent of intervening card-generation changes, while newer reads remain invalidated.
- Closed terminal red: ticket20-terminal-red.log; green: ticket20-terminal-green.log. Submitted failures survive close/reopen; editing or removing discards them.
- Production window close callback is covered by windowCloseDiscardsDraft. Shorter-value visibility reload passed without product changes (ticket20-selection-review.log).
- Test-review correction: three new session cases now use the real configuration coordinator with external model/storage substitutes. Rebuild with duplicate guard removed failed precisely at pending phase in both cases (ticket20-coordinator-mutation.log); only that guard was restored.
- Final executable gates: strict build exit 0; 293 tests / 72 suites, 15.460 seconds; native menu 10/10, 0.893–1.477 seconds. Current logs use /private/tmp/ticket20-closeout-{strict.log,full.log,native.jsonl}.
- Full localization dictionaries compared: 248 unique keys each, sets identical. Checklist enumerated 58 requirements / 58 unique ownership rows with no missing or mismatched text.
- Whole-ticket code and test reviews are in their separate required files; they do not rely on the earlier runner-only review.
- Current native PNG inspected: text starts at the left, no duplicate placeholder, controls remain inside the card. Native click/Return tests certify activation; inactive-window snapshot colors do not establish active-window color parity.
- Prototype's old input script remains a visual demo, not the changed editing model. Scoped invalidation notice added to its Provider harness, preserving layout. Isolated Chrome rendered that notice at x=275.16,y=851.5,w=263.70,h=17 in a 1200×900 viewport; center hit-test true. Screenshot: /private/tmp/ticket20-prototype-notice.png. Shared Chrome MCP was occupied, not stopped or reconfigured.
- No installed-app, real-account validation, signed CRUD, merge or release was performed.
