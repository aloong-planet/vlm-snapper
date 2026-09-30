# Scoped final regression — 2026-09-30

## Stage 1: changed declarations

| Pair | Conclusion |
| --- | --- |
| Spec updates section ↔ implementation | Explanation remains under the switch only; absent for idle/current/checking status detail. Other state details remain. |
| Spec ↔ features | Both state the same copy-only behavior; no update functionality removed. |
| Prototype ↔ implementation | Prototype already places the automatic-check explanation only at the switch. No change needed for this request; no claim of broader visual parity. |

## Stage 2: relationships

| Pair | Conclusion |
| --- | --- |
| Strings ↔ view consumers | `rg -n 'automaticChecksHint|updateAutomaticChecksHint' VLMSnapper docs/prototypes/management-center` shows the dictionary/facade and one remaining view call at the switch. Keep both language entries. |
| Feature/spec ↔ indexes | No name, scope or index-summary change; index descriptions remain true. |
| ADR-0004 / CONTEXT ↔ update copy | No distribution, update flow, model or terminology decision changed. |
| Copy rule ↔ checks | Fresh four-variant rendering inspected; automated PNG check alone is not a text-content gate. |

## Stage 3: events

| Event | Conclusion |
| --- | --- |
| Supported members/state set | No members added/removed; localization remains enabled per AGENTS.md. |
| Pending conditions | No earlier feature Pending acceptance condition is discharged by deleting this sentence. |
| New rule | Narrow display rule recorded in existing v1-core spec updates section; no new cross-project rule. |

## Validation and delivery

- Production rendering passed and four images were inspected; no repeated hint or vacant detail line.
- Offline regression: exit 0; log `/tmp/vlm-update-copy-regression.log`, detailed evidence `vlmsnapper-full-regression.S3g9A0` in the system temporary directory. Strict build, script tests, checklist, shell syntax, 369 non-App Swift tests, 22 App Swift tests, 31 native XCTest cases, two isolated native cases and 18 AX cases passed. No live model calls.
- Local installation: arm64 0.1.0 (50) built, Developer ID signed with secure timestamp and validated profile/Keychain entitlements. Normal quit followed by direct overwrite of `/Applications/VLMSnapper.app`; no backup or user-data modification. Post-install strict verification passed, Info.plist reports 0.1.0 / 50, and installed executable launched (PID 54627). Build/signing/installed verification logs are in `/tmp/vlmsnapper-update-copy-install.eCNEXl/`. No commit, push or merge performed.

## 2026-09-30 — compact spacing follow-up

### Stage 1

| Pair | Conclusion |
| --- | --- |
| Spec ↔ implementation | No extra vertical padding for the three states with nil details; other states retain their spacing. |
| Spec ↔ features | Both describe compact single-line status spacing, not a new update behavior. |
| Prototype ↔ implementation | Compact current/checking presentation retained; native Form geometry is not hardcoded to browser pixels. Installed visual parity pending due to CUA failure. |

### Stage 2

| Pair | Conclusion |
| --- | --- |
| Dictionaries ↔ update view | Both locales keep title/action and switch hint. No string changes this turn. |
| Spec/features ↔ indexes | No feature name or scope change, existing indexes remain applicable. |
| ADR/CONTEXT ↔ implementation | Update comparison, distribution and state transitions unchanged. |
| Rule ↔ verification | Tests skipped by user instruction; build and strict install checks passed, not substitutes for visual evidence. |

### Stage 3

| Event | Conclusion |
| --- | --- |
| State/language members | Unchanged. i18n enabled per AGENTS.md; no additions. |
| Prototype confirmation | User requested App synchronization; implementation gate satisfied. Visual acceptance is separate and remains open. |
| New cross-project rule | None. Narrow style requirement recorded in existing spec. |
| Local installation | Replaced build 50 with verified build 51 without backup or user-data changes. CUA could not confirm launch after installation. |

Evidence: `/tmp/vlmsnapper-update-spacing.qF7PHE/{build,signing,verification,installed-verification}.log`; installed plist reads 0.1.0 / 51. No tests run, no commit/push/merge, and no full-feature closeout claimed. See spacing-follow-up.md for the visual-verification gap.
