# VLMSnapper v1 core features

Status: implemented in the development application; not yet eligible for a formal public release.

## Menu-bar application

VLMSnapper runs as a menu-bar accessory without a Dock icon. The panel starts a capture, shows the active capture shortcut, opens the three most recent records, navigates to History or Settings, exposes update checks, and quits through the coordinated shutdown path. Provider setup, permission recovery, and storage/privacy sheets do not block that path; canceling an unsaved-result confirmation keeps both the application and the original sheet open. Only one primary instance per macOS user opens protected storage, registers the shortcut, performs cleanup, or checks for updates.

## First-run setup and recovery

The onboarding window separates screen-capture permission, online Provider configuration, and storage/privacy details. A user may finish later, but capture remains unavailable until both permission and one Provider/model are usable. Provider setup supports DeepSeek, OpenAI, and Gemini, stores API keys in Apple Keychain, fetches the account model list, and requires an explicit model selection. Permission recovery distinguishes first request, denied/revoked access, Settings, and restart-required states. The macOS permission explanation identifies VLMSnapper and states that screen access is used to capture a selected area for text extraction or translation in the supported interface language.

## Frozen-frame capture

The global capture shortcut defaults to `⌥⇧S` and can be changed through a key-recording control in General Settings. A replacement is registered before the previous shortcut is released; invalid or conflicting input leaves the old shortcut active and shows a localized explanation.

Triggering capture freezes every available display at that instant through ScreenCaptureKit. Selection panels show only those frozen images, so videos and animation cannot advance between trigger and crop. A rectangular selection is mapped into display-local physical pixels and cropped into the original sRGB PNG. Escape, cancel, or retriggering before a model request discards the in-memory capture without creating history.

## Extract and translate operations

The compact toolbar stays 4 px from the selection and offers Extract Text, Translate, a searchable target-language picker, the current Provider/model, and cancel. The language list uses stable standard codes, keeps 11 common languages first, excludes Traditional Chinese and arbitrary manual values, and remembers the last choice.

Each user-triggered Extract, Translate, or Retry creates exactly one request to the currently selected online multimodal model. Translate sends the original PNG and asks the model to return both recognized source text and translated text in one streaming response. It does not run Apple Vision OCR or make a second text-translation request. A failure terminates immediately with its normalized reason; there is no automatic product retry.

The result workspace keeps the original screenshot beside streamed Markdown output. Extract and Translate slots are independent, reuse the same original PNG, and never start merely because the user switches tabs. Closing an active request cancels and persists it. A result that could not be saved remains copyable and requires explicit confirmation before discard.

## Local history and screenshots

Before any network upload, VLMSnapper atomically saves the original PNG and prepares a recoverable SQLite record. Screenshots are stored by year-month under `~/Pictures/VLMSnapper/` with timestamp filenames such as `vlmsnapper-20260825-143012.png`; a `-2`, `-3`, and later suffix prevents same-second collisions without overwriting. Internal metadata stays in the sandbox Application Support directory.

The management center provides the confirmed left-aligned All / Extract Text / Translate selector, source/translation search, pinned navigation, record details, original screenshots, model metadata, latency, usage, delete, and clear-history actions. Deletion only removes PNG bytes whose managed path and SHA-256 still match the record; replacements at the same path are treated as user data and retained.

Unpinned history defaults to 30 days, with 7, 30, 60, 90, or 180 days available. Cleanup runs once at primary startup and is checked during the application lifetime, never more than once per 24 hours. Shortening retention shows the affected count before permanent deletion. Partial failures continue and remain visible for retry.

## Settings, diagnostics, and updates

General Settings includes interface language, capture shortcut, login at launch, update checking, history retention, and diagnostics export. The interface supports Simplified Chinese and English; changing it requires restart. Sanitized allowlisted diagnostics are retained for seven days and exported as gzip without API keys, authorization headers, prompts, screenshots, recognized text, or response bodies.

Sparkle checks the architecture-specific HTTPS appcast at a fixed six-hour interval when automatic checking is enabled. It never automatically downloads an update. An available version is shown in the menu and Settings; the user chooses when to download. Download and installation state comes only from Sparkle callbacks, and immediate installation first closes active work safely.

## Distribution status

Development validation produces separate Universal, Apple Silicon, and Intel DMGs with matching identity, version, Sparkle public key, resources, entitlements, and architecture-specific appcasts. The formal pipeline is fail-closed for Developer ID signing, hardened runtime, timestamps, notarization, stapling, Gatekeeper, EdDSA enclosure/feed verification, and atomic six-file staging.

The current repository does not claim a public release. Formal distribution remains blocked until real Developer ID/notary credentials, public unauthenticated HTTPS hosting, a signed update-from-previous-version exercise, and protected live Provider contracts pass. A Provider with unconfirmed account visibility or request limits must be disabled in the signed release configuration rather than guessed.
