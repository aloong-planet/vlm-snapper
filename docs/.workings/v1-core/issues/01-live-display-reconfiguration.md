# Live display reconfiguration during selection

Status: ready-for-agent

Blocked by: none

## Problem

`CaptureSelectionSession.applyCurrentDisplayGeometries(_:)` can invalidate one frozen display without canceling the others, but production code does not currently call it. A display resolution, scale, rotation, connection, or sleep change is therefore detected only when the user finishes a selection on that display.

## Impact

The frozen frame remains visible until mouse-up instead of becoming unavailable immediately as required by the accepted capture specification. The selected display is still rejected before cropping when its geometry no longer matches, so this does not cause the Retina downsampling defect fixed separately.

## Recommendation

Connect the existing session interface to a CoreGraphics display-reconfiguration observer. Refresh the complete active-display geometry set after a relevant callback, invalidate only changed or disconnected frozen displays, and remove the observer when capture completes or is canceled.

## Acceptance

- A changed or disconnected display becomes unavailable during selection without waiting for mouse-up.
- Other unchanged frozen displays remain selectable.
- A newly connected display is ignored until the next capture.
- Completion and cancellation release the observer.

## Comments

- Recorded while reviewing the Retina frozen-capture repair. Kept separate because it predates and does not cause the downsampling bug.
