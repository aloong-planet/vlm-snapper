# 22 — Make Provider credential work exclusive with capture and model requests

**What to build:** Give Provider validation and recovery one application-owned activity slot that cannot overlap screen capture, selection, model requests, or result reruns. Blocked user actions must preserve existing work and guide the user to the active Provider job instead of starting a partial second workflow.

**Blocked by:** 21 — Reconcile Provider credentials from Keychain truth.

**Status:** ready-for-review

- [x] Capture, model request, Provider validation, and Provider recovery acquire one symmetric application activity gate; only the owning token can transition or release it — **test**: `ProviderConfigurationCoordinatorTests.providerValidationAndCaptureAreMutuallyExclusive` and `ProviderConfigurationCoordinatorTests.exclusiveActivityReleaseRequiresTheOwnerToken`.
- [x] Recovery waits for an active capture or model request to finish and becomes exclusive before reading/listing/publishing Provider state; no polling path can bypass the gate — **test**: `ProviderConfigurationCoordinatorTests.reconciliationWaitsForCaptureToFinish` plus a nameable model-request counterpart.
- [x] While a model request, frozen capture, or selection is active, Provider cards remain viewable but all credential, model, refresh, current-Provider, and removal mutations are disabled until the owner ends — **test**: `ProviderSetupSessionTests.readOnlyStateBlocksConfigurationMutations`, `ProviderConfigurationCoordinatorTests.activeRequestFreezesModelSelection`, and `ProviderConfigurationCoordinatorTests.requestFreezeDoesNotOverlapConfigurationMutation`.
- [x] While one Provider credential job is active, another Provider may keep a window-session draft but cannot validate; repeated click or Return produces no second request and availability restores from the real draft state at terminal completion — **test**: `ProviderSettingsPresentationTests.activeCredentialJobControlsEditingAndValidationSeparately` plus a nameable exactly-once cross-Provider submission case.
- [x] Capture shortcut and menu capture do not freeze or create a selection while credential work is active; they bring Settings Center and the active Provider job forward. Result Try Again likewise starts no request and creates or modifies no history — **test**: application-routing and result-runner cases must be nameable for shortcut, menu action, and Try Again before completion.
- [x] The capture toolbar never adds a configuration-in-progress state because mutually exclusive Provider work prevents that surface from opening — **evidence**: fresh capture-toolbar prototype/production comparison and an exhaustive state enumeration record no such state.
- [x] Strict build, focused gate/application-routing tests, full tests, render contracts, and `git diff --check` pass — **gate**: the repository's complete local verification commands fail non-zero on any regression.

## Comments

- 2026-09-07 delivery: user confirmed the production-used workflow seam. All seven criteria now have named evidence in the tasklist; strict build and full 326 tests / 72 suites passed (16.513 seconds), script syntax and diff check exit 0. Separate code/test reviews and three-stage scoped document regression are recorded. New capture/rerun effect tests are not falsely called red-first; stricter terminal-button mutation failed both presentation and native click assertions, then passed after exact restoration. Physical shortcut and installed-app foregrounding remain explicit combined-acceptance gaps in Ticket 23. Ready for PR review, not merged, installed or released.

- 2026-09-07: Started from merged PR #25 on `codex/ticket-22-provider-workflow-exclusivity`. Current-source inspection identified that production capture/rerun routes are private and constructed with real OS/account dependencies. A small shared production application-workflow boundary is proposed for the ticket's required routing tests; agreement is pending before test/code changes. See `../22-provider-workflow-exclusivity-tasklist.md`. No acceptance criterion is checked by this preparation.

- 2026-09-05: This ticket was cut after the gate implementation had already been drafted. Missing named application-level cases remain real acceptance gaps even if lower-level gate tests are green.
