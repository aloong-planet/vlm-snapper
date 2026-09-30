# Update status copy cleanup — 2026-09-30

Scope: remove the duplicated automatic-update explanation boxed in the user's screenshot. Keep the switch hint, status heading/actions and useful download/install/failure details. Reference commit: `850f64d01641922f6b2ece6458a121081a823789` plus existing uncommitted work, which is preserved on the current feature branch.

- [x] Inspect the production view, localized strings and management-center prototype.
- [x] Remove the repeated hint from idle/current/checking; omit the absent text view rather than render an empty line.
- [x] Review code independently (review-code.md).
- [x] Review validation independently (review-tests.md).
- [x] Render and inspect current production UI in Chinese/English, light/dark.
- [x] Sync the update-copy requirement in spec and features; cross-check prototype.
- [x] Complete offline regression and signed local installation: 0.1.0 (50), verified and launched.

This is a pure-copy removal under the to-spec prototype exception, not a new state or layout. The prototype already keeps the automatic-check explanation only under its switch, so no prototype edit is needed. Pure UI text deletion does not add a new algorithmic seam; TDD is exempted, with existing production rendering and regression used instead. No paid model requests, update-service requests or user-data cleanup are authorized by this change.

## Follow-up: compact spacing — 2026-09-30

User requested reduced spacing after the copy removal, prototype synchronization, and no tests. Prototype current/checking states now use one line, 52px minimum row height (previously 88px), 8px vertical padding (previously 13px), and no title bottom margin. Other state heights/details are unchanged. This spacing change is awaiting the prototype confirmation gate; App code and installed build 50 are unchanged in this follow-up. No tests were run. Browser visual inspection was blocked by the file-URL security policy; user preview is required, and no rendered geometry claim is made.
