# Ticket 06 — Design review

Date: 2026-08-27

## Findings resolved before implementation

1. A single enum for each tab would erase the old success when rerun begins. The reviewed model separates committed success from the current attempt so replacement occurs only after new success persistence.
2. A window-owned busy flag would allow a history rerun or second workspace to overlap. The reviewed design uses an application-scoped lease and makes window visibility independent of activity ownership.
3. Persisting a screenshot once per operation would duplicate files and break the shared-screenshot mental model. The workspace caches one managed screenshot identity and prepares a separate typed history row per attempt.
4. The existing schema cannot support the confirmed history type filter or translation target. Schema v2 and transactional v1 migration are prerequisites, not deferred UI metadata.
5. Canceling the Swift task without writing a terminal row would leave routine user cancellations to look like crashes after restart. The cancellation sequence persists `canceled`; startup interruption remains only the recovery fallback.
6. A generic Retry action could accidentally replay a completed Provider request after final database failure. Retry Save is a distinct intent carrying the completed in-memory output and has no Provider dependency.
7. Closing behavior has three materially different paths: discard before history, cancel while running, and hide after terminal. The window delegate must query the workflow outcome instead of treating every close identically.

## Scenario completeness check

- Entry paths: fresh selected PNG, reopened terminal history result, and future history rerun all converge on the same operation slot snapshot; only fresh capture owns an unpersisted PNG.
- Activity exits: success persisted, Provider failure persisted, user cancellation persisted, terminal persistence failure retained in memory, or unexpected task cancellation with recovery row. Every path releases the global lease once.
- Display switching cannot initiate work. Explicit Start/Retry/Rerun are the only request-producing intents.
- A Provider/model/target change after attempt start cannot mutate that attempt because identity is frozen before history preparation.
- Old success survives preparation, transport, protocol, cancellation and persistence failures; only persisted new success replaces it.

## Review conclusion

The design now covers the acceptance criteria and the high-risk asynchronous/persistence paths without inventing new product choices. Implementation may proceed test-first at the actor and SQLite seams, followed by native UI rendering against the confirmed prototypes.
