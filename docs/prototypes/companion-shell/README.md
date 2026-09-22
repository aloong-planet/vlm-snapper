# Menu bar entry prototype

This page presents the requested menu-bar-first entry surface. The footer's left
Provider action opens Provider configuration; its right Settings action opens
General Settings inside the shared management-center shell. History remains a
destination in the management-center sidebar, not a footer action.

Updated on 2026-09-16: the menu shows up to five most recent records. If fewer
than five exist, it shows only those records, without empty placeholder rows.
The panel grows vertically while preserving its 300-point width and row styling;
the full management-center history list is not limited to five records.

The footer labels, destinations and destination-only sidebar selection were
confirmed on 2026-09-14 with the request to synchronize the App. Prototype
approval does not substitute for native interaction or installed-app acceptance.

Confirmed on 2026-08-25 as the v1 entry structure.

Confirmed on 2026-08-27, direction A adds a small menu-bar status dot and an inline, non-modal notice below the capture action when an update is available. Updates are never downloaded automatically: the user starts the download, the notice changes to downloading, and only updater completion changes it to downloaded. The downloaded notice says the update installs on quit and links to General Settings; it does not compete with capture as the primary menu action.

Selected on 2026-08-31: a left click opens or closes the existing panel, which contains no Quit action. A right click opens a native-style context menu containing only Quit VLMSnapper.

The entry-surface, theme, and update-state controls are prototype harness UI and are not part of the product design. Real click routing comes from the status-item button and real update state comes from Sparkle.
