# Ticket 13 design review

## Review result

Approved after correcting five design risks. The ticket must implement the confirmed prototypes in production-native views, but it must not turn a visual contract into invented data, custom text editing, or tautological screenshot tests.

## Findings and corrections

### 1. Custom Command-V handling — rejected

A key-field-only keyboard handler would repair one screenshot while leaving every other text editor without a standard Edit menu. It would also bypass AppKit validation and accessibility conventions.

Correction: install one complete native application menu and keep editing actions on the responder chain with nil targets.

### 2. Pixel-identical HTML reproduction — rejected

The prototypes describe the accepted product UI, but production uses native AppKit/SwiftUI controls. Forcing browser CSS pixels onto native menus, typography, focus rings, and sheets would make the application less native and less accessible.

Correction: parity is evaluated by information hierarchy, control inventory, explicit accepted dimensions, state language, density, and interaction outcomes. Native platform chrome remains native.

### 3. Prototype fixture data in production — rejected

The companion and result prototypes contain sample titles, Provider names, timings, and results. Copying them would make the app appear configured or successful when it is not.

Correction: extend presentation seams to carry real history/provider/update/workspace data and use localized empty states when data is absent.

### 4. Shared geometry constants in implementation and tests — rejected

Tests that read the same constants used to lay out the view can stay green after an accidental contract change. Existing PNG-byte-count assertions have the same false-confidence problem.

Correction: menu expectations and confirmed geometry literals live independently in tests. Rendering remains necessary evidence, but named screenshots must also be visually inspected.

### 5. Keeping the obsolete panel update row — rejected

The earlier spec says the menu panel exposes a manual update check, while the latest confirmed companion prototype shows only an inline available-update notice and places manual update controls in settings.

Correction: implement the latest confirmed prototype. Keep manual checking in General Settings, remove the standalone panel row, and synchronize spec/features during closure.

## Regression boundaries

- Existing screenshot capture routing and popover-dismissal sequencing remain unchanged.
- Right-click status menu remains a native menu containing only Quit.
- Provider validation, model-list replacement, Keychain storage, and live request rules remain unchanged.
- Permission recovery reuses the existing coordinator and restart rules.
- Management mutations, retention, deletion, update lifecycle, and termination coordination are not redesigned.
- All new user-facing strings must exist in both locales before the full gate passes.

## Approved implementation order

Application menu → menu-panel presentation → onboarding/provider/privacy/permission → management center → result workspace/toolbar → full native rendering and documentation synchronization.
