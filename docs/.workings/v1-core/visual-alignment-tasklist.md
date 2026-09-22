# Visual alignment 1–4 — 2026-09-08

Scope: the user approved aligning VA-01–04 to existing confirmed prototypes. VA-05 and the unresolved Provider letter-mark choice are excluded. This incremental correction does not close the full-feature Ticket 23.

- [x] Read implement/prototype/ui-design, current CONTEXT and relevant ADR; fetch main and create `codex/align-confirmed-visuals` with no additional commits.
- [x] Prototype admission: onboarding Direction A covers intro/card icons/gate/footer; management prototype covers flexible 1:1.1 fields, 32-point controls, 128-point Refresh, footer/label styles and label-free History filter. No redesign or prototype mutation.
- [x] VA-01: align onboarding composition, bilingual readiness messages and grouped footer; preserve callbacks and readiness rules.
- [x] VA-02: align responsive Provider field geometry and model/Refresh control shells without changing selection/refresh admission.
- [x] VA-03: align destructive/current-provider/footer label styles.
- [x] VA-04: hide the visual History filter label, retain accessible label.
- [x] Execute native geometry/selection checks, fresh bilingual light/dark renders, strict build and existing test/package gates; retain the first native focus failure and separate passing rerun below.
- [x] Independent step 5: review-code findings and resolution.
- [x] Independent step 6: review-tests including evidence/false-pass limits.
- [x] Scoped spec/features reconciliation and final-regression record. Full Ticket 23 remains open.
- [ ] Stable full native/physical acceptance and permitted browser/native pixel comparison — retained under Ticket 23, not waived by the independent rerun.

Testing seam: production ManagementCenterWindowController and public AppKit controls, plus real rendered views. Pure style changes use render evidence (TDD exemption), not string/constant assertions. A geometry regression must first fail against the unchanged view; any model-control replacement additionally needs selection/disabled-state coverage. No real keys or Provider requests are needed.

Evidence limitation: local HTML preview was denied by browser URL policy in the audit. Use confirmed source contracts and fresh native renders; do not bypass the denied browser action or claim browser pixel parity. According to project capabilities, English/Simplified Chinese are covered; RTL mirroring is not enabled and is skipped.

## Results and artifacts

- Fresh evidence preserved at `/private/tmp/vlmsnapper-visual-alignment-evidence.NxghbV/`. Inspected 20 affected surface renders and five Refresh state samples. Uninspected permutations and actual title-bar/hover/occlusion are not counted as accepted.
- Strict warnings-as-errors build passed: `/private/tmp/visual-align-final-build.log`.
- 333 tests / 73 suites passed: `/private/tmp/visual-align-final-all.log`.
- 11 application tests passed: `/private/tmp/visual-align-final-app.log`.
- Native Paste first failed before key-window acquisition: `/private/tmp/visual-align-final-paste.log`; unchanged independent run passed one XCTest: `/private/tmp/visual-align-paste-repeat.log`. Root cause and stability are not established; assertions/timeouts unchanged.
- Native closed-window completion passed one XCTest: `/private/tmp/visual-align-final-closed.log`.
- Final reachable-fixture geometry/selection tests passed two cases: `/private/tmp/visual-align-final-geometry.log`.
- Intended baseline geometry red and read-only mutation evidence: `/private/tmp/visual-align-red.log`, `/private/tmp/visual-align-mutation.log`. Compiler/cache failures are not baseline red evidence.
- Six Python checklist tests and 58 requirement ownership entries passed; shell syntax and diff whitespace checks passed.
- arm64/x64/universal development DMGs passed build, app verification and DMG verification: `/private/tmp/visual-align-packages.log`, output `/private/tmp/vlmsnapper-visual-alignment-packages.l9Odf2/`. These are ad-hoc development checks, not release artifacts or installation.

No push, PR, merge, installed-app update or release performed. Per the implement gate, the first failing combined run is not retroactively labeled all-green; native stability remains an explicit handoff item. The bounded visual corrections and their documentation are ready for local review.
