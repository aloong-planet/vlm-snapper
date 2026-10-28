# Local install — 2026-10-28

- Installed: `/Applications/VLMSnapper.app`, version 0.1.2, arm64, Developer ID `RHQ28XS7D9`, embedded provisioning
  profile `VLMSnapper` (taken from the previously installed app; expires 2044). Executable SHA-256
  `bdab2f2b5e211727f4f81e1bdb64810183b7c43190e67664650979f46e49db80`.
- Contents: this branch at `208266a` plus an unpushed local merge of the open PR #34 branch
  `codex/extraction-to-translation` (`a4758c0`). The previously installed 0.1.1 was built from PR #34, so a build of
  this branch alone would have removed its saved-text translation. Code merged without conflicts; the two
  documentation conflicts were resolved with this branch's text and do not affect the binary. PR #34 adds no history
  schema change (its own review record), so the database stays compatible in both directions.
- Verification of the combined tree before building: `Scripts/test-local-regression.sh --offline` passed every stage
  (strict build, script tests, checklist, shell syntax, non-app, app, native Paste, native closed-window,
  accessibility).
- Build: `Scripts/build-macos-app.sh arm64 0.1.2 https://development.invalid/vlmsnapper/appcast-arm64.xml <key>` with
  the installed app's feed URL and Sparkle key; signed with `Scripts/sign-developer-id-app.sh`, which verified profile,
  team, application identifier and Keychain group. Designated requirement equals the previous install's, so the
  screen-recording permission and Keychain access carry over. `--verify-data-protection-keychain` (random service, no
  user credential touched) passed.
- Install: the app was not running; the previous 0.1.1 was moved to
  `/Applications/VLMSnapper.app.backup-20261028-0.1.1-before-instant-capture`, the new app copied with `ditto`,
  re-verified in place (`codesign --verify --deep --strict`, executable identical to the signed build, version 0.1.2)
  and launched. Not notarized, like the previous local install; no quarantine attribute.
- Not done: no history, settings, screenshots, credentials or permissions changed; no tag or release.

Rollback: quit VLMSnapper, then move the backup back to `/Applications/VLMSnapper.app`.

Please try: press the capture shortcut and check that the dimmed overlay appears at once; drag immediately after
pressing; press Esc right after the shortcut; retrigger while a selection is shown; and use Translate on saved text
from history (PR #34) to confirm it is still present.

## Reinstall — 0.1.3 (same day, after user feedback)

- Reason: user feedback on 0.1.2, 2026-10-28, verbatim: “有一个问题，按截图快捷键后，遮罩没有直接覆盖全屏幕，看起来像是先铺了遮罩但是
  遮罩没有完全覆盖屏幕，然后遮罩快速扩大到整个屏幕，是什么原因？” Cause and fix in `review-code.md` (window-open
  animation). The user's hands-on check of 0.1.3 is still to come.
- Contents: this branch at `17dbf8d` plus the same local merge of PR #34 (`a4758c0`); code identical to the 0.1.2
  tree that passed the full offline regression except the one-line `animationBehavior = .none`, which passed the
  targeted run (`logs/targeted-animation-fix.log`). Signed and verified the same way; Keychain smoke test passed.
- Installed `/Applications/VLMSnapper.app` 0.1.3, executable SHA-256
  `f6be156aa961e390677d9d87f553fef5473033b8bd8f8e12b4544b76b2044e4b`. The superseded 0.1.2 was moved out of
  `/Applications` to session scratch storage; the rollback target remains
  `/Applications/VLMSnapper.app.backup-20261028-0.1.1-before-instant-capture`.
- Hotkey-to-screen measurements of 0.1.1, 0.1.2 and 0.1.3 are in `measurements.md`.
