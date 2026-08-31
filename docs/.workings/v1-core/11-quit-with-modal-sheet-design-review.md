# Ticket 11 design review — Quit while a sheet is presented

## 1. Bottom-layer assumptions

- Confirmed from the current macOS SDK that `preventsApplicationTerminationWhenModal` is the window-level policy intended for modal termination.
- Confirmed from Unified Log that the current failure occurs in AppKit before the application delegate, so changing only `prepareForTermination` cannot fix it.
- Confirmed the failure is not an unsaved-result decision: the history database contains no operations, diagnostics contain only startup, and the sampled process returned to its ordinary event loop after AppKit canceled termination.

## 2. Runtime behavior

- Forcibly ending sheets was rejected because a later user cancellation would lose presentation context and could desynchronize SwiftUI bindings.
- A window-attached bridge is required; configuring a view before it belongs to a sheet window would be a timing-dependent no-op.
- The policy is idempotent and remains valid across SwiftUI updates.
- The complete class of current app-owned SwiftUI sheet call sites was enumerated: onboarding, menu-bar container, and management center.

## 3. Safety and correctness

- The selected policy does not bypass the application delegate; it permits the delegate to make the decision that AppKit currently preempts.
- The change is scoped to app-owned sheet content, so system panels and intentional modal alerts are not silently weakened.
- Canceling termination preserves both unsaved content and the original sheet presentation.

## 4. Consistency

- The design preserves the existing invariant that every successful termination path runs coordinated shutdown.
- No user-visible text, icon, geometry, color, or localization changes are introduced.
- The logic prototype records the selected cancel path: continued execution retains the sheet.

## Review conclusion

Option B is approved for implementation. The acceptance gate must include a real AppKit window rather than relying only on rendering tests or a pure policy unit test.
