# Ticket 14 design review

## Review result

Approved after separating the five symptoms into four production causes and rejecting two deceptively small fixes.

## Findings and corrections

### 1. Re-front the existing popover sheet — rejected

Keeping recovery inside the menu popover would preserve the edge-anchored geometry and leave readiness split between the menu and application model.

Correction: dismiss the panel and enter the existing application-model Capture path. The model remains the single readiness authority and the onboarding window becomes the recovery host.

### 2. Observe the entire application model from Provider setup — rejected

Making the view depend on the whole mutable application model would widen ownership and still couple a local text-editing concern to unrelated state.

Correction: keep a presentation-local key draft, copy it to the existing boundary only at validation, and clear it at the current lifecycle transitions.

### 3. Replace only the management sidebar color — rejected

The same incorrect semantic surface appears in Provider setup, hints, screenshots, and metrics. Fixing a single call site would leave a class-level theme defect and inconsistent surfaces.

Correction: repair the theme anchor once with an adaptive AppKit semantic color, then render all affected surfaces in both appearances.

### 4. Add history geometry constants and assert them — rejected

Constants shared by production and tests can remain green when both drift together, and they do not prove that the card hierarchy is rendered.

Correction: keep behavior tests at real seams and use newly generated whole-window renders for the pure hierarchy correction.

### 5. Hard-code a near-white RGB value — rejected

A hard-coded light value would violate the theme contract and fail in dark appearance.

Correction: use an adaptive system semantic surface and verify the actual rendered luminance under pinned light and dark appearances.

## Regression boundaries

- Capture readiness and permission/provider coordinators remain unchanged.
- Menu-panel close-before-capture ordering remains mandatory.
- Provider validation remains one explicit request with no automatic retry or model selection.
- API keys remain transient in UI and persist only through the existing Keychain flow after successful validation.
- History search, filter, pin, delete, retention, and record selection semantics do not change.
- No new icon or localized string is introduced.

## Approved implementation order

Menu recovery routing → Provider key draft → semantic surfaces → history detail card → complete rendering and documentation synchronization.
