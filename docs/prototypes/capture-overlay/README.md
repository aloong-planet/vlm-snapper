# Capture overlay toolbar prototype

This prototype captures the confirmed v1 post-selection toolbar structure.

- The toolbar is attached below the selection and left-aligned with it.
- The toolbar has a 4 px visible gap below the selection border, uses 3 px inner padding and gaps, and contains 25 px-high controls with a 6 px corner radius.
- Text Extraction, Translation, target language, Provider/model, and cancel remain visible in one row.

Confirmed on 2026-08-25. The theme control is prototype harness UI and is not part of the product design.

Superseded on 2026-10-28 for the selection itself: the user made the shipped app the reference, so the selection has a 1 px border and no corner handles, size label or inner hairline. The toolbar conclusions above still hold.

## Snap region (`prototype-snap-region.html`)

Before anything is dragged, the overlay highlights the snap region under the pointer with the selection look: the whole topmost window (never an element inside it), a single menu bar status icon or the rest of the menu bar, the Dock strip as one region (no single icons: the app stays sandboxed), and the whole display over the desktop. A click (3 px or less of movement) selects the highlighted region and shows the shared toolbar; moving further draws a manual rectangle. Confirmed by the user on 2026-10-28. The colour tokens and the toolbar are shared with the attached-toolbar page through `_shared/capture-overlay.css` and `_shared/capture-toolbar.js`.

## Confirmed selection, Copy and Save (2026-10-29)

Confirmed by the user: a confirmed selection shows small handles at its four corners and four edge midpoints; dragging a handle resizes, dragging inside moves, a press outside starts a new selection, and the toolbar follows. The toolbar has icon buttons Copy (the app's copy icon) and Save (a floppy disk, chosen by the user; SF Symbols has none, so it is Lucide's save icon) before Close; Copy and Save close the capture, Save first opening the system save panel.

