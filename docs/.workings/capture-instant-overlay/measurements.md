# Instant capture overlay measurements

Date: 2026-10-28. Machine: Apple M1 Pro, one built-in 3024 x 1964 Retina
display (1512 x 982 points), macOS 26.0.1. Toolchain: Xcode toolchain,
Swift 6.2.3, release builds.

## Method

A scratch executable (outside the repository) linked the production
`VLMSnapperCore` and `VLMSnapperUI` library products through a local package
dependency, once against `850f64d` (`origin/main`) and once against this
branch. Each run owned a status item and a small titled window, because the
production capturer fails closed unless the current process is a shareable
application (as the real app always is). One unmeasured capture warmed the
process, then three rounds ran two seconds apart.

- `main`: trigger -> `ScreenCaptureKitFrozenDisplayCapturer.captureFrozenDisplays()`
  -> `FrozenCaptureOverlayController.replace(...)` -> `CATransaction.flush()`.
- branch: trigger -> `presentPending(...)` (overlay ordered on screen) ->
  `captureFrozenDisplays()` -> `commit(displays:)` -> `CATransaction.flush()`.

Times are main-thread wall-clock from the trigger; the compositor adds up to
one display refresh in both cases. The application's admission hops (actor
calls before `beginCapture`) are identical in both versions and not included.

## Results

| Round | `main`: overlay first visible | branch: overlay visible (`presentPending`) | branch: frame frozen | branch: frozen frame committed |
|---|---|---|---|---|
| 0 | 325.4 ms (freeze 134.3 ms) | 10.3 ms | 120.2 ms | 145.8 ms |
| 1 | 164.8 ms (freeze 111.2 ms) | 11.1 ms | 155.6 ms | 180.5 ms |
| 2 | 160.7 ms (freeze 108.8 ms) | 4.1 ms | 116.1 ms | 140.0 ms |

- Dragging a selection on a committed overlay: 120 drag events with display
  and flush after each took 3.26 ms in total (0.027 ms per event); the frozen
  frame is layer contents and is not redrawn.
- Exclusion while the pending overlay is visible: mean luma of a 64 x 64
  downsample of the frame frozen under the visible 48 % scrim was 236.4-236.8,
  against 236.9 for a reference freeze without any overlay. A leaked scrim
  would read about 123. The production filter (current process excluded) keeps
  the pending overlay out of real frames on this system.

## Rendering check

Screenshots taken with `/usr/sbin/screencapture` during the branch run (not
stored; they contain unrelated personal screen content):

- Pending overlay: the whole display, including the menu bar, dimmed by the
  existing scrim over the live screen; no added element.
- Committed overlay after a programmatic drag: frozen frame dimmed outside the
  rectangle, undimmed inside it with content continuous across the edge, and
  the 1 pt accent border on the edge; same appearance as the previous
  `draw(_:)` implementation.
