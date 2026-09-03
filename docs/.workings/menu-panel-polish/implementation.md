# Menu Panel Polish Implementation

## Confirmed behavior

- The status-item panel is 300 points wide.
- Its complete frame stays below the menu bar and inside the current screen horizontally.
- An 8-by-4-point arrow points at the status item.
- Clicking outside the panel and status item dismisses the panel.
- Capture uses a white raised surface with a weak border, centered dark text, and a fixed gray 12-point shortcut.
- Hover changes the surface without moving the button.

## Implementation seam

`MenuBarPanelPlacement` owns screen-relative geometry and `MenuBarPanelDismissalRouter` owns click routing. `MenuBarPanelController` uses a nonactivating transparent `NSPanel` because `NSPopover` does not expose the arrow geometry required by the confirmed prototype.
