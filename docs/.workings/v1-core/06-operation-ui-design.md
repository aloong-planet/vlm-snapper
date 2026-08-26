# Ticket 06 — Operation and result UI design

Date: 2026-08-27

## Scope

Implement the application workflow that connects one in-memory selected PNG to the confirmed post-selection toolbar and result workspace. The ticket owns explicit Extract/Translate starts, streaming presentation, one global active model attempt, cancellation, manual retry and rerun semantics. Provider setup, onboarding, history browsing and release packaging remain Tickets 07–10.

## Architecture seams

1. `OperationWorkspaceSession` is an actor and the authoritative presentation workflow model for one selected screenshot. It owns the selected tab, the shared original PNG and one slot per operation.
2. `ActiveOperationGate` is application-scoped, not window-scoped. A lease is acquired before any attempt is prepared and released exactly once at every terminal path. A second workspace or history rerun cannot start while a lease exists.
3. `OperationWorkspaceRunning` is the session boundary. `PersistedOperationWorkspaceRunner` owns the optional managed screenshot identity and atomically ensures the screenshot is persisted, prepares a typed history operation, starts exactly one Provider stream and persists the terminal outcome.
4. SwiftUI views render immutable snapshots and send explicit intents to the session. Tab selection is display-only and never calls the runner.
5. AppKit owns panel/window behavior: the toolbar remains 4 px below and left-aligned to the fixed selection; the result window is movable/resizable and floating. Closing delegates to the session before hiding.

## Persisted operation identity

History schema version 2 adds `operation_kind` and nullable `target_language`. Existing schema version 1 databases migrate in a transaction: all legacy rows are extraction operations, because Tickets 01–05 could only create extraction rows. A prepared attempt records the Provider/model snapshot and exact operation before networking begins.

The screenshot is persisted at most once per workspace. Later operations and reruns reuse the same managed screenshot and create a new operation row. No Provider call occurs until both screenshot persistence and typed operation preparation succeed.

## Slot model

Each operation slot contains two independent layers:

- `committedResult`: the last successfully persisted source/translation output, if any.
- `attempt`: `neverStarted`, `preparing`, `streaming`, `failed`, `canceled`, or `resultPersistenceFailed`.

Streaming deltas belong only to the active attempt. A rerun does not clear `committedResult`; it is replaced only after the new output has been successfully persisted. Failure or cancellation discards partial deltas and keeps the previous committed result.

## User action sequences and terminal behavior

### Select operation

- Switching Extract/Translate changes only `selectedOperation`.
- A never-started slot shows an explanation and explicit Start action.
- A terminal slot shows its committed result or failure/cancel state and explicit Retry/Rerun action.
- Repeatedly clicking a selected tab never starts or restarts work.

### Start, retry or rerun

1. Reject if this workspace already has an attempt or the application gate is held elsewhere.
2. Freeze operation kind, Provider/model and target language for this attempt before the first suspension point.
3. Acquire the global lease.
4. Persist the shared PNG if it has no managed identity.
5. Prepare one typed history row.
6. Start exactly one Provider stream.
7. Append ordered source/translation deltas only to the attempt buffer.
8. Require Provider metadata and completed terminal event.
9. Persist success, then replace `committedResult` and clear the attempt buffer.
10. Release the lease on every terminal path.

### Provider or protocol failure

- Normalize and persist the failure for the new attempt.
- Discard partial source and translation.
- Preserve any previous committed success.
- Do not retry, replace the Provider/model or replay the request.
- Treat both Swift task cancellation and the adapter's normalized cancellation sentinel as cancellation, never as a failed Provider attempt.

### Final persistence failure

- Keep the completed output in memory and expose Copy plus Retry Save.
- Retry Save writes only the terminal database outcome and never calls the Provider again.
- Closing with unsaved completed output requires confirmation; this confirmation UI is part of this ticket.

### Cancel and close

- Explicit Cancel or closing a running result window cancels the stream, persists `canceled`, discards partial deltas and releases the global lease.
- Closing after an ordinary terminal state only hides the window.
- Closing before any operation discards the in-memory screenshot and does not create history.
- If cancellation persistence fails, the UI reports the persistence problem but still releases the global lease; startup recovery later marks the prepared row interrupted.

### Shortcut while active

- During selection/toolbar, a repeated shortcut discards the current in-memory selection and starts a fresh capture.
- During a model attempt, it does not capture; it requests that the current result window be brought forward.
- After an attempt terminates, a new capture may begin even if a result window remains visible.

## Visual contract

- Toolbar: 4 px visible distance from the selection border, left aligned, 3 px container padding and control gaps, 25 px controls, 6 px toolbar/control radius. Extract, Translate, target language, Provider/model and Cancel stay on one row. If the row is wider than the visible screen, its leading edge remains visible.
- Result workspace: centered native segmented control at the top; two cards below, with the original screenshot on the left and current operation result on the right. Extract hides target language; Translate shows it.
- The result card renders never-started, preparing/streaming, success, failure, canceled and result-persistence-failed states. Markdown content is read-only.
- Light/dark colors use semantic SwiftUI/AppKit colors. Icons are centralized SF Symbols, never characters. User-facing strings enter a centralized catalog seam so Ticket 09 can add both localizations without searching view bodies.

## Verification

- Actor behavior tests cover explicit-only starts, one-request invariant, global exclusion, tab switching, cancellation/close, retained success during rerun, failure/cancel partial-output discard and retry-save without networking.
- SQLite tests cover v1→v2 migration and typed operation persistence.
- Rendered harness screenshots verify toolbar geometry and result-window hierarchy in light and dark appearance. Static inspection verifies explicit labels and read-only result text; signed-app keyboard and accessibility behavior remains a Ticket 10 integration gate.
- Signed-app shortcuts, TCC and packaged window behavior remain Ticket 10 integration gates.
