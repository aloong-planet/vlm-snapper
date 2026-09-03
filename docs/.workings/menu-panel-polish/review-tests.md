# Menu Panel Polish Test Review

## Tests retained

- Confirmed geometry fixes the width at 300 points and the arrow at 8 by 4 points.
- Placement covers right-edge clamping, arrow clamping, exact menu-bar separation, and an unusually tall panel.
- Dismissal routing covers the panel window, the status-item hit rectangle, blank space in the status-item window, and another application window.
- Existing full-row click and hover-response tests continue to cover action hit targets.
- Production rendering covers Simplified Chinese and English in light and dark appearances at 300 points.

## False-green risk resolved

The first dismissal test accepted a preclassified target and therefore could not detect broken event-window or coordinate classification. It was replaced with event window numbers, mouse coordinates, and the real status-item hit rectangle contract.

## Remaining manual acceptance

The signed local application should still be used to confirm AppKit event-monitor delivery when clicking another application or the desktop. Unit tests cover the deterministic classification and lifecycle code but do not synthesize a cross-process global mouse event.
