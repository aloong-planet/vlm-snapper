# Ticket 09 — Lifecycle, localization, diagnostics, and update design

## Scope

Ticket 09 adds application-level lifecycle modules and their native adapters: primary-instance election and activation, allowlisted local diagnostics, UI-language preference, login-at-launch state, and Sparkle update state. It also extends the confirmed menu and General Settings surfaces. Ticket 10 still owns the signed `.app` composition, architecture-specific Info.plists/appcasts, release credentials, notarization, and end-to-end installation verification.

## 1. Primary instance

`PrimaryInstanceCoordinator` is the only interface startup code crosses before constructing the database, hotkey registrar, cleanup scheduler, or updater. Its outcome is either `primary(lease)` or `secondary`. The adapter acquires an advisory lock in the app's internal Application Support directory and holds the file descriptor for the process lifetime. A crash releases the kernel lock; the lock file itself is not treated as ownership.

After a primary claim, the adapter installs a per-user distributed activation observer. A secondary process that cannot acquire the lock posts an activation notification and asks the existing `NSRunningApplication` to activate, then terminates without opening any protected subsystem. The primary routes activation to the active result window when a model operation exists, otherwise to the menu panel. The signed-app gate in Ticket 10 must exercise simultaneous launch and `open -n`; unit tests use a lock and activation adapter, not multiple test processes.

## 2. Diagnostics

`DiagnosticEvent` is a typed allowlist rather than an arbitrary message logger. Its optional fields are timestamp, Provider ID, model ID, request stage, duration, HTTP status, sanitized Provider error code, sanitized request ID, and normalized application error code. There is no free-form message, request, response, path, screenshot, source text, translation, credential, or header field.

`DiagnosticLogStore` writes one JSONL file per UTC day under internal Application Support. Provider/error/request identifiers pass a conservative printable-token sanitizer and length limit; rejected values become absent rather than partially copied. Cleanup only considers managed daily filenames and removes files older than seven days. Export is user initiated and produces a gzip-compressed JSONL stream from currently retained managed files. A failed cleanup or export returns a typed local error and never weakens the allowlist.

The seven-day boundary is rounded down to the UTC start of the cutoff day so a daily file is never removed before every event in that file has completed the retention period. Gzip input and output are bounded at the C interoperability seam and the produced stream must round-trip through a system gzip implementation.

## 3. Language preference

`ApplicationLanguagePreference` persists only `system`, `zh-Hans`, or `en`. `ApplicationLanguageResolver` scans the complete ordered `Locale.preferredLanguages` list and chooses the first supported language by normalized language/script identity; unsupported entries do not force an early fallback. The effective language is concrete and derived, never persisted.

The production composition resolves language synchronously before constructing the first SwiftUI view and configures the localization bundle once for that process. Changing preference saves the new strategy and presents a restart-required state; it does not hot-swap an already-mounted view. Date, number, token, duration, and measurement formatting continue using the user's current region, not the selected UI language. v1 does not mirror RTL layouts.

The restart-required state exposes an application restart intent. The settings view never changes its active localization dictionary in place; process startup explicitly loads the selected language's strings table before mounting UI.

## 4. Login item

`LoginItemCoordinator` owns the user intent and maps `SMAppService.mainApp.status` into `disabled`, `enabled`, `requiresApproval`, or `unavailable`. The first primary launch attempts to enable login launch because the product default is on. `register()` success is not assumed to mean enabled: the status is reread, and `requiresApproval` remains visible with an explicit System Settings action. Disabling calls `unregister()` and also rereads status. The adapter never runs in a secondary instance.

## 5. Update lifecycle

`UpdateLifecycleModel` is one application-level observable state shared by menu and settings:

- `idle` / `checking`
- `current(lastCheckedAt)`
- `available(version, displayVersion)`
- `downloading(version, receivedBytes, expectedBytes?)`
- `readyToInstall(version)`
- `failed(operation, normalizedCode)`

Sparkle 2.9.6 is isolated behind a native adapter. Automatic checking is enabled by default and scheduled at 21,600 seconds. Automatic downloading is disallowed in product configuration and never exposed as a preference. A custom public `SPUUserDriver` receives the available item and retains Sparkle's choice reply. The user's Download intent replies with `.install` exactly once; only Sparkle download callbacks transition through downloading and ready states. UI code never assumes success from the button tap.

User-driver callbacks are forwarded through one ordered delivery chain. This prevents download-byte or ready events from overtaking the preceding download-start event when Core consumes them asynchronously.

The user driver retains Sparkle's ready-to-install reply. Normal app termination lets Sparkle install the prepared update. Immediate restart invokes the retained install path only after the application shutdown coordinator has canceled and persisted the active operation and resolved any unsaved-result confirmation. A downloaded update that remains uninstalled for seven continuous days creates one gentle reminder state; it does not request notification permission or interrupt a capture/model operation.

Information-only updates do not expose Download and instead open their HTTPS information URL through an injected intent. Any update error is normalized for UI and diagnostics; raw Sparkle errors are not persisted or shown verbatim.

## 6. UI and localization

The confirmed prototype removes the standalone Update destination. General Settings contains language, login launch, automatic checking, retention, and diagnostics. Menu and settings consume the same update snapshot and intents. The menu status dot and inline notice appear for available, downloading, and ready states. Capture remains the primary menu action.

All new visible text is added to both localization dictionaries and accessed through `VLMSnapperStrings`. SF Symbols remain centralized in `VLMSnapperIcons`. Rendering covers Simplified Chinese and English longest-copy states in light and dark appearances.

## 7. Failure sequences

1. Two instances launch together: one kernel lock succeeds; only that process constructs protected subsystems. The loser requests activation and exits.
2. Primary crashes: the kernel releases ownership; a later launch acquires the existing lock file safely.
3. Diagnostic token contains whitespace, control characters, or exceeds the limit: omit that field; keep the typed event.
4. Retention cleanup hits an unrelated or malformed filename: ignore it. A managed-file deletion failure is reported and later files continue.
5. Preferred languages are `[unsupported, en, zh-Hans]`: resolve English. Manual `system` preference remains `system` on disk.
6. Login registration needs approval: show requires-approval, do not claim success, and keep the user setting actionable.
7. Background check finds an update: show available; do not download.
8. User taps Download twice: Sparkle choice reply is consumed once; no second download starts.
9. Download fails or is canceled: leave ready false, publish normalized failure/available state as appropriate, and permit an explicit retry.
10. User taps immediate update during an active or unsaved operation: shutdown coordination runs first; canceled/aborted shutdown never invokes Sparkle installation.

## Validation

- Strict Swift/C warnings-as-errors build.
- Vertical unit tests for primary startup gating, diagnostic sanitizer/retention/export, language resolution/persistence, login status mapping, and update state transitions/double-download prevention.
- UI rendering of menu and General Settings in both languages, both appearances, and available/downloading/ready/failure states.
- Full package tests with a real Swift Testing total; `Executed 0 tests` is not evidence.
- Ticket 10 signed-app gates for process election, SMAppService, Sparkle feed/download/install, appcast architecture, TCC, Keychain, signing, notarization, and Gatekeeper.
