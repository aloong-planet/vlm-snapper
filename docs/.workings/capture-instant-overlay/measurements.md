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

## On-screen latency and the window-open animation (2026-10-28, after user feedback)

Correction: the 4-11 ms figures above are main-thread time of `presentPending`
only. They are not the time until the overlay is visible. Visible timing is
measured below from the composited display.

Method: a scratch program records the main display with an `SCStream` (half
resolution, up to 120 fps, idle frames skipped), posts the installed app's
capture shortcut (Command-Shift-F) through the HID event tap, then Esc. Per
frame it compares a 22 x 14 grid including 1 px edge points with the frame
before the shortcut; a point counts as covered when its luma falls below 75 %
of the baseline. Times are frame presentation timestamps minus the time the
shortcut was posted, so they include hotkey delivery, admission, window
server composition and one or more display refreshes. App switched with a
normal quit between versions.

| Installed build | First overlay frame (5 runs) | Full coverage | Partial frames before full |
|---|---|---|---|
| 0.1.1 (freeze first, PR #34 base) | 574, none, 480, 278, 321 ms | 753, none, 547, 349, none ms | 4, 0, 6, 5, 3 |
| 0.1.2 (pending overlay, default window animation) | 126, 97, 120, 104, 99 ms | 193, 155, 166, 250, 228 ms | 4, 4, 3, 3, 4 |
| 0.1.3 (pending overlay, `animationBehavior = .none`) | 161, 91, 132, 88, 82 ms | same frame | 0, 0, 0, 0, 0 |

"none" means no covered frame within 1 s in that run (not investigated; old
build only). The partial frames come from AppKit's default window-open
animation: in a single-capture frame dump of 0.1.2 the dimmed area spanned
x 7-748 of 0-755, then 5-750, then 4-751 over successive frames (edge coverage
0 %, 17 %, 33 %), the same growth reproduced in process with the production
controller (6-749, 5-750, 3-752) and absent after the fix in 3 of 3 runs
(first frame 0-755 with 100 % edge coverage). The old build shows partial
frames too: the animation predates this change, but over an opaque frozen
screenshot it was less visible than over the live screen.

In-process variants recorded the same way (3 rounds, first covered frame after
the call): production `presentPending` (new panels with the overlay view) 69,
55, 72 ms; a new plain panel 58, 48, 47 ms; a reused plain panel 36, 40, 49 ms.
Reuse was 15-33 ms earlier than the production path and -2 to 22 ms earlier
than a new plain panel, within the run-to-run spread; see ADR-0013 option 6. Both in-process variants ran with the default
animation (the scratch helper took an optional behavior, so `.none` there was
`nil`); the comparison is like for like, and its 2 % inset grid did not reach
the edges where the animation shows.

In-process observables during the default animation (scratch probe polling
every 4 ms for 350 ms after `orderFrontRegardless`): `NSWindow.frame` and the
window-server bounds from `CGWindowListCopyWindowInfo` equal the full screen
(0, 0, 1512, 982) from the first sample; window alpha is 1. The shrink exists
only in composited frames, so the regression test asserts the overlay
windows' `animationBehavior`.
