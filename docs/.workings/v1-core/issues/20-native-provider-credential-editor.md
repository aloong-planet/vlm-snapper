# 20 — Make Provider credential editing deterministic

**What to build:** Give each inline Provider card one native macOS API Key editor whose text, placeholder, status, buttons, focus, insertion point, and selection remain coherent across typing, Command-V, clear, secure/plain visibility changes, view refreshes, card switches, and validation submission.

**Blocked by:** 19 — Manage Providers inline in Settings Center.

**Status:** ready-for-review

- [x] Keyboard input preserves every character, while each paste removes at most one trailing CRLF, LF, or CR sequence and replaces the current selection without trimming or Unicode normalization — **test**: `ProviderAPIKeyFieldTests.pasteNormalizationIsNarrow`, `ProviderCredentialInteractionTests.pasteReplacesSelectionWithoutTrimming`, and `ProviderAPIKeyFieldTests.standardPasteRoutes`.
- [x] Empty values, values containing a remaining newline, and values above 4096 UTF-8 bytes stay local and cannot start Provider validation; all other characters remain opaque — **test**: `ProviderAPIKeyInputTests.validationUsesTheDocumentedSafetyBoundary`, `ProviderConfigurationCoordinatorTests.unsafeInputPreservesSavedConfiguration`, `ProviderCredentialInteractionTests.unsafeDraftCannotValidate` and `ProviderSettingsPresentationTests.localAPIKeyErrorsHaveSpecificHints`.
- [x] Secure/plain visibility changes preserve the current value, focus, insertion point, and selection without changing dirty state or triggering validation — **test**: `ProviderAPIKeyFieldTests.visibilityPreservesSelection` using the real AppKit field editor.
- [x] Placeholder, status, clear availability, and validation availability derive from the same window-session value and remain coherent when the Settings Center re-renders — **test**: `ProviderSettingsPresentationTests.inlineCredentialStates`, `ProviderCredentialInteractionTests.revertedCredentialCannotSubmit`, and `ProviderSettingsPresentationTests.validationAndFailureOverrideStatus`.
- [x] Switching cards or closing Settings Center discards only an unsubmitted draft; a submitted validation captures an immutable Provider and exact key and may update only that original Provider — **test**: `ProviderSetupSessionTests.selectingProviderClearsTransientState`, `ProviderSetupSessionTests.submittedValidationUsesExplicitProvider`, `ProviderSetupSessionTests.pendingValidationSuppressesDuplicates`, `ProviderCredentialEditorTests.lateReadCannotPopulateNewVisit`, and `ProviderCredentialInteractionTests.windowCloseDiscardsDraft`.
- [x] Clicking Validate and pressing Return enter the same exactly-once submission path, and an unchanged loaded credential cannot be resubmitted — **test**: `ProviderCredentialInteractionTests.editingEnablesValidation`, `ProviderCredentialInteractionTests.revertedCredentialCannotSubmit`, and `ProviderCredentialEditorTests.submissionIdentityAndCompletion`.
- [x] Strict build, focused AppKit/UI tests, full tests, localization-key parity, and `git diff --check` pass — **gate**: the repository's complete local verification commands fail non-zero on any regression.

## Comments

- 2026-09-06: All Ticket 20 criteria are now mapped and locally verified. Strict build, 293 tests / 72 suites, 248-key bilingual parity and rebuilt native menu 10/10 pass; whole-ticket code/test reviews and scoped final regression are recorded. Ready for PR review, not merged or installed. Signed/live and physical-input acceptance are not claimed; Ticket 21–23 requirements remain open.

- 2026-09-06: Continued after synchronizing Ticket 19 to completed/merged. Added deliberate red-green tests for duplicate in-flight validation and explicit submission identity. Validate and Return now pass the displayed Provider/key values to application dispatch; the session preserves that Provider even if the card changes before dispatch. Duplicate suppression remains scoped to an in-flight validation for the same Provider and releases on success/failure. This does not yet accept unchanged-key suppression, draft/close/read generations, or full cross-workflow exclusivity. Full suite: 282 tests / 71 suites passed. No commit, PR or installation.

- 2026-09-05: This ticket was published after draft implementation had already begun. Existing green tests are inputs to review, not completion evidence, until each criterion is deliberately re-run and mutation-checked.
- 2026-09-06: Native editing and local input safety are implemented in the isolated Ticket 20 worktree. Strict build and 280 tests passed, but the ticket is not complete. Stable native context-menu acceptance and its mutation check, draft lifetime, immutable submission/duplicate suppression, ownership reconciliation, independent reviews, and documentation closeout remain pending. No PR or installed-app update was made.
