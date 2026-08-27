# Ticket 08 — Design review

## Review outcome

Approved for implementation after the following design-level corrections were incorporated:

1. **Legacy retention safety** — v1/v2 did not store creation time. Treating legacy rows as epoch-old would cause an unexpected first-launch purge, so migration assigns the migration time and documents this conservative exception.
2. **Filesystem/database ordering** — deleting the row first can orphan a PNG that the app can no longer prove it owns. The design deletes a matching managed PNG first and preserves/retries the row if the database step fails.
3. **Mismatch semantics** — a mismatch is not a deletion failure. It proves only that the original is unavailable; the path is untouched while internal history may be removed.
4. **Activity race** — candidate selection alone is insufficient because state can change before deletion. The coordinator rechecks the row at deletion time through the store seam and treats active rows as skipped.
5. **Metric completeness** — usage already exists in Provider terminal metadata but the runner discarded it. The design carries terminal metadata and timings into the atomic terminal update instead of bolting on a later best-effort write.
6. **Scheduler scope** — a persisted last-run timestamp would suppress the explicitly required startup check. The 24-hour gate is process-local after one startup run.

## Rejected alternatives

- SQLite FTS is deferred: v1 data volume and local `LIKE`/`instr` search do not justify a second index/schema synchronization path yet.
- Scanning Pictures to rebuild ownership is rejected by the storage ADR.
- Moving files to Trash or adding undo is rejected by the confirmed permanent-delete behavior.
- Separate History and Settings windows are rejected by the confirmed management-center shell.

## Readiness

The confirmed prototype covers the user-visible information architecture. The design has explicit public seams and testable terminal behavior, so Ticket 08 may enter TDD implementation.
