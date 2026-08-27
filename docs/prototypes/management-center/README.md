# Management center prototype

This page presents the shared management-center shell reached from the menu bar panel.

Confirmed on 2026-08-25 as the v1 management structure.

- `#history` opens History with a dedicated content toolbar: left-aligned type filters, right-aligned search, then the history list and detail below.
- `#settings` opens the Provider page inside the same shell.
- `#general` opens General Settings. Confirmed on 2026-08-27, direction A keeps update checking and update state inline here instead of adding a separate Update destination. Updates are never downloaded automatically: the user starts the download, updater callbacks drive the downloading and downloaded states, and a completed download remains non-modal, installs on quit by default, and exposes one emphasized immediate-restart action.

The theme and update-state controls are prototype harness UI and are not part of the product design. Real state comes from the updater lifecycle.
