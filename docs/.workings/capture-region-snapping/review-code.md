# Capture region snapping — code review

No ticket (`/to-tickets` no-ticket entry). Date 2026-10-28. Scope: `8c00b2d..e91ba54` plus the two fixes
below (uncommitted at the time of review, committed with this record): the snap-region resolver, the
CoreGraphics window-list adapter, overlay controller and view changes, application model wiring.

## Underlying premises

- The window list is ordered front to back and gives bounds in global top-left coordinates with the
  owner PID, layer, alpha and on-screen flag: observed in the 2026-10-28 probe on this machine (52 windows,
  18 ms), which the resolver fixtures copy.
- The Dock is one layer-20 window covering the display, and its strip equals the display frame minus
  the visible frame on its side: observed (bottom 48 pt; the Dock's items sit at y 931–972).
- `CGWindowListCopyWindowInfo` is usable from a sandboxed app: Apple DTS recommends it as the
  alternative to the Accessibility API for sandboxed apps (forum 794253). Not yet observed in the signed
  sandboxed build — verified on the installed app before delivery.
- A synthetic mouse-moved event sent to the panel reaches the view (controller hover test passes);
  physical movement on other displays relies on the `.activeAlways` tracking area — installed-build check.
- New comments: "Listing takes tens of milliseconds" (measured 18 ms) is a verified cause. "A release far
  from the press is a drag even when no drag event arrived" states the behaviour that keeps an existing
  press-and-release pair a drag; corrected 2026-10-28 after the post-implementation check (finding 2): no
  earlier test sent such a pair, `farReleaseWithoutDragEventsDrags` now drives it. No finding.

## Runnability

States and paths enumerated for the view: awaiting/ready/unavailable window list × hover, press,
drag, click, settled; frame before/after; rollback, abandon, close, display invalidation.

1. **Bug, fixed (same-layer escape).** The controller gave a window list to pending *and* current
   panels. During a replacement, the current panels belong to the previous capture; if the new freeze
   then failed, the restored overlay snapped with the newer list, which no longer matches its frozen
   frame (CONTEXT invariant). Fix: the list goes to the pending overlay if there is one, otherwise to
   the current one. Test "a replacement's window list does not reach the overlay it may roll back to"
   was red first (`logs/snap-rollback-red.log`: the restored overlay selected the replacement's window
   (600, 682, 300, 200)), green after (`logs/snap-rollback-green.log`).
2. **Bug, fixed (same-layer escape).** The model accepted a list while `activeCaptureGeneration` matched,
   which stays the previous capture's until a replacement commits; a late list of the previous capture
   then landed on the replacement's pending overlay. Fix: hand a list over only while its request owns the
   newest overlay (its pending request, or the committed one with no newer request). Test
   `lateWindowListOfReplacedCaptureIsIgnored` was red first (`logs/snap-late-red.log`: toolbar at +200,
   the earlier capture's window), green after (`logs/snap-late-green.log`, App suite 35 tests).
   Class check — every path that hands per-capture data to overlay panels: `commit` (frames, pending
   panels only, unchanged), `attachSnapRegions` (fixed in 1), and the model's two callers that deliver
   capture results (`beginCapture` frames under `ownsRequest`, unchanged; `attachSnapRegions`, fixed here).
   Two instances, both fixed.
- Remaining paths checked without finding: list after abandon/Esc (request cleared → ignored); list
  `nil` (click is an empty selection as before, drag unchanged); click before list then list `nil`
  (empty selection); click before frames (completed-before-frame path); retain cycle (the view's
  closure holds the panel weakly); `mouseExited` clears hover when the pointer leaves a display.

## Security

No window titles are read; nothing new is stored or logged; own windows are excluded by PID so
VLMSnapper's interfaces never become regions; no new permission. No finding.

## Consistency

- A press moved 3 pt or less was a tiny drag (rejected as too small); it is now a click on the snap
  region — the change v1-core::REQ-006/AC-07 asks for. Drags past 3 pt and down/up pairs without drag
  events keep their old result.
- Smells: none hit in the changed code. The view grew a second selection source; both feed the one
  `selectionRect` and `complete` path rather than duplicating finish logic.

## Refactoring list

None.
