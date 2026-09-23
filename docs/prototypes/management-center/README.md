# Management center prototype

This page presents the shared management-center shell reached from the menu bar panel.

Confirmed on 2026-08-25 as the v1 management structure.
The capture-retirement and history double-click interaction revision was confirmed on 2026-09-03.

The latest 2026-09-14 revision fills the available desktop with an ordinary
window by default, retaining the menu bar and titlebar controls; it does not
enter a macOS fullscreen Space. The shared sidebar remains 180 pt and the
history list 260 pt; detail takes the remaining width. This supersedes the
earlier fixed default of 1200 × 780 pt, not the supported minimum size.
The minimum-size demo remains 920 × 620 pt of content. The existing Library and
Settings Center groups, counts, and borderless selected navigation stay in place.
The sidebar has no current-Provider summary card; the Provider settings entry remains.
The earlier fixed-window revision was approved and installed in build 31.
On 2026-09-15 the user explicitly requested implementing the top-right Retry
button and its real operation. That entry now runs in the native detail pane;
fill-screen and no-extra-action double-click are now synchronized to the native App; installed-app acceptance remains separate.
Browser automation for that earlier revision was denied by URL policy.
The history-only bilingual revision below was inspected in the in-app browser;
that evidence does not retrospectively validate every settings state.

## Bilingual history preview — 2026-09-23

### Image availability — confirmed 2026-09-23

The user explicitly rejected loading messages after the local-read measurement.
Image selection leaves the existing 100 px bordered image region blank until the
read completes, with no loading text or spinner. Switching records clears the
previous image; completion reveals the selected image or the existing unavailable
message. Rendering the same record, including retry progress, retains its loaded
image. Text remains readable; image preview and Retry require an available image.

The bottom loading/completed/read-failure controls are fixture-only harness controls,
not product buttons. The automatic 900 ms delay only makes switching observable;
it is not a production delay requirement. Actual availability must come from local
reading, ownership/hash validation and image decoding. This UI preview does not
prove that the native first-load bug or Provider retry failure is fixed.

The earlier browser check covered the now-rejected loading message; it does not
serve as acceptance of this revision. Native regression checks distinguish a
pending read from a failed read and cover same-record retention and late results.
The existing theme border/surface and image geometry are unchanged. Provider
request failures are a separate concern and are not solved by image presentation.

The user confirmed continuous paragraphs and linked sentence highlighting in
the standalone bilingual preview. History now uses that same shared reading
surface inside its existing detail card, below the screenshot. Original is on
the left and translation on the right; header and body dividers share the same
column geometry. Hover previews both matching fragments, while click or native
text selection gives the selected pair precedence. Extraction stays single-column.
The history list, filters, screenshot viewer and Retry/Pin/Delete controls remain.

The bottom **Stream preview** control is test-only: synthetic interleaved deltas
fill both columns without API calls or history writes. Switching records or
ending the preview restores the saved fixture, and stale callbacks do not write
into the next record. Paragraph boundaries and correspondence are authored in
the fixtures, not inferred or verified against a model. The standalone page and
history page declare the `bilingual-result` shared block and load its CSS and JS.

Browser checks covered both hosts, bidirectional click/hover, a wrapped sentence's
actual text fragment, extraction, image viewer, replay completion and record
switch isolation, plus English/dark/minimum-window layout. Header/body divider
offset was 0 px at the full and minimum history window sizes. Automated waits
for the full replay twice hit the tool deadline; subsequent page observations
confirmed the completed state. This is not a timing benchmark or native App
acceptance. The user confirmed the integrated composition, copy icons and compact
action spacing on 2026-09-23; native installed-app acceptance remains separate.

Each bilingual column has a 30 × 30 Copy icon button in its heading, using the
existing copy glyph with localized hover text and an accessible action name. Clicking copies
only that column's currently displayed text, preserving paragraph breaks and list
numbers, with brief success/failure feedback beside the unchanged icon. Empty columns disable Copy; during
stream preview Copy takes a snapshot of the text already displayed. Unlike the
mock retry/delete controls, these buttons write the fixture text to the clipboard.

