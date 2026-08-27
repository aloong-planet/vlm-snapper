# 10 — Release and feature closure

Status: in progress (formal release gates blocked)

Blocked by: Developer ID identity, Apple notarization credentials, public HTTPS feed/download hosting, and protected live Provider credentials

## Goal

完成全规格核销、功能目录、全量回归和 Universal/Apple Silicon/Intel 直接分发门禁。

## Acceptance

- `docs/features/v1-core.md` 与实现、spec、ADR 和原型一致。
- lint、单元/集成、UI/E2E、真实 Provider 契约和三架构构建全绿。
- 三个 DMG 的签名、公证、stapling、Gatekeeper、EdDSA 与独立 appcast 全部通过，否则整版不发布。
- review-code、review-tests 和 final-regression 证据齐全。

## Comments

- 2026-08-27: Production accessory app composition, menu/onboarding/settings/history/capture/result wiring, custom shortcut, target-language picker, diagnostics export, coordinated termination, and application-lifetime cleanup are implemented.
- 2026-08-27: Strict build and 184 Swift tests pass; 32 Ticket 09 and 4 Ticket 10 bilingual light/dark renders were generated and inspected.
- 2026-08-27: Separate ad-hoc development DMGs for Universal, Apple Silicon, and Intel validate packaging shape only. They do not satisfy the formal release acceptance criteria.
- 2026-08-27: Formal completion remains fail-closed until signed/notarized/stapled/Gatekeeper/EdDSA artifacts and live Provider contracts have real evidence.
