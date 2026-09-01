# Ticket 15 design review

## Review result

Approved after replacing three symptom-level patches with one lifecycle fix, one typed error mapping, and one content-space geometry contract.

## Findings and corrections

### 1. Add a delay to `showOnboarding()` — rejected

An arbitrary time delay would hide the lifecycle race, slow the interaction, and remain timing-dependent.

Correction: preserve close-before-action ordering and move the pending action to the next main-run-loop turn, which is the first lifecycle boundary after the close transaction.

### 2. Make onboarding a floating always-on-top window — rejected

Changing the window level would keep onboarding above unrelated applications beyond the explicit action and alter confirmed product behavior.

Correction: activate once, show the normal window, make it key, and use one front-ordering operation for the user-triggered recovery only.

### 3. Treat every model-list failure as invalid credentials — rejected

Transport, 5xx, malformed payload, and pagination failures are not evidence that the key is wrong.

Correction: map only the typed authentication rejection to the existing invalid-credential reason; keep unrelated failures unavailable.

### 4. Add top padding to the Header — rejected

Padding would compensate only for the visible top crop while leaving the bottom and detail body clipped.

Correction: define the minimum in content coordinates with `contentMinSize`, matching the SwiftUI root contract.

### 5. Remove the SwiftUI minimum height — rejected

That would permit the confirmed management layout to collapse below its supported information density and would not state the real AppKit contract.

Correction: retain the root minimum and make the window enforce the same content minimum.

## Regression boundaries

- Readiness decisions remain owned by `VLMSnapperApplicationModel.capture()`.
- Menu panel dismissal still precedes every Capture action.
- Provider validation remains one request with no automatic retry and no persistence before complete success.
- The Provider setup field and model selector geometry do not change.
- Management navigation, filters, search, selection, history actions, and detail content do not change.
- No user-facing string, icon, or visual token is added.

## Approved implementation order

Provider authentication classification → management content-size contract → menu-dismissal lifecycle and onboarding fronting → full review and rendering.
