# Ticket 15 — Production regression follow-up design

## Scope and visual authority

This ticket restores three behaviors already required by the confirmed prototypes and `docs/specs/v1-core.md`. No visual decision changes, so no new prototype is needed.

1. An incomplete Capture action must close the menu panel, then bring onboarding to the front.
2. Provider validation must explain authentication rejection rather than claiming temporary unavailability.
3. The management center must preserve its complete header and body at the supported minimum size.

## Confirmed facts

- The menu action enters `VLMSnapperApplicationModel.capture()` only from `MenuBarPanelDismissalCoordinator.panelDidClose()`. That callback invokes the pending action synchronously. `showOnboarding()` then orders the window before activating the accessory application, leaving presentation in the same close transaction and vulnerable to activation-order competition.
- The installed application reached `api.openai.com`, completed TLS, received HTTP 401, and finished the URLSession task normally. `OfficialProviderModelLister` correctly produced `ProviderModelListError.authenticationRejected`, but `ProviderSetupSession.setFailure` maps every non-`ProviderConfigurationError` to `.unavailable`.
- `ManagementCenterWindowController` assigns `window.minSize = 920×620`, which constrains the full frame. The SwiftUI root separately requires a `920×620` content area. At the minimum frame, AppKit exposes a `920×588` content layout rectangle, so the oversized root is clipped by 32 points.
- Existing Ticket 13 renders use a hosting view at the requested content size and therefore cannot expose the window-frame/content-size mismatch.

## Design

### Menu dismissal and onboarding fronting

`MenuBarPanelDismissalCoordinator` keeps the existing public behavior—actions wait until the popover reports closure—but dispatches the pending action to the next main-run-loop turn. This separates recovery presentation from AppKit's popover-close transaction.

The application delegate fronts onboarding through one helper that performs the sequence:

1. activate the accessory application;
2. show the existing onboarding window;
3. make it key and order it front regardless of the previously active application.

The same helper is used for a newly created or already existing onboarding controller. Capture readiness ownership remains in the application model.

### Provider setup failure classification

`ProviderSetupSession` recognizes `ProviderModelListError.authenticationRejected` and maps it to the existing `.invalidConfiguration` presentation category, which already renders the localized invalid-credential reason. Other model-list failures remain `.unavailable` in this ticket. The failed candidate key remains only in the field; coordinator persistence still starts only after a complete model list succeeds.

### Management minimum content size

`ManagementCenterWindowController` constrains `window.contentMinSize` to `920×620` instead of constraining the outer frame to those dimensions. The default content size remains `1200×720`. The SwiftUI root minimum remains `920×620`, so AppKit and SwiftUI use the same content-space contract.

## Failure modes by user operation

1. User clicks Capture from a visible menu panel without a usable Provider: the popover closes, the next main-loop turn runs readiness handling, onboarding activates and appears in front, and no screen freeze begins.
2. User clicks Capture without permission: the same fronting path runs and no permission request is issued by the menu action itself.
3. User clicks Capture when ready: the same deferred post-dismissal action starts capture without reopening onboarding.
4. User pastes a rejected OpenAI, DeepSeek, or Gemini key and selects Validate: the Provider returns 401/403, the field keeps the candidate text, the UI says the credential was rejected, nothing is written to Keychain, and no automatic retry occurs.
5. Provider transport, 5xx, malformed model list, or pagination failure occurs: the existing unavailable failure remains terminal and manually retryable.
6. User resizes the management center to its minimum: Header controls remain fully visible, the list footer remains visible, and the detail column is not vertically clipped.
7. User opens the management center at its default size: the content remains `1200×720`; no visual density or information hierarchy changes.

## TDD seams

1. Existing `MenuBarPanelDismissalCoordinator` seam: inject a deterministic next-turn scheduler and assert that the pending action does not run inside `panelDidClose`, then runs exactly once when the scheduled closure executes.
2. Existing `ProviderSetupSession` seam: drive validation through its public `validate(apiKey:)` path with a boundary throwing the real `ProviderModelListError.authenticationRejected`, then assert the public snapshot reports `.invalidConfiguration`.
3. AppKit window seam: expose the management controller's `contentMinSize` through its public window and assert the independent literal `920×620`; also resize the outer frame and assert the content layout rectangle never becomes smaller than the contract.
4. Whole-window production rendering remains the visual evidence for unchanged prototype parity; it supplements but does not replace the geometry test.

## Validation gates

- Each vertical slice: one correctly failing test, minimal implementation, focused test, then warnings-as-errors build.
- Full strict build and complete Swift test suite.
- Ticket 13 bilingual light/dark production renders regenerated and visually inspected.
- Localization parity, UI literal scan, `git diff --check`, code review, test review, and final regression.

## Out of scope

- Accepting an invalid API key or probing image input during model-list validation.
- New Provider retry, fallback, model selection, or Keychain behavior.
- New management-center controls, minimum width changes, or prototype revisions.
- Raising onboarding continuously above other applications after the explicit recovery action.
