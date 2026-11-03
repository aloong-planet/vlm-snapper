# Capture result box

## Question

Once Extract or Translate starts, does showing the streamed result in a box on the capture overlay look and behave right? This page covers the box's place, anatomy and states, and how the toolbar works alongside it.

- The box is a read-only text panel, independent of the selection. It sits at the right edge of the selection's display, 12 pt in, top-aligned below the menu bar, 380 pt wide and up to 640 pt tall. Its header drags it within the display.
- The Extract box shows the source text. The Translate box shows only the translation, and its title names the target language.
- Translate and its target language are one control: one outline with a divider between the two parts. The left part runs the translation and the right part opens the language list. The language has no icon.
- The control shows the language's abbreviation, the uppercase primary language code such as ZH or EN, with the full name as its tooltip. Each row in the list leads with the abbreviation and follows it with the language name, and the search matches either. The Translate box's title keeps the full name.
- The current Provider and model appear in the box header, between the title and the buttons, cut short with an ellipsis when they do not fit; the full name is the tooltip. The toolbar does not show them.
- While a request runs, a spinner sits before the model in the header. While the request is being prepared, the box body says so.
- One box shows at a time. Pressing the other operation switches to it: an operation with a result only shows that result again, and one never run starts a request.
- The selection locks when an operation starts: the handles go away and presses outside it do nothing.
- While a request runs, the other operation, Copy and Save are disabled. The target language can still change and affects the next press only.
- While a result is unsaved, an operation that would send a request is disabled, including Translate after the language changes. Switching to an operation that already has a result still works.
- Changing the target language and pressing Translate again is a new translation with its own history record. Retry keeps the record and its language.
- The box's close button closes only the box, and closing it during a request cancels the request. Pressing the operation again shows the latest state without sending a request.
- Escape or the toolbar's cancel button leaves capture and closes the box, canceling a running request. An unsaved result asks for confirmation first.
- An open box moves the toolbar to its left when they would overlap, so every toolbar button stays reachable. Closing the box puts the toolbar back. Dragging the box does not move the toolbar, and the toolbar stays on top.
- While text streams, the box follows the end unless the reader has scrolled up, and appended text keeps the current text selection.

## Structure basis

- The right-edge placement, one box at a time, a translation-only Translate box and a draggable header are the confirmed direction for this page.
- The selection look, handles and toolbar are from the confirmed capture overlay pages and use the shared toolbar. The current-operation and disabled toolbar states are new here.
- The box's header buttons reuse the toolbar's icon button. Retry draws the clockwise arrow the app uses for retry in history.
- Strings reuse the app's existing wording where it has one. The no-text message is new.

## Demo scaffolding

Not part of the design; do not implement.

- The floating bar marked `data-demo-harness`: the next request's result, the selection preset and Start over.
- The Selection presets replace drawing a selection, so the handles shown before an operation starts are not draggable on this page. The capture snap region page covers adjusting a selection.
- The target-language list holds a sample of the app's list, including its longest abbreviation length and longest name.
- Streaming speed and sample text are mock data. The mock window is drawn from the same extracted text, and every selection preset contains all of it.

## Uncovered dimensions

- Interface language: only Simplified Chinese is drawn. Longer English labels are not tested in the box header.
- Appearance: only light is drawn. The page uses the shared tokens, which also define dark.
- Multiple displays: only one is drawn. Other displays keep their overlay until capture ends.
