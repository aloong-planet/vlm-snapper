# Capture self-exclusion implementation tasklist

- [x] Update the v1 specification, ADR-0010, and project terminology for self-excluding capture and macOS 14.4.
- [x] Add failing tests for reversible workspace capture preparation and atomic overlay replacement.
- [x] Capture every display from one ScreenCaptureKit snapshot while excluding the current process.
- [x] Retire only known VLMSnapper surfaces after the replacement overlay is visible.
- [x] Preserve the current workspace or selection when freezing or overlay presentation fails.
- [x] Align every build, verification, and release minimum-version gate to macOS 14.4.
- [x] Run focused and full verification.
- [x] Complete code review and record it in `review-code.md`.
- [x] Complete test review and record it in `review-tests.md`.
- [x] Update the feature catalog and complete the final documentation regression.
