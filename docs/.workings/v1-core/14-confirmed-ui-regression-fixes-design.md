# Ticket 14 — Confirmed UI regression fixes design

## Scope and accepted authority

This ticket restores five already-confirmed production behaviors. It does not introduce a new visual direction, so the accepted onboarding, Provider setup, management-center, history-detail, and menu-panel prototypes remain the visual authority.

1. A Capture click with incomplete permission or Provider setup closes the menu panel and brings the onboarding window to the front.
2. Provider setup is presented from a centered application window, never as a sheet attached to the menu-bar popover.
3. Pasting or typing an API key immediately enables Validate when validation is not already running.
4. Management and Provider navigation surfaces use the accepted light semantic surface instead of the dark under-page material.
5. History detail uses the accepted outer background and bordered detail-card hierarchy.

## Confirmed facts

- `MenuBarContainerView` currently intercepts incomplete Capture routes and attaches Provider or permission sheets to the menu-bar popover. The application model already routes an incomplete `capture()` call to `onShowOnboarding`, and the application delegate already activates and fronts that window.
- A menu-popover sheet inherits the status-item edge as its presentation context, so the 720-point Provider surface can extend beyond the visible screen instead of appearing in the centered onboarding window.
- `ProviderSetupView` reads the Validate state from an external `Binding<String>`. The production binding mutates a plain application-model property and does not publish a SwiftUI observation event, so the field editor can display pasted text while the sibling button keeps its previous disabled state.
- `VLMSnapperTheme.subtleSurface` uses `NSColor.underPageBackgroundColor`. Current light-mode production renders show that semantic color as a dark gray on every sidebar and secondary block; the problem exists without a modal overlay.
- The production history detail is one padded `VStack`. The accepted prototype has a secondary page background and a distinct bordered white detail card.
- Ticket 13 rendering tests only assert that PNG files are nontrivial in size, so they cannot detect wrong color luminance, missing hierarchy, or an edge-anchored presentation path.

## Design

### Unified Capture recovery path

All three `MenuCaptureRoute` values use the menu-panel dismissal coordinator and then invoke the existing Capture callback. Readiness remains owned by `VLMSnapperApplicationModel.capture()`:

- ready → begin capture;
- permission incomplete → show and activate onboarding;
- Provider incomplete → show and activate onboarding.

The menu panel no longer owns Provider or permission sheets. This removes two competing readiness flows and ensures recovery happens in a centered application window.

### Provider key draft

`ProviderSetupView` owns a local API-key draft for the lifetime of one presentation. Text editing updates observable local state, so Validate enablement reacts immediately. Before validation, the view copies the draft into the existing external binding and invokes the existing callback. The draft and external value are cleared when validation advances to model selection/readiness, on Provider change, and on cancellation/completion through the existing container actions.

No key is persisted by the view. Keychain storage and Provider validation behavior remain unchanged.

### Semantic surfaces

The theme replaces the under-page material with an adaptive window-level semantic surface for secondary backgrounds. This is a theme-anchor correction, not a hard-coded light color. It applies consistently to the management sidebar, Provider sidebar, hints, placeholders, and metrics in both appearances.

### History detail hierarchy

The detail column gains:

- a secondary page background;
- one bordered, rounded detail card;
- the existing title/actions, screenshot, original/translation, and metrics inside that card with the accepted spacing.

No history data, actions, selection rules, or fields change.

## Failure modes by user operation

1. User clicks Capture from the menu panel before configuring a Provider: the panel closes, onboarding becomes the frontmost application window, and no Provider sheet is attached to the status item.
2. User clicks Capture without screen permission: the same centered onboarding recovery path is used.
3. User clicks Capture when ready: panel dismissal still completes before capture starts.
4. User pastes an API key: Validate enables immediately without requiring focus loss or another model update.
5. User switches Provider after entering a key: the prior Provider draft does not leak into the new Provider.
6. Validation starts: Validate disables for the in-flight operation and remains single-action.
7. Validation succeeds: the key is cleared and the returned model selector appears below the unchanged key area.
8. User opens Provider configuration from onboarding or Management Center: the setup surface is centered in that application window and remains within the visible window bounds.
9. User opens history or settings in light/dark appearance: navigation and secondary blocks retain readable adaptive contrast without the light-mode dark-gray regression.
10. User selects a history record: the detail content remains scrollable and all existing actions/data are preserved inside the accepted card hierarchy.

## TDD seams and evidence

1. Menu action seam: update `MenuCaptureActionHandler` behavior tests so every route is deferred through the panel-dismissal path; this fails on the current local-sheet routing.
2. Provider draft seam: exercise the public Provider setup input state so a user edit changes `canValidate`, Provider switching clears the draft, and in-flight validation disables the action.
3. Rendered theme seam: render the semantic surfaces under a pinned Aqua appearance and sample independent pixels; fail when the secondary surface is dark in light mode.
4. Pure visual history-card work has no truthful behavior seam in the opaque SwiftUI tree. It is validated by the existing production render harness plus required visual inspection against the accepted prototype, rather than a tautological geometry-constant test.
5. Full bilingual light/dark rendering is rerun from the newly built production views.

## Validation gates

- Each behavioral vertical slice: focused red/green test plus warnings-as-errors build.
- Full strict Swift/C build and complete Swift test suite.
- Named Ticket 13 production renders regenerated from the current branch and visually inspected.
- Focused pixel probe verifies the light semantic secondary surface.
- Localization parity and UI literal scans remain green; no new user-facing copy is expected.
- `git diff --check`, code review, test review, spec/features synchronization, and three-stage final regression.

## Out of scope

- New onboarding steps or copy.
- Provider adapter, model-list, request, retry, or Keychain changes.
- New history fields or editing actions.
- Screenshot annotation or image editing.
