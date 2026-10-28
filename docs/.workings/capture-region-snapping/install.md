# Local install and installed-build checks — 2026-10-28

- Installed `/Applications/VLMSnapper.app` 0.1.4 (arm64, Developer ID `RHQ28XS7D9`), executable SHA-256
  `03884701741edde53fecd715835608e2d8f8a390d79e1c6868d3afb05ffe577b`, overwritten in place without a backup
  (project install preference); the existing 0.1.1 backup was left as is. Signed and verified with
  `Scripts/sign-developer-id-app.sh`; Keychain smoke test passed.
- Contents: this branch at `48610ef` (product code identical to `b2085e3`: `git diff --stat 48610ef..HEAD --
  Sources VLMSnapper Package.swift Package.resolved Scripts Distribution` is empty) plus a local merge of the
  open PR #34 branch `codex/extraction-to-translation` (`a4758c0`), so saved-text translation stays
  available; the two documentation conflicts were resolved with this branch's text.

## Installed-build checks (probe `logs/installed-snap-probe.swift`)

Real shortcut and real pointer moves (HID events), composited screenshots compared with a baseline taken
before the shortcut (luma ratio; the overlay dims to about 0.52):

| Pointer over | Inside the expected region | Outside it | Result |
|---|---|---|---|
| Topmost window (Google Chrome, 0, 34, 1512, 898) | 1.00 | 0.54 (menu bar) | snapped to the whole window |
| Menu bar status item (894, 0, 32, 33) | 1.00 | 0.54 (menu bar elsewhere) | snapped to the item |
| Dock strip (pointer at the bottom centre; sampled at its far left) | 1.00 | 0.52 (screen middle) | snapped to the whole strip |

A click on the window opened the toolbar at x 0 (the window's left edge); the window fills the screen, so
the existing placement put the toolbar at the top of the visible area. Esc closed the capture.

This confirms the real window list in the signed sandboxed app (ADR-0014's open premise), the real menu bar
and Dock geometry, and hover from real pointer movement. Hover latency was not measured below the 250 ms
sampling interval.

Not checked here (deferred acceptance, needs the user): the visible frame with an auto-hidden Dock (needs
changing the user's Dock setting), and two displays (one display connected).
