# 19 — Manage Providers inline in Settings Center

**What to build:** Let users configure, validate, select a model for, activate, and remove every supported Provider directly in the Settings Center. Onboarding opens that same surface and returns automatically only after a model is selected. Retire the standalone Provider setup surface so production, prototypes, and test harnesses describe one configuration experience.

**Blocked by:** None — can start immediately.

**Status:** completed (merged)

- [x] Settings Center presents one expanded Provider card at a time, preferring an explicit target, then the current Provider, then DeepSeek; all configuration, model, current-Provider, and removal actions stay in that page — **test**: `ProviderSettingsPresentationTests.expandedProviderPreference`, `ProviderConfigurationCoordinatorTests.selectingFirstUsableProviderMakesItCurrent`, `ProviderConfigurationCoordinatorTests.configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider`, and `ProviderConfigurationCoordinatorTests.clearingProviderRemovesKeyAndMetadataWithoutFallback`.
- [x] Onboarding opens Settings Center at the requested Provider without starting capture or permission recovery; selecting a valid model or closing early returns to onboarding exactly once with the real completion state — **test**: `ProviderSettingsPresentationTests.onboardingReturnIsConsumedExactlyOnce` plus the onboarding navigation cases in `OnboardingSessionTests`.
- [x] Validation remains in the expanded card, reveals the complete model list without choosing a model, and never switches the global current Provider merely because another Provider became usable — **test**: `ProviderSetupSessionTests.validationRevealsModelsWithoutSelection`, `ProviderSetupSessionTests.selectingModelEnablesDone`, and `ProviderConfigurationCoordinatorTests.configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider`.
- [x] The Provider page preserves the confirmed information hierarchy and responsive geometry in both languages and appearances — **evidence**: fresh production renders at normal and narrow Settings Center sizes show the 850 pt content limit, 54 pt card header, 29 pt Provider mark, 32 pt credential field, and wide/tall field layout.
- [x] No production route, harness mode, localized copy, geometry constant, test, manifest entry, or prototype remains for the standalone Provider setup component — **evidence**: repository-wide fixed-string searches across `Sources`, `VLMSnapper`, `Tests`, `docs`, and `Package.swift` return no current reference for the retired UI symbols, accessors, or `--provider`; the non-UI `ProviderSetupSession` remains live.
- [x] Strict build, full tests, localization-key parity, prototype syntax, render-contract tests, and `git diff --check` all pass — **gate**: 271 tests in 68 suites pass with warnings-as-errors; both 246-key localization dictionaries match; 9 HTML prototypes and 9 inline scripts parse.

## Comments

- 2026-09-06: Status synchronized after PR #23 was merged as `eba012fa929e34d0bc3e744eaa7ff2715b15d3e0`. Follow-up native editing and lifecycle requirements remain in Ticket 20; this status update does not accept them retroactively.

- 2026-09-05: This ticket was published after draft implementation had already begun because a tasklist was incorrectly used in place of a formal ticket. Existing behavior was re-verified from the isolated `a97bd73` tree; a missing geometry contract was then added through a deliberate red-green cycle and mutation-checked.
