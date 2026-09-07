# Ticket 21 implementation

Base: `e955513`, PR #24 merged. Branch starts with no carried commits.

## Admission and seams

- Existing management-center prototype in the preserved menu-panel worktree covers recovery warning and read-only secure-storage error in the existing inline area. No geometry or icon redesign is intended.
- Use the public ProviderConfigurationCoordinator and ProviderSetupSession boundaries with injected storage/network faults; retain actual editor load identities from Ticket 20.
- i18n is enabled; both dictionaries and existing semantic presentation must stay aligned.
- Ticket 22 owns cross-workflow exclusion; do not import the old draft's activity gate.

## Tasks

- [x] Merge prerequisite, fetch main, create clean feature branch.
- [x] TDD: reconcile missing credentials, orphan credentials, interrupted replacement, storage failures and cancellation.
- [x] TDD: session read failure/reopen, recovery and validation lifetime; connect production startup and editor.
- [x] Verify strict build, full tests, native editor, localization parity and signed Universal Keychain gate.
- [x] Reconcile this ticket's checklist evidence.
- [x] Review code (separate gate; documented physical/browser limits).
- [x] Review tests (separate gate; documented physical/browser limits).
- [x] Spec terminal audit and features-catalog cross-regression.
- [ ] Commit, push, open PR; do not merge or install without authorization.

## Evidence

### User prototype acceptance — 2026-09-07

- The user explicitly replied “验收通过” to the scoped manual checklist for the management-center prototype's recovering and storage-read-error states: status/error visibility, disabled credential/model controls, hidden Validate action, and light/dark readability without clipping or abnormal layout shifts.
- This closes the user-side prototype preview gap recorded below. It is user-reported acceptance, not an agent browser run; Browser Use URL policy remains unchanged.
- This does not accept real Keychain recovery after reopening, installed-app interaction, physical Quit/crash behavior, or every Ticket 21 criterion. No commit, PR, merge or installation is authorized by this acceptance alone.

The checkpoints below retain their historical status. Current criterion acceptance is recorded in the delivery reconciliation; no legacy draft test result is accepted retroactively.

### Delivery reconciliation — 2026-09-07

