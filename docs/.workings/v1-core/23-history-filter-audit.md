# Ticket 23 — History-filter closeout discrepancy

Date: 2026-09-09. Current source inspection, not a full-feature acceptance report.

## Requirement and observed implementation

US-10 in `docs/specs/v1-core.md` requires status, Provider, model, target-language,
date and pinned filters as well as operation kind and text search.

| Layer | Evidence | Conclusion |
|---|---|---|
| Query contract | `Sources/VLMSnapperCore/HistoryManagement.swift`, `HistoryQuery` | All dimensions exist in the public query type. |
| SQLite | `Sources/VLMSnapperCore/SQLiteHistoryStore.swift`, `history(matching:operationID:)` | Optional dimensions produce SQL predicates and bound values. |
| Production application | `Sources/VLMSnapperApp/VLMSnapperApplicationModel.swift`, `start` and `refreshHistory` | Both fetch the unrestricted `HistoryQuery()`. |
| Native view | `VLMSnapper/UI/ManagementCenterView.swift`, state, `contentToolbar`, `filteredRecords` | The public workflow selects kind, text search and pinned navigation only; its predicate contains only these three dimensions. |
| Prototype | `docs/prototypes/management-center/prototype-management-center.html`, titlebar and `applyHistoryFilter` | The confirmed toolbar models type/search, not the five missing controls. A new control placement requires prototype approval. |

Search scope: enumerated production `HistoryQuery` references across `Sources`
and `VLMSnapper`, then inspected the query type, SQL builder, both application
callers and the view's actual toolbar/predicate. This conclusion is based on the
connected input/query path, not on absence of a guessed control name.

## Why existing evidence did not catch it

- `SQLiteHistoryStoreTests.pinningAndMetricsSurviveCompleteFilter` calls the store
  directly, bypassing native controls. Its one stored record matches every
  criterion; this establishes positive retrieval and metrics, not rejection of
  nonmatching records for each filter independently. No target mutation was run
  in this continuation; do not claim demonstrated mutation sensitivity.
- `Ticket08RenderingTests.managementCenterStatesRender` writes eight images and
  checks image count/byte size. It does not activate or assert the missing
  filter controls. Those assertions remain useful as render smoke checks, not
  interaction acceptance.
- `Scripts/verify-feature-checklist.py` checks 58 unique ownership rows and
  nonempty cells. It explicitly does not certify implementation; its green
  result cannot resolve this missing product workflow.
- Ticket 08's acceptance named type/search while the broader US-10 clause was
  not checked at the production boundary. The ownership table's generic
  “existing acceptance” reference concealed this difference until semantic audit.

## Disposition

Impact: users cannot narrow history by the five promised dimensions; no loss or
corruption of stored history is established. This is a cross-layer coverage gap,
not a reason to delete the underlying query support or rewrite the accepted spec.

Owner: keep this finding under local #23, which remains in-progress. Recommended
next step: confirm an advanced-filter layout in the existing management-center
prototype, then implement its native public path. Add mixed matching/nonmatching
fixtures per dimension (including date endpoints), combined filters, reset,
empty results and real control-to-list assertions. Re-run scoped code/test review
and the full-feature gates after implementation. If the user instead chooses to
defer the capability, explicitly revise the spec/ownership scope together; this
audit does not authorize that scope reduction.

The remaining 58-row semantic review is not represented as complete by this
finding. Provider build 29 acceptance, #24 native waits, hardware display testing
and #10 release facts are separate evidence boundaries.

## Fresh validation

- Ownership parser: 58 rows; its six structural tests pass. `git diff --check`
  passes after the documentation corrections.
- First history-test invocation used the default toolchain and exited 1 before
  tests with `no such module 'Testing'`; log:
  `/private/tmp/vlmsnapper-ticket23-history-audit.log`.
- Re-ran with the project's CI `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
  `xcrun swift test --filter SQLiteHistoryStoreTests`, exit 0 and explicit
  **17 tests / 1 suite passed**. Log:
  `/private/tmp/vlmsnapper-ticket23-history-audit-xcode.log`.
- This confirms the existing database tests pass despite the missing native
  workflow. It is not a new UI test, predicate mutation or full-suite pass.
