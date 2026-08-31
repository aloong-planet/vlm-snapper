# Ticket 07 — Menu, onboarding, Provider, and permission UI design

Date: 2026-08-27

## Scope

Implement the confirmed menu-bar-first entry surface, single-page onboarding checklist, split-pane Provider setup sheet, and unified screen-capture permission recovery panel. Ticket 07 owns presentation state and native entry adapters. History content remains Ticket 08; full app lifecycle, language preference, login item, diagnostics, and Sparkle remain Ticket 09.

## Architecture seams

1. `OnboardingSession` is a pure Sendable state model. It combines permission readiness and Provider readiness into one snapshot, derives the blocker, and never performs OS or network effects.
2. `ScreenCapturePermissionCoordinator` is an actor at the TCC boundary. It reads current access, remembers whether this app installation already requested access, and returns typed dispositions for explicit user intents. It never requests permission during status refresh, Provider setup, or menu-panel display.
3. `ScreenCapturePermissionAuthorizing` abstracts `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess`. `PermissionRequestHistoryStoring` distinguishes an untouched installation from a prior denied/revoked state because Core Graphics exposes no public denied-versus-not-requested status.
4. `ProviderConfigurationCoordinator` remains the only durable Provider/model authority. Ticket 07 adds a read snapshot and a `ProviderSetupSession` presentation actor that holds only transient API-key input, selected Provider, validation progress, returned models, and pending model selection.
5. SwiftUI views receive immutable snapshots and explicit async-safe callbacks. They do not read Keychain, UserDefaults, metadata files, TCC, or `NSWorkspace` directly.
6. `MenuBarPanelController` owns an `NSStatusItem` and transient `NSPopover`. Its History, Settings, Update, and Quit actions are callbacks so later tickets attach lifecycle and management-center behavior without replacing the panel.
7. The selected permission recovery Direction A is one reusable attached panel used from both onboarding and menu capture. Direction B is retained only as prototype history.

## Permission state and effects

The product presents four user-relevant states:

- `notRequested`: preflight is false and no request attempt is recorded.
- `unavailable`: preflight is false after a recorded attempt. Public APIs cannot reliably label this as denied versus later revoked, so user copy covers both.
- `restartRequired`: the explicit system request returned true in the current process; the user is told to restart before capture.
- `ready`: preflight is true after launch/refresh.

User sequences:

1. Opening onboarding or the menu panel only refreshes status with preflight; it never opens a system prompt.
2. Pressing Configure Permission in `notRequested` records the attempt before calling the system request. Success yields `restartRequired`; failure yields `unavailable`.
3. Pressing the same action in `unavailable` yields `openSystemSettings` and never calls the system request again.
4. Returning from System Settings refreshes preflight. If access is visible, the panel presents Restart; otherwise it remains recoverable and dismissible.
5. Starting capture with no usable Provider/model opens Provider setup before any TCC request or screen freeze.

The restart and System Settings effects are injected UI callbacks. Ticket 07 tests intent routing; signed, packaged TCC and relaunch behavior remain release gates.

## Onboarding readiness

Permission and Provider/model are required. Storage/privacy is informative and never blocks. The derived Start button is enabled only when both required items are ready. “Later” is always enabled and closes onboarding without changing readiness.

Provider readiness is one of `missing`, `pendingModel(provider)`, or `ready(provider, model)`. The blocker prioritizes permission, then Provider/model, matching the visible checklist order. No localized strings are stored in the model.

## Provider setup workflow

1. Select one built-in Provider: DeepSeek, OpenAI, or Gemini.
2. Enter an API Key and press Validate.
3. The existing coordinator validates the key, fetches the complete account model list, and persists the Keychain credential plus metadata replacement.
4. Success keeps the credential area in place and reveals the model picker immediately below it; it does not navigate or auto-select a model.
5. Selecting a returned model calls the existing coordinator. No manual model ID input exists.
6. Done is enabled after selection and returns to onboarding showing Provider and model. Close/Cancel can return with a validated but pending-model Provider.
7. Refresh uses the saved credential and replaces the list. A disappeared selected model is removed by the existing coordinator and returns the sheet to pending selection.
8. While an operation freezes configuration, mutation errors render inline and the form remains read-only until activity ends.

The API Key remains transient in view state until validation succeeds or the sheet is dismissed. Failed validation retains the input for correction, as required. User-visible errors are typed and localized; raw secrets and response bodies are never shown or logged.

## Menu panel

The menu-bar panel is the first regular entry. It exposes Capture, a bounded recent-record summary supplied by Ticket 08, History, Settings Center, Check for Updates, and Quit. Capture routes in this order:

1. Missing Provider/current model → open Provider setup; do not request permission.
2. Permission not ready → present the unified recovery panel.
3. Both ready → invoke capture.

History and Settings call the same management-center navigation boundary with different destinations. Ticket 07 does not fabricate history data or update behavior.

## Visual and localization contract

- Onboarding uses selected Direction A: a single readiness checklist with one dynamic blocker.
- Provider setup uses selected Direction B: Provider sidebar and reusable detail pane. The attached sheet has 8 px corners; fixed Provider marks do not collapse at narrow widths.
- Permission recovery uses selected Direction A: one continuous reusable panel, not inline expansion.
- Menu panel follows confirmed Direction C.
- Colors are semantic, icons are centralized SF Symbols, and all user-visible text comes from zh-Hans/en localization dictionaries.
- HTML prototypes define the confirmed structural and visual contract but do not replace validation of the actual SwiftUI output. Production SwiftUI views must match that contract and be rendered in light/dark and at the narrow Provider sheet width; if the implementation intentionally diverges, the affected prototype decision must be updated or explicitly marked stale.

## Verification

- Core tests cover readiness derivation, Later availability, explicit-only TCC requests, no repeat request after denial/revocation, restart state, Provider snapshot and transient setup transitions.
- UI tests inspect menu capture routing and narrow-width fixed icon geometry through stable public layout constants/models rather than private SwiftUI structure.
- Harness renders onboarding, Provider setup, permission recovery, and menu panel in both appearances.
- Full gates: Swift build, exact test count, localization key parity, unlocalized production-literal scan, CJK-in-code scan, and `git diff --check`.
