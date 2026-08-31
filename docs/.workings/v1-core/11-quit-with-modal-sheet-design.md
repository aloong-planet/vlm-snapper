# Ticket 11 design — Quit while a sheet is presented

## Confirmed facts

- The installed app remains alive after both system Quit attempts, returning `User canceled (-128)`.
- macOS Unified Log reports `App termination blocked by modal sheet` before the application delegate's coordinated termination callback runs.
- The live unnamed 720 x 590 window matches the minimum dimensions of Provider setup.
- AppKit documents `NSWindow.preventsApplicationTerminationWhenModal` as the per-window control for this exact termination gate. Its default is normally enabled, while framework-created modal windows may choose another default.
- VLMSnapper presents app-owned SwiftUI sheets from onboarding, the menu-bar container, and the management center. The current test targets render their content but never present a real sheet and request application termination.

## Options

### A. End every sheet before requesting termination

This makes AppKit's gate disappear, but it mutates presentation state before the application knows whether termination is allowed. If an unsaved result causes a confirmation and the user cancels, Provider setup or permission recovery has already been dismissed. Ending a SwiftUI-created sheet from AppKit can also leave its local presentation binding stale.

Rejected.

### B. Mark VLMSnapper-owned sheets as permitting application termination

Each app-owned sheet configures its own hosting window so modal presentation does not preempt application termination. Quit then reaches the existing application delegate and shutdown coordinator. If the user cancels the unsaved-result confirmation, the application and existing sheet continue unchanged.

Selected.

### C. Disable the modal termination gate for every application window

This would also affect alerts, save panels, and future modal surfaces whose blocking behavior may be intentional. It obscures ownership and makes the policy difficult to audit.

Rejected.

## Design

Add one reusable SwiftUI sheet-content modifier in the UI module. Its AppKit bridge observes when its backing view moves into a window and sets that sheet window to allow application termination while modal. The bridge does not dismiss the window, store presentation state, or initiate termination.

Apply the modifier at every VLMSnapper-owned SwiftUI sheet root:

1. Onboarding permission recovery, Provider setup, and storage/privacy details.
2. Menu-bar permission recovery and Provider setup.
3. Management-center Provider setup.

Do not apply it to the unsaved-result confirmation, capture-failure alert, diagnostics save panel, or updater-owned windows. Their behavior is outside this sheet policy.

The existing coordinated shutdown remains the sole authority for capture cancellation, active-request persistence, unsaved-result confirmation, and the final terminate reply.

## User operation sequences and failure modes

1. **No sheet, no active work, Quit** — termination enters the existing coordinator and completes.
2. **App-owned sheet visible, no active work, Quit** — AppKit does not preempt the request; the coordinator completes and the app exits.
3. **App-owned sheet visible, active request, Quit** — the coordinator cancels and persists the request before exit.
4. **App-owned sheet visible, unsaved result, confirm discard** — the coordinator discards the unsaved result and exits.
5. **App-owned sheet visible, unsaved result, cancel termination** — the app remains running and the same sheet remains visible.
6. **Multiple app windows each own a sheet** — every enumerated sheet applies the same window policy; no window may retain the old default by omission.
7. **Sheet rerenders during Provider validation or model selection** — the window policy remains an idempotent value on the attached sheet and does not create a second presentation owner.
8. **An unrelated modal alert or system panel is visible** — it retains its existing policy; this change does not globally bypass modal termination.
9. **A future app-owned SwiftUI sheet is added without the modifier** — the AppKit integration test cannot enumerate future call sites, so the design and code review must treat all `.sheet` call sites as a class-level audit surface.

## Testing decisions

### Primary seam

The public sheet-content modifier is the product boundary. Mount representative sheet content in a real `NSWindow`, attach it as a sheet, allow the AppKit event loop to complete attachment, and assert the actual sheet window no longer prevents application termination while modal. The initial red must fail because an unmodified SwiftUI sheet retains the blocking value observed in the installed app.

### Coverage

- Real AppKit sheet-window policy after attachment.
- Static enumeration that every production `.sheet` root applies the modifier, or an equivalent high-level presentation test for each of the three host surfaces.
- Existing UI rendering remains unchanged; no new snapshot is required because the modifier has no visible pixels.
- Signed-app smoke: open Provider setup, issue normal system Quit, and verify the process exits without `App termination blocked by modal sheet`.

## Non-goals

- Changing the visual appearance, dimensions, or dismissal controls of any sheet.
- Removing the existing unsaved-result confirmation.
- Changing alert, save-panel, or Sparkle modal behavior.
- Refactoring the duplicate preflight between menu Quit and the application delegate.
