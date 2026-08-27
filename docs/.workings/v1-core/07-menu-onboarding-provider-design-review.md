# Ticket 07 — Design review

Date: 2026-08-27

## Findings resolved before implementation

1. Core Graphics preflight cannot distinguish never requested, denied, and revoked. The design records whether the app attempted a request and uses one honest `unavailable` recovery state instead of claiming an OS distinction it cannot observe.
2. Requesting TCC during onboarding display would violate the confirmed user-triggered rule. Status refresh is preflight-only; only the explicit permission action can call the request API.
3. A menu Capture action that checks permission first could prompt before the user has configured a model. Routing checks Provider/model first, then permission, then capture.
4. A Provider sheet that mirrors durable metadata in independent storage can drift from Keychain generations and refreshed model lists. The sheet keeps only transient input/presentation state and delegates every durable mutation to `ProviderConfigurationCoordinator`.
5. Automatically choosing the first model after validation would contradict the confirmed model-selection flow. Validation reveals the complete list in place and leaves selection pending.
6. A second permission recovery implementation inside the menu panel would diverge from onboarding. Selected Direction A is a reusable panel driven by the same typed permission state and actions.
7. Implementing a production executable now would mix Ticket 07 presentation with Ticket 09 single-instance and lifecycle ownership. Ticket 07 provides native controllers and callbacks; the final app composition remains Ticket 09.
8. Treating an accepted permission request as immediately capture-ready is unreliable for the confirmed product flow. The coordinator yields `restartRequired`, and readiness becomes true only after a subsequent preflight reports access.

## Scenario completeness check

- Entry paths: first launch, Later then menu capture, Provider-first configuration, permission-first configuration, validated-without-model, and previously ready permission later unavailable all converge on the same state model.
- Exit paths: onboarding Start, Later, Provider Cancel/Close/Done, recovery Dismiss/Open Settings/Restart, and menu actions are explicit callbacks with no hidden capture.
- Failure paths: Provider validation, refresh, selection, metadata/Keychain consistency, permission denial, and unchanged System Settings state remain actionable without dismissing the parent surface.
- Concurrency: Provider mutation remains serialized by the existing coordinator and rejects changes during request freeze. Permission requests are actor-serialized, and repeated explicit clicks cannot create overlapping system requests.
- Privacy: API-key input is transient; no view string, diagnostic, or test fixture echoes a real key.

## Review conclusion

The reviewed design covers the accepted prototypes and Ticket 07 acceptance without depending on unimplemented history, updater, or lifecycle behavior. Implementation may proceed test-first at the permission/readiness and Provider presentation seams, followed by native UI rendering.
