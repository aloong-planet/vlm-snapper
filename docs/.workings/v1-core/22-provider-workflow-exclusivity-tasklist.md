# Ticket 22 implementation

Base: `5999103679d208ac90543fa4ece46249801c679f` (merged PR #25).
Branch: `codex/ticket-22-provider-workflow-exclusivity`.
The branch was created after fetch with no commits ahead of origin/main.

## Scope and admission

- Implement the existing US-07 / FM-31, FM-43, FM-44 and FM-46 exclusion requirements. Ticket 21 owns credential reconciliation; Ticket 23 owns combined feature closeout.
- Reuse confirmed management-center read-only controls and recovery presentation, capture toolbar and result workspace. No new toolbar configuration state, geometry or icon choice. Any uncovered UI state must pass the prototype gate before implementation.
- i18n is enabled. Both dictionaries participate in any wording change and final parity checks.
- Preserve the Ticket 21 and menu-panel prototype worktrees; no installed-app update or release is included.

## Current-source findings

- `ProviderConfigurationCoordinator` has separate `configurationLocked` and `configurationMutationInProgress` flags. Its request freeze can reject configuration mutation but carries no owner token and does not represent capture/selection.
- `OperationWorkspaceSession` already exposes `OperationActivityGating`; its `ActiveOperationGate` owns model-operation leases only. Production constructs this separately from the Provider coordinator's request freeze.
- `VLMSnapperApplicationModel.capture()` and `rerunWorkspace()` are private application routes. The constructor directly creates Apple Keychain, official model listing, ScreenCaptureKit and user screenshot storage. The current test targets do not directly exercise this application composition.
- Therefore an isolated activity-lock test cannot redeem the ticket's shortcut/menu/Try Again routing criterion. A production-used, injectable application workflow boundary needs agreement before new tests; do not use private-state casts, a duplicate test-only router, or real user credentials to fill this gap.

## Proposed test boundaries

1. Existing `ProviderConfigurationCoordinator`: symmetric admission, ownership, recovery waiting/cancellation and storage mutation exclusion, using injected external stores/model listing.
2. Existing `ProviderSetupSession`, `ProviderCredentialEditor` and presentation: another Provider may edit a draft but not submit during active credential work; terminal availability comes from the retained draft.
3. A small production-used application workflow entry shared by shortcut/menu capture and result rerun: constructor-injected screen/window effects; the real coordinator and operation session/runner remain under test. Blocked capture cannot freeze/create a selection and targets the active Provider; blocked rerun cannot call the provider or change persisted history. This new boundary is awaiting user agreement under the TDD seam rule.

## Tasks

- [x] Fetch main, create a fresh branch/worktree, and record merged prerequisite.
- [x] Read ticket/spec/current code and identify the application-routing test gap.
- [x] Confirm the new production application-workflow test boundary (user confirmation, 2026-09-07).
- [x] TDD: symmetric owner-token activity admission and terminal release.
- [x] TDD: event-driven recovery wait with cancellation and no premature storage/model effects.
- [x] TDD: cross-Provider draft/edit/submit distinction and terminal restoration.
- [x] TDD: shared application capture routes, selection-to-model handoff, and no-effect result rerun.
- [x] Verify strict build, focused/full tests, native/render contracts and localization parity.
- [x] Reconcile every Ticket 22 checklist criterion with a named test/gate/evidence.
- [x] Review code (separate gate).
- [x] Review tests (separate gate).
- [x] Spec terminal audit and features-catalog three-stage regression.
- [ ] Commit, push, open PR; stop before merge or installation.

## Verification environment

Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for SwiftPM tests, as verified during Ticket 21 delivery. Failures must stop the command chain before submission. No Ticket 22 product test or implementation result is claimed yet.

## Implementation evidence — 2026-09-07

The preparation statements above describe the initial checkpoint. The user approved the shared production workflow entry. Shortcut/menu capture, selection handoff and current/historical workspace reruns now enter it before native capture, workspace mutation or persistence effects.

| Ticket criterion | Redeeming test / evidence |
|---|---|
| Owner-only symmetric gate | `exclusiveActivityReleaseRequiresTheOwnerToken`, `providerValidationAndCaptureAreMutuallyExclusive`, `workflowOwnerBlocksAllConfigurationChanges` |
| Recovery waiting / cancellation | `reconciliationWaitsForModelRequestToFinish`, `reconciliationWaitsForCaptureToFinish`, `canceledRecoveryDoesNotWaitForOwner`; continuation wakeup on owner release, no production timer |
| Capture/model read-only | `captureActivityLocksSession`, `readOnlyStateBlocksConfigurationMutations`, `activeRequestFreezesModelSelection`; native fields retain separate editing and submission eligibility |
| Another Provider draft / no second submit | `crossProviderSubmissionIsExclusive` success/failure; `activeCredentialJobControlsEditingAndValidationSeparately` valid/empty/newline; `otherProviderJobBlocksNativeSubmission` real field, click, Return, terminal positive control |
| Capture routes / result history | `captureRoutesActiveProviderJob` shortcut/menu; `activeJobFocusNavigatesExistingWindow`; `blockedTryAgainPreservesHistory` real SQLite, screenshot store, runner and workspace; terminal control changes Result 1 to Result 2 under the original ID |
| Toolbar surface | `Ticket10RenderingTests.toolbarRendersTargetLanguageSelection`; fresh 2026-09-07 16:18 renders under `vlmsnapper-ticket10-renders-47888D1F-3100-4426-9176-3D84C31F82A9`; inspected en/light PNG. Production toolbar constructor/body enumerates extract, translate, target language, Provider summary, cancel. `WorkspaceOperationKind` has extract/translate; no credential state input. Prototype body lines 159–166 has the same action set and no configuration-in-progress state. This is a state/action comparison, not a claim of pixel identity across SF Symbols and HTML icons. |
| Gates | Strict build exit 0; full suite 325 tests / 72 suites exit 0 before the final focus test, which separately passed. Final all-in-one rerun follows reviews. |

Red evidence: `ticket22-owner-red.log` failed both foreign/stale release assertions; `ticket22-recovery-red.log` failed with configurationLocked; each became green. Integration additionally exposed async protocol default dispatch masking the actor activity query (`ticket22-routing-integration.log`, 9 failures); removing the default implementation made the same suite green (`ticket22-activity-dispatch-green.log`, 51 tests).

The initial unconditional capture-effect stub was rejected by safety review before application. It was not retried through another tool. The shared entry was added guarded from inception; new effect tests use real blocked and admitted controls and are not described as red-first evidence. No installed application or real account request was used. Native events are synthetic AppKit tests, not a claim of physical keyboard or installed-app acceptance.

UI admission: existing confirmed lock strip and disabled controls are reused. The lock-strip wording alone changed under the pure-copy prototype exception to avoid falsely identifying capture/credential activity as a model request. Theme, centralized native icon enum and both localization dictionary anchors were inspected; no colors, geometry or icons were changed. The native screenshot `/private/tmp/vlmsnapper-ticket22-other-provider.png` was inspected: editable field and disabled Validate remain visible without clipping at minimum content size.

## Final delivery gate

- Final strict build: /private/tmp/ticket22-delivery-strict.log, exit 0.
- Final full suite: /private/tmp/ticket22-delivery-full.log, 326 tests / 72 suites, 16.513 seconds, exit 0.
- The same guarded command chain completed bash syntax checks and git diff --check with exit 0.
- Separate review-code and review-tests sections recorded. Stricter canValidate mutation produced two expected failures; exact restoration plus native/state regressions passed. No production gate-removal mutation claimed.
- Code review restored unsaved-result window fronting omitted by the rewritten native adapter. Existing unsaved preparation test passes, but physical foregrounding remains explicit signed-app acceptance; no fake routing test added.
- Spec, features, CONTEXT, checklist and paired localized prototype wording synchronized; three-stage scoped final-regression recorded. Ticket 23 remains whole-feature/installed interaction closeout.
- Only commit/push/open PR remain. No merge/install/release authorized for this delivery.
