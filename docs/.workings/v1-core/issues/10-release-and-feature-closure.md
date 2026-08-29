# 10 — Release and feature closure

Status: in progress (formal release gates blocked)

Blocked by: public HTTPS artifact hosting, a signed update-from-previous-version exercise, and the remaining protected live Provider contracts

## Goal

完成全规格核销、功能目录、全量回归和 Universal/Apple Silicon/Intel 直接分发门禁。

## Acceptance

- `docs/features/v1-core.md` 与实现、spec、ADR 和原型一致。
- lint、单元/集成、UI/E2E、真实 Provider 契约和三架构构建全绿。
- 三个 DMG 的签名、公证、stapling、Gatekeeper、EdDSA 与独立 appcast 全部通过，否则整版不发布。
- review-code、review-tests 和 final-regression 证据齐全。

## Comments

- 2026-08-27: Production accessory app composition, menu/onboarding/settings/history/capture/result wiring, custom shortcut, target-language picker, diagnostics export, coordinated termination, and application-lifetime cleanup are implemented.
- 2026-08-27: Strict build and 190 Swift tests across 46 suites pass; 32 Ticket 09 and 4 Ticket 10 bilingual light/dark renders were generated and inspected.
- 2026-08-27: Separate ad-hoc development DMGs for Universal, Apple Silicon, and Intel validate packaging shape only. They do not satisfy the formal release acceptance criteria.
- 2026-08-27: Formal completion remains fail-closed until signed/notarized/stapled/Gatekeeper/EdDSA artifacts and live Provider contracts have real evidence.
- 2026-08-27: The formal workflow now runs one fixed-image translation contract per Provider and uploads an allowlisted JSON report even when the gate fails. Missing key/model configuration is blocked and no request is retried.
- 2026-08-27: GitHub has no release or Provider secrets/variables, the local keychain has no valid signing identity, and no public feed/download URL is configured. Repeated Gemini probes produced passed, malformed-output, and first-text-timeout outcomes, so live Provider evidence is not currently green.
- 2026-08-28: The local Developer ID identity and Apple notary profile were validated. The first formal arm64 pass reached Accepted app and DMG notarization, stapling, and Gatekeeper acceptance before exposing an appcast path defect; these diagnostic artifacts were not published.
- 2026-08-28: Sparkle resolved a relative `-o` path against the repository working directory, while the release script expected the XML in per-architecture staging. A dedicated script seam now supplies an absolute staging path, with a regression test that rejects both missing staged output and working-directory leakage.
- 2026-08-28: The selected HTTPS feed and download routes are reachable but return 404 until artifacts are uploaded. No public-hosting or signed-update gate is claimed complete by local packaging alone.
- 2026-08-28: The merged absolute-path repair allowed appcast generation to run, then a second formal arm64 pass exposed URL directory semantics: Sparkle replaced the final `v0.1.0` component when the prefix lacked a trailing slash. The helper now normalizes the prefix to exactly one trailing slash, and the regression seam asserts the versioned directory survives.
- 2026-08-28: A signed installation exposed missing `NSScreenCaptureUsageDescription` metadata. The repair requires an English fallback plus exact `en` and `zh-Hans` localized purpose strings in every final app bundle, with source-metadata and packaged-app gates before a rebuilt artifact can replace the affected build.
