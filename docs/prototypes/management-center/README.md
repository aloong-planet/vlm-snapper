# Management center prototype

This page presents the shared management-center shell reached from the menu bar panel.

Confirmed on 2026-08-25 as the v1 management structure.
The capture-retirement and history double-click interaction revision was confirmed on 2026-09-03.

- `#history` opens History with a dedicated content toolbar: left-aligned type filters, right-aligned search, then the history list and detail below.
- A single click selects a history row. A double click on the full row opens that saved operation in the Result Workspace without starting a Provider request; the Management Center yields to the Result Workspace.
- Starting a new capture hides the Management Center before the display frame is frozen, so the window is not included in the captured frame.
- `#settings` opens the Provider page inside the same shell.
- `#general` opens General Settings. The application section includes a compact 150 × 28 key-recording control for the customizable capture shortcut; it is not a text field. Confirmed on 2026-08-27, direction A keeps update checking and update state inline here instead of adding a separate Update destination. Updates are never downloaded automatically: the user starts the download, updater callbacks drive the downloading and downloaded states, and a completed download remains non-modal, installs on quit by default, and exposes one emphasized immediate-restart action.

The theme and update-state controls are prototype harness UI and are not part of the product design. Real state comes from the updater lifecycle.
