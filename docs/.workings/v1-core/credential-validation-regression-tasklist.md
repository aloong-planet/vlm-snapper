# Inline credential validation regression

Scope: repair the installed Ticket 19 candidate's empty-to-nonempty Validate interaction. This is a regression follow-up on the existing local candidate branch, not completion of Ticket 20's native editor and submission-lifecycle criteria. Preserve the separate uncommitted Ticket 20-22 draft worktree. Local installation is requested; do not publish or merge.

Confirmed UI: the existing management-center prototype requires a nonempty edited key to enable Validate. No geometry, icon, color, or copy changes are planned.

- [x] Build a real ManagementCenterWindowController test: insert dummy text through the AppKit field editor and click Validate.
- [x] Reproduce empty-to-nonempty failure and prove the same click submits when the field was initially nonempty.
- [x] Fix the input-to-control state propagation and cover clear, Return, and fresh window renders.
- [x] Run focused interaction tests and full verification (strict build; 272 tests / 69 suites).
- [x] Run code review as a separate pass and record findings.
- [x] Run test review as a separate pass and record findings.
- [x] Reconcile spec/features and document why prior tests missed the defect.
- [x] Build, sign, and install the verified local candidate for user testing: `/Applications/VLMSnapper.app`, 0.1.0 (25), arm64. Developer ID and embedded provisioning profile validation passed. The previous app was moved to `/Applications/VLMSnapper.app.backup-20260905-build24-before-validation-fix` after normal quit. No push, merge, tag, or public release.

Red command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ProviderCredentialInteractionTests`.
Observed before the fix: with an initially empty field, the underlying binding contains `test-key`, the field shows bullets and Pending Validation, but clicking Validate leaves submissions empty. The prefilled control case submits exactly `test-key`. Red log: `/private/tmp/vlmsnapper-credential-red.log`. The test refreshes `/private/tmp/vlmsnapper-credential-empty.png` on each run; it now shows the final enabled button.
