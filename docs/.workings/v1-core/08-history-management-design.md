# Ticket 08 — History management and cleanup design

## Scope and confirmed UI direction

Ticket 08 implements the confirmed `management-center` prototype: one shared window shell, History and Settings destinations, a History content toolbar with left-aligned operation filters and right-aligned local search, then a list/detail split below. The menu bar History action opens this window on History; Settings opens the same window on Settings; a recent item opens History with that record selected.

The first implementation keeps Provider settings behind the existing Provider setup content. General settings owns retention. No screenshot annotation, result editing, history synchronization, custom retention, or custom storage path is introduced.

## Data model and migration

SQLite schema v3 adds these operation columns:

- `created_at`: Unix seconds captured when the prepared record is created. Retention never changes it when a record is viewed or rerun.
- `is_pinned`: integer boolean, default false.
- `first_text_latency_ms` and `total_latency_ms`: nullable non-negative integer milliseconds.
- `input_tokens`, `output_tokens`, and `total_tokens`: nullable integers saved only when the Provider reports usage.

Existing v1/v2 rows migrate conservatively: their `created_at` becomes the migration time so installing the version cannot immediately erase legacy history whose exact creation time was never stored. Existing rows start unpinned and have unavailable metrics. The store exposes typed history query, count, pin, and record-deletion APIs; callers never construct SQL fragments.

## Query and presentation seam

`HistoryQuery` is the public behavior seam. It combines:

- operation kind: all, extract, or translate;
- optional terminal status, Provider, model, target language, date interval, and pinned state;
- a source/translation search string, matched case-insensitively and locally;
- stable newest-first ordering with ID as the tie-breaker.

`HistoryRecord` contains the persisted operation, creation date, pinned state, and optional performance/usage. The detail layer checks the managed screenshot through `ManagedScreenshotLoading`; missing or mismatched files are shown as unavailable while text and metadata remain usable.

## Metrics seam

`PersistedOperationWorkspaceRunner` owns an injected wall clock. Timing starts when `run` is invoked, before screenshot persistence. The first non-empty source or translation delta captures first-text latency once. Every terminal success, failure, or cancellation captures total latency. Completed Provider metadata supplies usage; the app never estimates absent usage. Metrics are written with the terminal state in the same database update.

## Deletion ownership and ordering

All manual deletion, clear-history, retention changes, and automatic cleanup call one `HistoryDeletionCoordinator`:

1. Resolve candidates from the database and skip active states (`preparing`, `uploading`, `streaming`).
2. Pinned candidates are excluded unless the user explicitly authorized including them; automatic cleanup never authorizes them.
3. Ask `ScreenshotPersisting.discardIfOwned` to delete the file first. It may delete only a regular file under the managed year-month directory whose current SHA-256 matches history.
4. A missing file or ownership mismatch means the original screenshot is unavailable; do not touch the path and delete only the internal record.
5. Any other file deletion failure preserves the internal record so the user can retry.
6. After a file is deleted, delete the database record. If that database write fails, preserve/report the record; a later retry sees a missing file and can finish internal deletion.
7. Remove a year-month directory only when it is safe and completely empty. Never remove the VLMSnapper root.

Batch execution continues after individual failures and reports deleted, failed, and skipped counts. There is no Trash move and no undo state.

## Retention and scheduling

`RetentionPolicyStore` accepts only 7, 30, 60, 90, or 180 days and defaults to 30. `HistoryCleanupCoordinator` queries records older than `now - retention`, excluding pinned and active records.

An app-process scheduler runs cleanup once after startup. While the same process remains alive it permits another automatic run no more often than every 24 hours. A shorter retention selection first computes the deletable count; only user confirmation saves the new value and immediately cleans. Cancel preserves the old value. A longer value saves without cleaning.

Automatic failures are non-modal. The latest summary drives a History warning marker and the History page retry-cleanup action.

## User-operation failure matrix

1. Search/filter yields no rows: show the confirmed empty state; do not alter selection or data.
2. Selected screenshot was moved or deleted: keep text and metadata; disable image-dependent actions.
3. Selected path now contains different bytes or a symlink: never display, upload, overwrite, or delete it.
4. User deletes an active row: deletion is disabled; batch operations count it as skipped and never cancel the request.
5. User deletes a pinned row: require explicit confirmation before the coordinator receives pinned authorization.
6. Matching PNG deletion fails: preserve the database row, continue a batch, and report failure.
7. PNG is absent or mismatched: leave the filesystem untouched and remove only the internal row.
8. Database deletion fails after PNG deletion: keep/report the row; retry safely completes internal deletion.
9. Clear history partially fails: do not roll back successes; report exact deleted, failed, and skipped counts.
10. Retention is shortened then confirmation is canceled: save nothing and run no cleanup.
11. Automatic cleanup fails: show no modal or notification; retain failed rows for the next scheduled/manual retry.
12. A record is active at cleanup time and finishes immediately afterward: keep it until the next normal cleanup check.

## Validation gates

- TDD at the public SQLite query/mutation seam, deletion coordinator seam, retention/scheduler seam, and operation-runner event seam.
- Strict Swift build and the real full Swift Testing total.
- Migration coverage from schema v1 and v2 plus newer-schema blocking.
- Behavioral mutation checks for hash mismatch, active skipping, pinned exclusion, partial failure continuation, and 24-hour gating.
- Light/dark rendered management-center images, including history, settings, empty results, and cleanup failure state; compare toolbar alignment and shell structure with the confirmed prototype.
- Localization-key parity and source/comment English scans.
