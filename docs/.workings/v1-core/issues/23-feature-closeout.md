# 23 — 收口:内联 Provider 配置完整验收与文档回归

**这是收口票。** 本 feature 的最后一张，承担全 feature 收口，不交付产品行为。

**Blocked by:** 19 — Manage Providers inline in Settings Center; 20 — Make Provider credential editing deterministic; 21 — Reconcile Provider credentials from Keychain truth; 22 — Make Provider credential work exclusive with capture and model requests.

**Status:** ready-for-agent

- [ ] `/features-catalog` 的全 feature 收口通过 — **evidence**: record the three consistency passes for spec/implementation, implementation/features, and decision/prototype/terminology documents, including every discrepancy and its resolution.
- [ ] The feature checklist maps all twelve v1 User Stories and all forty-six failure modes to an owning ticket and named acceptance criterion, with no uncovered row — **gate**: a reproducible checklist parser verifies the expected 58 unique requirement rows and rejects empty owner or criterion cells.
- [ ] The complete onboarding-to-Provider flow opens inline configuration, accepts a native-field key, validates exactly once, selects a model, persists recoverably, and returns to onboarding without using the retired standalone surface — **test**: one named application-level integration case covers the combined Tickets 19–21 path.
- [ ] Provider validation/recovery and capture/model/rerun cannot interleave in the production composition, and blocked actions preserve existing capture, result, draft, and history state — **test**: one named application-level integration case covers both directions of the Ticket 22 gate and terminal release.
- [ ] Confirmed onboarding, Provider settings, capture toolbar, menu, and result surfaces remain visually consistent in both languages and appearances — **evidence**: inspect and record fresh production renders beside the confirmed prototypes, including normal and minimum Settings Center widths.
- [ ] Retired tasklists no longer act as parallel authority and all surviving implementation/review evidence names Tickets 19–23 consistently — **evidence**: record the repository-wide search commands and results for the retired tasklist names and stale standalone Provider terminology.
- [ ] Strict warnings-as-errors build, full test suite, localization parity, prototype syntax, render contracts, source/literal checks, and `git diff --check` all pass together after the four behavior tickets — **gate**: the repository's full closeout command set fails non-zero on any member failure.

## Comments

- 2026-09-05: This closeout ticket explicitly prevents the retrospectively ticketed drafts from being treated as complete merely because prior tasklists were checked.

- 2026-09-06 Ticket 20 scoped review: the management-center visual demo uses DS/OA/G letter marks while native UI uses the existing symbol anchor. These pre-existing marks are outside the editor fix. Include this in the full visual consistency check; ask for an icon choice before replacing it, do not silently copy letter marks into native UI. The same prototype's old API Key trim/dirty/lifetime simulation is now explicitly marked non-authoritative; layout remains confirmed.
