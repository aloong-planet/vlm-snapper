# Provider setup sheet directions

This prototype compares three attached-sheet structures for configuring an online Provider from the selected single-page onboarding checklist.

All variants share the confirmed product flow: choose a built-in Provider, validate its API Key, fetch the complete model list, optionally leave in the pending-model state, select one current model, close the attached sheet, and return to onboarding with explicit Provider and model details. Cancel and close also return to onboarding without inventing a completed state. The prototype never sends or persists the mock API Key.

In the single-column and split-pane directions, successful API Key validation keeps the credential section visible and reveals the model selector directly below it. At narrow widths, the model selector and refresh action share one control row, while Provider mark boxes keep a fixed 24 px geometry.

The attached modal uses an 8 px corner radius on all four corners.

- Direction A: single-column sequential form.
- Direction B: Provider sidebar plus reusable detail pane.
- Direction C: two-step progressive setup.

The bottom dark control is demonstration infrastructure rather than product UI. It switches layout, mock lifecycle state, and theme.