- All nine ticket criteria and every Ticket 21 ownership row now map to current tests, source-flow review or the signed CRUD gate in `checklist.md`. Code/test reviews and the spec terminal audit remain valid because this continuation changed documentation only.
- Refreshed strict build passed. The default Command Line Tools test build then failed before execution (`no such module 'Testing'`); its exit guard stopped delivery. Both installed toolchains contain Testing, so bare `swift -e 'import Testing'` without test framework paths was not a valid absence check. The actual SwiftPM command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` passed 312 tests / 72 suites in 16.015 seconds. No system toolchain or product code was changed. Logs: `/private/tmp/ticket21-delivery-strict.log`, `/private/tmp/ticket21-delivery-full.log` (failed setup), `/private/tmp/ticket21-delivery-xcode-full.log` (passing run).
- The same exit-guarded rerun completed rebuilt native programmatic Paste 10/10 (0.956–3.369 seconds), shell syntax and diff checks; log `/private/tmp/ticket21-delivery-xcode-native.log`. Both dictionaries still contain 251 identical unique keys. The earlier final-source v4 signed Universal/profile/Keychain CRUD gate remains applicable; no source changed afterward.
- User prototype acceptance closes the preview gate. Installed-app physical interaction and Quit/crash are not claimed; Ticket 23 retains combined application acceptance. Ticket 22 still owns cross-workflow exclusion.
- Delivery target is a PR only. No merge, installation, notarization or release.

### 2026-09-06 checkpoint (not a completion claim)

- Deliberate red/green cases now cover orphan-key recovery, missing-key cleanup, fresh-list recovery after metadata publication failure, local storage classification, generic/Keychain read failures, old-key deletion failure and permission-restored cleanup, memory-candidate termination, and cancellation before a delayed Keychain response can start recovery.
- A retirement journal records the known previous generation before deletion. Recovery may delete that known retired generation, but fails closed for an unrelated generation; it never authenticates using the retired key. This is not rollback storage: the journal contains no secret.
- Production editor close/switch cancels its attached load task. Once recovery starts, that task detaches from the window but remains in the application's termination-owned task set. Submitted validation remains application-owned.
- Strict Swift/C warnings-as-errors build, full suite (304 tests / 72 suites, 16.808 seconds), and `git diff --check` passed at this checkpoint. Logs: `/private/tmp/ticket21-strict-checkpoint.log` and `/private/tmp/ticket21-full-checkpoint.log`.
- Rebuilt native editor smoke runner passed 10/10 fresh processes, 0.941–1.606 seconds, exit 0. Log: `/private/tmp/ticket21-native-checkpoint.log`. This is real AppKit menu tracking with programmatic Paste and fake credentials, not physical input or live Provider acceptance.
- Preliminary Universal build, Developer ID/profile verification and the random-service Data Protection Keychain CRUD smoke test passed. That bundle predates the final cancellation/retirement edits, so it does not satisfy the final-source signed gate. Logs: `/private/tmp/ticket21-universal-build.log`, `/private/tmp/ticket21-signing.log`, `/private/tmp/ticket21-keychain.log`.
- An attempted global reconciliation wait introduced a test deadlock when a card switch waited for validation while the test waited for the card switch before releasing its external response. The wait was removed, the exact owned test process was terminated, and the full suite above passed afterward. Do not reintroduce a blanket wait as a repair for read-generation races.

### Required decision and remaining work

- User approved the acceptance boundary: reject replacement before any Provider request unless the retirement record is durable. Old saved configuration remains eligible when submission was never accepted. The spec and ADR-0012 now record this boundary; no further decision is pending on it.
- Still reconcile rapid close/reopen while an uncancellable physical Keychain read is outstanding, recovery reattachment across A/B/A, and second-read failure identity. The passing editor identity tests alone do not accept the complete production composition.
- Still inspect startup task termination and final secret flows; render recovery/storage-error surfaces in both languages/appearances, align approved prototype coverage, run the final-source signed gate, and reconcile every Ticket 21 ownership row before formal reviews.
- Separate code review, test review, spec audit and features-catalog cross-regression have not run. No commit, push, PR, installation or release for Ticket 21.

### 2026-09-07 checkpoint

- Reopen sequencing initially produced a false green because the first test double automatically finished its AsyncStream on cancellation. Holding an uncancellable read continuation reproduced the real race; `reopenedLoadWaitsForCanceledRead` failed at premature completion, then passed after awaiting only the canceled load predecessor. Logs: `/private/tmp/ticket21-red-reopen-read-v2.log`, `/private/tmp/ticket21-green-reopen-read.log`.
- `lateReadFailureIsIgnored` reproduced stale error publication across close and A/B/A. The editor identity and session generation both gate publication now. `recoveryPublishesBusyState` also covers A/B/A and verifies one external recovery request through completion.
- Replaced the remembered-current fixture with actual public configuration and model selection for both Providers before replacing the noncurrent key. No fabricated current pointer is used in that test anymore.
- A generic credential-write failure was incorrectly classified as Provider unavailability. The actual coordinator/session test failed, then passed with sanitized credential-boundary errors. Logs: `/private/tmp/ticket21-red-write-classification.log`, `/private/tmp/ticket21-core-final-candidate.log`.
- Actual production rendering exposed an unusable Validate row during recovery and read failure, and a misleading read-error retry instruction. `storageReadOnlyActions` failed in both states and passed after hiding the row only for recovery/read-only storage failure; write failure still permits manual retry. Read-error wording now describes collapse/reopen. Logs: `/private/tmp/ticket21-red-recovery-actions.log`, `/private/tmp/ticket21-green-recovery-actions.log`.
- Strict/full/native gate before the final cancellation check passed: 309 tests / 72 suites; native runner 10/10, 0.912–1.626 seconds. Final-source Universal Developer ID/profile and Keychain CRUD also passed at that checkpoint. These artifacts are superseded by the v2 runs after the next correction.
- `cancellationBeforeReplacementAdmission` reproduced a Provider request being started after a delayed credential read returned to an already-canceled validation task. Added cancellation checks after that read and before model listing. Log: `/private/tmp/ticket21-red-admission-cancel.log`. Final v2 build/test/native/signing gates must finish after this correction.
- Both dictionaries have 251 unique identical keys; prototype inline JavaScript parses. Browser preview of the synchronized recovery/read-error prototype was explicitly denied by the browser URL security policy. No alternative browser, raw CDP, proxy or other workaround was attempted. Browser interaction remains unverified and requires user-side preview; native production renders are separate evidence, not a substitute for that blocked action.
- Formal code review, test review, checklist acceptance and final document cross-regression are still pending. This checkpoint does not mark Ticket 21 complete or authorize a merge/install.

### Final v2 verification checkpoint — 2026-09-07

- Final strict build, full tests, and rebuilt native runner completed as an exit-guarded command chain with exit 0. The full suite passed 310 tests in 72 suites, 17.215 seconds; native secure context-menu Paste passed 10/10 fresh processes, 0.919–1.497 seconds. Logs: `/private/tmp/ticket21-final-v2-strict.log`, `/private/tmp/ticket21-final-v2-full.log`, `/private/tmp/ticket21-final-v2-native.log`. These native runs use fake input and programmatic AppKit actions, not physical interaction or live Provider requests.
- Final v2 Universal build, Developer ID/profile verification, and Data Protection Keychain CRUD gate completed with exit 0. The signed gate reported `Data Protection Keychain CRUD verification passed.` Bundle: `/private/tmp/vlmsnapper-ticket21-signing-final-v2/VLMSnapper.app`. Logs: `/private/tmp/ticket21-final-v2-universal.log`, `/private/tmp/ticket21-final-v2-signing.log`, `/private/tmp/ticket21-final-v2-keychain.log`. This is a separate test bundle with a development feed, not an installed or notarized release.
- Visually inspected all eight final production renders: recovering and storage-read-error, each in English/Simplified Chinese and light/dark appearance. At the tested 920 × 620 content size, status and error text are visible without clipping; recovery/read error expose no Validate row. Read-error advice says to collapse and reopen. Render directory: `/private/var/folders/9h/52q4kxb115j2nglbz0kfpkh00000gn/T/vlmsnapper-ticket13-renders`. These are static production-view checks, not browser or installed-app interaction acceptance.
- Mirrored the approved admission/cancellation boundary into FM-28, FM-41 and this ticket's replacement criterion; this synchronizes requirement wording, not acceptance status.
- Prototype browser behavior is still blocked by the explicit URL security policy. User-side preview of the existing `recovering` and `storage-error` demo controls is needed. Formal reviews and complete requirement/document reconciliation remain pending; no acceptance checkboxes, commit, push, PR or installation are claimed by this checkpoint.

### Implementation continuation and verification limits — 2026-09-07

- The user approved continuing implementation. This is not evidence that the user exercised the prototype or installed-app recovery controls.
- Strengthened `failedDeletionCannotRecoverRetiredCredential` with an injected model-list boundary that records any unexpected request. Focused coordinator/session/editor tests passed: 54 tests in 3 suites, exit 0 (`/private/tmp/ticket21-review-focused.log`).
- The intended temporary production mutation to exercise that forbidden-request assertion was rejected by the safety reviewer before the patch or test ran, because the proposed request could expose a retired credential. No mutation was applied and no request was executed. Do not recreate the rejected action through another tool. Its sensitivity remains unverified; further mutation work requires specifically authorized isolated fake-credential testing with no real credential or network access.
- Corrected the editor comment to distinguish discarding its memory baseline from the coordinator's durable admission boundary. Added test-file warnings separating injected cancellation/static PNG generation from installed-app interaction and process-death acceptance.
- Replaced two nonexistent ticket test references with actual declarations and enumerated all Ticket 21 ownership rows in `checklist.md`. This inventory explicitly preserves the open validation gaps; it does not accept the ticket or start formal reviews.
- Qualified the spec's ordinary model-cache refresh rule with its existing startup/orphan-key recovery exception, consistent with FM-46. No new product behavior or UI direction was introduced by that documentation correction.
- The first final v3 strict build was blocked from writing the compiler module cache by the execution sandbox; the exit guard prevented tests from running. A normal-environment build/test rerun was then requested through the permission mechanism, without the rejected mutation or real API Keys. Its result must be recorded separately.
- That permitted final v3 rerun completed with exit 0: strict Swift/C warnings-as-errors build, 310 tests in 72 suites (17.600 seconds), and `git diff --check`. Logs: `/private/tmp/ticket21-final-v3-strict.log` and `/private/tmp/ticket21-final-v3-full.log`. This does not supersede the distinct signed v2 bundle, browser gap, mutation-sensitivity gap, or unfinished formal review gates. No commit, push, PR, merge or installation was performed.

### Authorized isolated mutation verification — 2026-09-07

- The user authorized continuing the specifically proposed fake-key, no-real-network mutation test. Only `failedDeletionCannotRecoverRetiredCredential` was selected. Its stores are in-memory actors populated with `old-key` and `new-key` literals; its restarted model lister is `RejectUnexpectedModelRequest`, which records a test issue and returns an empty list. No Apple credential store, shell/environment credential, or real HTTP model lister is involved.
- An outer macOS sandbox profile `(version 1) (allow default) (deny network*)` prohibited network operations. The first invocation failed before test execution because SwiftPM attempted a nested sandbox (`sandbox_apply: Operation not permitted`); this is not a red-test result. The permitted rerun disabled only SwiftPM's nested sandbox while retaining the outer network denial.
- Temporarily inserted a fixed, secret-free execution marker and a call to the injected model-list boundary before retired-credential deletion. The rebuilt test emitted the marker twice, independently demonstrating both parameterized branches reached the mutation. Both cases then failed at `ProviderConfigurationCoordinatorTests.swift:864` with `An unexpected Provider model request crossed a forbidden boundary`. Exit 1; log `/private/tmp/ticket21-isolated-retired-key-red-v2.log`. The zero-test XCTest wrapper is not the result: the subsequent Swift Testing run executed one test with two cases and recorded two issues.
- Removed exactly the two temporary lines with a patch, preserving all implementation changes. The SHA-256 of `ProviderConfiguration.swift` before and after was identical: `cb04db419697afd2dd5f37fd4df1da8033e41f5508ff2874f4ca179fc8a72691`.
- Rebuilt and reran the same selected test under the same network-denial sandbox: one test with two cases passed, exit 0 (`/private/tmp/ticket21-isolated-retired-key-green.log`). `git diff --check` passed. This closes the forbidden-request assertion's mutation-sensitivity gap; it introduces no permanent production behavior change.
- The prototype-browser and installed-app interaction gaps remain. This bounded mutation exercise does not replace formal code review, full test review, or feature cross-regression. No commit, push, PR, merge, installation, or release was performed.

### Current-source v4 correction and gates — 2026-09-07

- Continuing read-only review despite unavailable browser preview is safe; the previous blanket stop was broader than the missing gate. It does not authorize circumventing the URL policy or claiming prototype interaction.
- Production rendering confirmed that clearing a candidate after secure-storage write failure hid Validate. The view conflated an unchanged draft with read-only storage. Removed only that conflation and made presentation eligibility require a changed selected key. The existing approved empty form is restored; no new visual design, geometry, icon or color is introduced.
- `unchangedCredentialAfterFailure` failed at `canValidate == true` before the correction, then passed. Its seam is public presentation of a loaded unchanged key after refresh failure. The separate render test uses public edit/submit/failure/clear operations and exposes production wiring; its green PNG-generation result does not prove visibility. Before PNG: `/private/tmp/ticket21-cleared-failed-candidate-before.png`; after: the system temporary directory's `ticket21-cleared-failed-candidate.png`, visually inspected.
- First red invocation could not write compiler cache; this is an environment failure, not a red test. Actual red: `/private/tmp/ticket21-empty-candidate-red-v2.log`, exit 1. Green: `/private/tmp/ticket21-empty-candidate-green.log`, nine tests, exit 0.
- v4 strict/full/native exit-guarded chain passed: 312 tests / 72 suites, 15.447 seconds; native 10/10 in 0.858–1.325 seconds. Final-source Universal Developer ID/profile and random-service Data Protection Keychain CRUD passed. All logs use `/private/tmp/ticket21-final-v4-`.
- A same-fact documentation search found the prototype README's unconditional retirement timing. Corrected it and made the spec's state description include recovery/read error and the already-approved empty validation control. No installed-app update, commit, push, PR or release.
- Separate code/test review records and three-stage document regression are now appended. The remaining delivery gate is the unavailable prototype-browser check (plus explicitly separate installed-app/physical acceptance); no scope expansion or browser-policy workaround was used. The first localization parity command used Ruby's unavailable filter_map API and failed; rerunning with map/compact checked the same complete files successfully. It was not counted as a passing gate until rerun.