- `#history` opens History with a dedicated content toolbar: left-aligned type filters, right-aligned search, then the history list and detail below.
- History rows retain rounded, separated surfaces: pale blue when selected, pale gray on hover, and selected color wins when both apply. These styles have been synchronized to the native App; installed-app interaction acceptance remains separate.
- The detail header now places three 30 × 30 icon buttons at the upper right, ordered Retry, Pin/Unpin, Delete. Hover or keyboard focus shows a localized tooltip in this prototype; the native App uses the standard macOS help tooltip for Retry. Retry uses a clockwise arrow, changing to a same-size spinner while busy; the other controls do not move. The HTML uses official Lucide SVGs matching the App's SF Symbols semantics, not identical glyph outlines. Pin toggles only the in-memory fixture and updates Pinned; Delete only shows demo feedback and never deletes data. The user requested this Retry entry on 2026-09-15; installed-app hover/click acceptance remains separate from the native rendering checks.
- A single click immediately selects a history row and shows its contents on the right. A double click has no additional action and never opens a separate Result Workspace. The right-hand detail header keeps Retry in its upper-right corner; it remains visible but disabled if the original image is missing or an operation is running. Clicking Retry demonstrates progress in the same pane without real requests or persistence. This supersedes the previously approved history double-click/return flow, not the fresh-capture workspace. The retry demo does not decide persistence semantics or implement real results.
- Starting a new capture excludes VLMSnapper from the frozen frame and hides the Management Center after the new selection overlay is visible; a capture failure leaves it available.
- `#settings` opens the Provider page inside the same shell. Provider cards form a one-open-at-a-time accordion: an explicit destination wins, otherwise the current Provider opens, and DeepSeek is the no-current fallback. The Provider content is centered at a maximum width of 850 pt; card headers are at least 54 pt high, Provider marks are 29 × 29 pt, and credential/model controls are 32 pt high. Credential and model controls share a row when space permits and stack at narrow widths. The expanded card directly owns API Key validation, model refresh and selection, current-Provider switching, and configuration removal; no separate setup window is involved. The API Key remains in a secure field with clear and reveal controls, while the field heading carries its configuration status. Validation appears as a separate action only when the Key needs verification. An accepted replacement retires the old credential without rollback, while a refreshed model list keeps the previous model only when it still exists.
- Opening Provider settings from onboarding carries a navigation origin. Successful model selection returns automatically to onboarding; closing early also returns without inventing a completed state.
- `#general` opens General Settings. The application section includes a compact 150 × 28 key-recording control for the customizable capture shortcut; it is not a text field. Confirmed on 2026-08-27, direction A keeps update checking and update state inline here instead of adding a separate Update destination. Updates are never downloaded automatically: the user starts the download, updater callbacks drive the downloading and downloaded states, and a completed download remains non-modal, installs on quit by default, and exposes one emphasized immediate-restart action.

The theme and state controls are prototype harness UI and are not part of the product design. Real update state comes from the updater lifecycle. Retry's demo models placement and busy feedback only: real Provider readiness, file validation, persistence-failure recovery and deletion protection follow v1-core::REQ-002/AC-07–09 in the specification. Native Retry rendering has been inspected; installed-app hover/click acceptance is still required.

Provider layout and control placement remain confirmed. The old API Key demo script is no longer authoritative for whitespace normalization, exact-value reversion, load/submission identity, replacement admission or close/reopen lifetime: those interaction rules evolved in the current v1 specification, User Story 7 and Failure Modes 28–46. In particular, replacement is accepted only after retirement can be recorded durably; rejection before admission sends no request and preserves the original saved configuration. The Provider demo controls carry this scoped invalidation notice; this does not invalidate the rest of the page or authorize a visual redesign.

The Recovering and Read Error demo controls represent read-only recovery and storage-read failure. Neither offers Validate; collapse/reopen is the read-error retry entry. A storage-write failure remains editable, and clearing its candidate leaves the existing validation action visible but disabled. On 2026-09-07 the user accepted the synchronized recovery/read-error demo against the manual checklist, including read-only controls, absence of Validate, and light/dark readability and layout. Automated browser preview was denied by URL policy and is not claimed; native production renders and installed-app recovery remain separate evidence.
