# Menu Panel Polish Code Review

## Scope

- `MenuBarPanelController` panel hosting, placement, and dismissal
- `MenuBarPanelView` compact capture action styling
- semantic theme color addition

## Findings resolved

1. Vertical clamping could have moved an unusually tall panel back over the menu bar. Placement now preserves the top edge below the menu bar even if the bottom would extend beyond the screen.
2. A failed status-item geometry lookup could have shown the panel at a stale origin. `show()` now requires successful placement before ordering the panel front.
3. The Capture shadow was initially placed before clipping and could be clipped away. The shadow now follows the rounded clip.

## Open findings

None.

## Scope guard

The change does not alter capture routing, Provider readiness, update behavior, history data, localization strings, or the right-click Quit menu.
