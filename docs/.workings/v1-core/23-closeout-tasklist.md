# Ticket 23 — Full feature closeout, 2026-09-09

This is construction bookkeeping, not the product specification. Current behavior is defined by `docs/specs/v1-core.md`, `docs/features/v1-core.md`, CONTEXT and accepted ADRs.

- [x] Record the unconfirmed key-window/toolbar timeout investigation separately as local Ticket 24; do not conflate it with the demonstrated teardown crash.
- [ ] Read the current checklist mapping and migrate every effective spec obligation to independent, namespaced coverage units before full closeout. Reconcile each unit with named tests/gates/evidence, retaining explicit gaps; the historical 58-row structure is not the current completeness criterion.
- [ ] Resolve document drift and cross-ticket behavior discrepancies; do not waive accepted requirements to close the ticket.
- [ ] Verify confirmed production surfaces against prototypes and user acceptance, including the Provider icon decision.
- [ ] Run strict build, complete non-App/App/native suites, ownership, localization, prototype and source checks with failure propagation.
- [ ] Run `/review-code` as a separate closeout review.
- [ ] Run `/review-tests` as a separate closeout review.
- [ ] Complete spec verification and the three full-feature consistency tables in `final-regression.md`.
- [ ] Update Ticket 23 status according to the actual results; create a PR only after all required closeout gates pass. Do not merge without confirmation.

## Findings to resolve

- Resolved: FM-43 ownership now includes the stable-layout Refresh clause; retired Provider-sheet and distribution wording were corrected in the feature catalog.
- Resolved: the user accepted the installed build 29 Provider marks. This supplements build 28 VA-01–04 acceptance; it does not certify every failure mode or hardware display scenario.
- US-03 display notifications are now connected in production; real display-change acceptance remains pending in `issues/01-live-display-reconfiguration.md`.
- Newly confirmed: US-10 promises status, Provider, model, target-language and date filters, but the native management center exposes only kind/search/pinned filtering. The database query supports the other dimensions; that is not an accessible product workflow. See `23-history-filter-audit.md`. Keep this discrepancy owned by #23 pending the user's UI/scope decision; do not remove the spec requirement to close the ticket.

## Current checkpoint

2026-09-09 continuation after user acceptance: installed build 29 is accepted for the Provider-icon change. Earlier strict/non-App passes remain historical results; the latest recorded App suite has a toolbar-wait failure tracked by #24. This continuation confirms the display call chain and a missing US-10 UI workflow, and reruns the ownership parser/tests. Ownership remains 58/58, not 58 accepted implementations. Full semantic reconciliation, final code/test reviews and whole-feature regression remain incomplete. Scoped audit records do not substitute for those final gates. No implementation, installation, commit, push or merge in this continuation.
