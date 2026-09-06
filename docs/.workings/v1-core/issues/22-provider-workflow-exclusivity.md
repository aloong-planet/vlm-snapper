# 22 — Make Provider credential work exclusive with capture and model requests

**What to build:** Give Provider validation and recovery one application-owned activity slot that cannot overlap screen capture, selection, model requests, or result reruns. Blocked user actions must preserve existing work and guide the user to the active Provider job instead of starting a partial second workflow.

**Blocked by:** 21 — Reconcile Provider credentials from Keychain truth.

**Status:** ready-for-agent

- [ ] Capture, model request, Provider validation, and Provider recovery acquire one symmetric application activity gate; only the owning token can transition or release it — **test**: `ProviderConfigurationCoordinatorTests.providerValidationAndCaptureAreMutuallyExclusive` and `ProviderConfigurationCoordinatorTests.exclusiveActivityReleaseRequiresTheOwnerToken`.
- [ ] Recovery waits for an active capture or model request to finish and becomes exclusive before reading/listing/publishing Provider state; no polling path can bypass the gate — **test**: `ProviderConfigurationCoordinatorTests.reconciliationWaitsForCaptureToFinish` plus a nameable model-request counterpart.
- [ ] While a model request, frozen capture, or selection is active, Provider cards remain viewable but all credential, model, refresh, current-Provider, and removal mutations are disabled until the owner ends — **test**: `ProviderSetupSessionTests.readOnlyStateBlocksConfigurationMutations`, `ProviderConfigurationCoordinatorTests.activeRequestFreezesModelSelection`, and `ProviderConfigurationCoordinatorTests.requestFreezeDoesNotOverlapConfigurationMutation`.
- [ ] While one Provider credential job is active, another Provider may keep a window-session draft but cannot validate; repeated click or Return produces no second request and availability restores from the real draft state at terminal completion — **test**: `ProviderSettingsPresentationTests.activeCredentialJobControlsEditingAndValidationSeparately` plus a nameable exactly-once cross-Provider submission case.
- [ ] Capture shortcut and menu capture do not freeze or create a selection while credential work is active; they bring Settings Center and the active Provider job forward. Result Try Again likewise starts no request and creates or modifies no history — **test**: application-routing and result-runner cases must be nameable for shortcut, menu action, and Try Again before completion.
- [ ] The capture toolbar never adds a configuration-in-progress state because mutually exclusive Provider work prevents that surface from opening — **evidence**: fresh capture-toolbar prototype/production comparison and an exhaustive state enumeration record no such state.
- [ ] Strict build, focused gate/application-routing tests, full tests, render contracts, and `git diff --check` pass — **gate**: the repository's complete local verification commands fail non-zero on any regression.

## Comments

- 2026-09-05: This ticket was cut after the gate implementation had already been drafted. Missing named application-level cases remain real acceptance gaps even if lower-level gate tests are green.
