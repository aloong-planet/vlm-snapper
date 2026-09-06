# 21 — Reconcile Provider credentials from Keychain truth

**What to build:** Treat Keychain as the source of truth for whether a Provider credential exists. Replace a submitted old credential without rollback, publish model metadata only after the new credential is durable, and deterministically recover or clear partial state on card open and application startup without exposing secret material.

**Blocked by:** 20 — Make Provider credential editing deterministic.

**Status:** ready-for-agent

- [ ] Submitting a changed key immediately removes the old credential's rollback eligibility, model configuration, and current-Provider eligibility; validation, listing, or storage failure never restores them — **test**: `ProviderConfigurationCoordinatorTests.credentialWriteFailureDoesNotRestorePreviousConfiguration` and `ProviderConfigurationCoordinatorTests.listFailureDoesNotRestorePreviousProviderConfiguration`.
- [ ] A successful replacement preserves the previous model only when it remains in the complete returned list and never steals the global current selection from another usable Provider — **test**: `ProviderConfigurationCoordinatorTests.replacementPreservesAvailableModelAndCurrentProvider` and `ProviderConfigurationCoordinatorTests.configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider`.
- [ ] A Keychain item without consistent metadata enters recovery and republishes the complete model configuration; metadata without a Keychain item is cleared together with any global current reference — **test**: `ProviderConfigurationCoordinatorTests.reconciliationRecoversStoredKeyWithoutConfiguration`, `ProviderConfigurationCoordinatorTests.reconciliationCommitsMetadataForDurableNewCredential`, and `ProviderConfigurationCoordinatorTests.reconciliationClearsConfigurationWithoutCredential`.
- [ ] Missing credentials and Keychain read failures remain distinct: missing means unconfigured, while permission, entitlement, access-control, or other read failure preserves metadata, exposes local secure-storage failure, and keeps editing read-only until an explicit reopen retries — **test**: `ProviderSetupSessionTests.keychainReadFailureIsNotMissingCredential`, `ProviderConfigurationCoordinatorTests.reconciliationPreservesStateOnCredentialReadFailure`, and a nameable reopen-retry case.
- [ ] Closing during load invalidates that generation; closing during submitted validation does not cancel application-owned work; reopening reconnects to validation, recovery, failure, pending-model, or configured state without resubmission — **test**: `ProviderSetupSessionTests.closingEditorInvalidatesCredentialRead`, `ProviderSetupSessionTests.submittedValidationIsNotMistakenForRecovery`, and a nameable close/reopen validation-continuity case.
- [ ] Keychain write failure and metadata publication failure do not mark the Provider usable and are reported as local secure-storage failures; a durable new key survives metadata failure for next-start recovery — **test**: `ProviderSetupSessionTests.keychainWriteFailureIsReportedAsLocalSecureStorage`, `ProviderConfigurationCoordinatorTests.reconciliationCommitsMetadataForDurableNewCredential`, and a fault-injection case for post-Keychain metadata failure.
- [ ] Candidate API Keys exist only in memory until Keychain persistence, are absent from metadata and diagnostic output, and are discarded on application termination — **evidence**: code review records the exhaustive secret-flow search, inspected persistence boundaries, and termination path without printing a credential.
- [ ] The final signed application still passes the existing Data Protection Keychain CRUD release gate — **gate**: Ticket 16's signed Universal application Keychain smoke test remains mandatory and non-zero on failure.
- [ ] Strict build, focused reconciliation tests, full tests, localization-key parity, and `git diff --check` pass — **gate**: the repository's complete local verification commands fail non-zero on any regression.

## Comments

- 2026-09-05: This ticket formalizes recovery work already present as an uncommitted draft. It is ready for deliberate verification; no criterion is accepted retroactively.
