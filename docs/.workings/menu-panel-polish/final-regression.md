# Menu Panel Polish Final Regression

## Confirmed behavior

| Requirement | Implementation | Verification |
| --- | --- | --- |
| Panel stays below the menu bar | Screen-relative top edge in `MenuBarPanelPlacement` | Placement tests, including tall content |
| Smaller arrow | 8-by-4-point `MenuBarPanelArrow` | Metrics test and four production renders |
| 300-point width | Shared `MenuBarPanelMetrics.width` | Metrics test and four production renders |
| Click outside closes | Local and global AppKit mouse monitors | Event window and coordinate routing tests |
| White raised Capture button | Semantic surface, weak border, and shadow | Light and dark production renders |
| No hover movement | Hover changes only background opacity | Action-role test and implementation review |
| Centered dark title and gray shortcut | ZStack title plus trailing 12-point shortcut | Four production renders |

## Cross-document check

- `docs/specs/v1-core.md` records geometry, dismissal, and button styling.
- `docs/features/v1-core.md` describes the current user-visible behavior.
- `CONTEXT.md` preserves the menu panel relationship and entry semantics.
- The confirmed companion-shell prototype matches the production constants and styling.
- No localization dictionary changed because no visible string was added or changed.

## Verification

- Targeted interaction, geometry, and action tests pass.
- Production surfaces render in Simplified Chinese and English, light and dark.
- Full Swift test suite passes.
- `git diff --check` passes.
