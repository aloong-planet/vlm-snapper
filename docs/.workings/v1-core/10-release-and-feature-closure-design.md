# Ticket 10 — Release and feature closure design

## Scope

Ticket 10 turns the already tested libraries and native views into a real menu-bar application, then builds and validates the three direct-distribution variants. It also closes every deferred signed-host and live-provider gate before the v1 feature is eligible for release.

The ticket does not publish a release merely because packaging code exists. Local unsigned or ad-hoc artifacts are development evidence only. A formal release remains fail-closed until the signed application, all three final DMGs, three EdDSA-signed feeds, live provider contracts, and signed-host interaction checklist have all passed.

## Production application composition

Add a `VLMSnapperApp` executable target. The application delegate owns the application-lifetime composition root and is the only place that creates application-wide services:

- primary-instance election and activation messaging;
- application language resolution before the first view is created;
- Keychain credentials and provider metadata under the stable bundle identity;
- the history database, managed screenshot store, retention scheduler, and diagnostics;
- permission, provider setup, global shortcut, capture, operation, menu-bar, management-center, onboarding, and update coordinators.

The secondary-instance path acquires no protected service. It asks the primary instance to activate and terminates. The primary instance creates the menu-bar controller only after the lease is held.

Production view state is held by one `@MainActor` observable application model. Existing views continue to consume immutable snapshots and explicit callbacks. Async callbacks re-read authoritative actor state before publishing a new snapshot; views do not become owners of provider, history, operation, or updater truth.

The application uses accessory activation policy, so it has no Dock or Command-Tab entry. Closing ordinary windows hides them. Every termination path, including Command-Q, explicit Quit, language restart, and Sparkle installation, runs the shared shutdown coordinator. It cancels and persists an active request and requires confirmation before discarding an unsaved completed result.

## Capture host

The existing frozen-frame and crop seams remain authoritative. The production capture host creates one borderless panel per successfully frozen display and draws only the captured frozen image plus the selection chrome. Live desktop content is never sampled again after the shortcut trigger.

Pointer input is converted through the frozen display geometry already used by `CaptureSelectionSession`. A valid selection is cropped from the frozen frame and handed to the confirmed toolbar controller. Invalid selections remain editable; Escape or cancel tears down every overlay without creating a file or history record. A display invalidated after capture becomes unavailable and is never replaced by a live frame.

The overlay and toolbar follow the confirmed capture prototype. This ticket adds production hosting and interaction wiring, not a new visual direction. The toolbar uses the configured Provider/model and a searchable standard target-language catalog; the selected language is remembered and the original PNG remains the only image sent for either operation.

The capture shortcut defaults to Option-Shift-S and is recordable in General Settings. A valid replacement becomes active before the old registration is released; an invalid or conflicting replacement leaves the current shortcut unchanged. Repeated capture while selecting or viewing the toolbar invalidates the older freeze generation and starts a new frozen capture. Repeated capture during an active model workspace only brings that workspace forward.

## Application paths and configuration

All internal state uses the sandbox Application Support directory. Managed PNGs continue to use `~/Pictures/VLMSnapper/` through the existing screenshot store. Build-time product configuration supplies:

- `CFBundleIdentifier = com.loong.vlmsnapper`;
- one semantic marketing version and monotonically increasing build version;
- one of `universal`, `arm64`, or `x64` as the distribution architecture;
- the matching HTTPS `SUFeedURL`;
- one shared `SUPublicEDKey`;
- six-hour checks enabled and automatic download disabled;
- accessory-app and macOS 14 minimum-system settings.

The sandbox entitlement set is explicit: application sandbox, outbound network access, and read/write access to the user's Pictures library. Sparkle uses its installer launcher service; the main application carries the two bundle-scoped `-spki` and `-spks` Mach lookup exceptions required by the embedded installer/status services. The product does not enable Sparkle system profiling or the downloader XPC service. The feed is required to be signed, and updates are verified before extraction.

The release builder rejects missing, placeholder, non-HTTPS, cross-architecture, or inconsistent configuration. There is no runtime fallback feed and no unsigned remote configuration.

## Build matrix

Build native arm64 and x86_64 release executables separately with the full Xcode toolchain. The Universal executable is created only from those exact two successful inputs. The Sparkle framework and SwiftPM resource bundles are embedded in each application bundle.

The matrix produces exactly:

- `VLMSnapper-<version>-mac-universal.dmg`;
- `VLMSnapper-<version>-mac-arm64.dmg`;
- `VLMSnapper-<version>-mac-x64.dmg`.

Artifact inspection asserts the executable slice set, bundle identifier, version, minimum system version, architecture-specific feed, common public key, required resources, Sparkle framework, entitlements, and absence of a Dock-visible activation policy.

## Signing, notarization, and feed order

Formal release order is fixed:

1. Import the Developer ID identity into an isolated temporary keychain.
2. Build and assemble all three application bundles.
3. Sign nested Sparkle code, the executable, and each outer application with hardened runtime and the release entitlements. Nested-code signing preserves required embedded entitlements and is followed by a strict deep verification; a successful outer signature alone is insufficient.
4. Verify each signed application and submit a ZIP of each application to Apple notarization.
5. Require `Accepted`, staple each application, and validate its ticket.
6. Create each final DMG from its already-stapled application and an Applications link.
7. Sign each DMG, submit it to notarization, require `Accepted`, staple it, and validate the final bytes.
8. Mount each DMG read-only and verify both the outer DMG and inner application with `codesign`, `stapler`, `spctl`, bundle metadata, and executable architecture checks.
9. Run Sparkle `generate_appcast` separately over the final DMG for each architecture. All three use the same private key and version but distinct download URLs.
10. Parse and validate every enclosure, verify its EdDSA signature against the final DMG, and verify that the supplied public key is derived from the signing key.
11. Stage all three DMGs and all three appcasts together. Nothing becomes public until every prior gate has passed.

Stapling changes bytes, so EdDSA signing always follows final DMG stapling. Public appcasts are never updated before all three architectures pass.

## Automation boundary

Pull requests run strict compilation, all Swift tests, UI rendering tests, release-tool tests, and unsigned/ad-hoc three-architecture assembly checks. These jobs prove the release pipeline shape but do not claim Developer ID or Apple notarization.

A manual formal-release verification job and a clean release tag require all release credentials. Missing credentials fail before packaging; the workflow never silently falls back to ad-hoc or unsigned output. A formal release also requires a public HTTPS feed/download location. The current private repository is acceptable for development but cannot itself serve unauthenticated Sparkle feeds.

Provider live-contract tests use protected CI credentials and a fixed harmless PNG fixture. They record only provider, model, stage, normalized outcome, timing, status, redacted request identifier, and usage. They never persist keys, authorization headers, response bodies, recognized text, or uploaded image bytes.

## Provider release gates

Gemini may run when its protected credential is present. OpenAI and DeepSeek remain blocked when their protected credentials are absent. DeepSeek additionally requires the account model list to contain the exact configured model and the full image/stream/cancel/timeout/truncation/error/usage contract to pass.

The release configuration carries signed, versioned request-size limits. A provider with an unconfirmed limit is disabled for that release rather than assigned a guessed limit. Refreshing a model list or failing a live probe never retries the user operation.

## User-operation failure modes

1. A second process starts: it activates the primary and exits before opening protected storage, hotkeys, cleanup, or Sparkle.
2. The first run has no provider or permission: onboarding remains reachable; capture does not freeze or request permission out of order.
3. A shortcut arrives during selection or the toolbar: the older freeze generation is cancelled and a new frozen capture starts. During an active model workspace, the result window is activated and no second request starts.
4. One frozen display fails or changes geometry: only that display is unavailable; successful frozen displays remain usable.
5. All displays fail: overlays close, no PNG/history/network activity occurs, and a localized retry/cancel error is shown. Permission denial uses the existing permission recovery route instead.
6. The user cancels or presses Escape before an operation: every overlay and in-memory frame is released without persistence.
7. Application shutdown or update installation begins during a request: the request is cancelled and persisted before termination; failed shutdown leaves the app and installer state unchanged.
8. Database or screenshot storage fails: the existing no-network and recovery rules remain authoritative.
9. Sparkle reports an available update: no download begins until the user asks; only updater callbacks may report downloading or ready.
10. An installed architecture reads a mismatched feed or artifact: release validation fails; the app does not migrate architectures automatically.
11. Any app, DMG, notarization, staple, Gatekeeper, EdDSA, feed, or provider gate fails: no architecture is published and no public appcast changes.
12. CI or a local machine lacks credentials: development validation may produce clearly labelled unsigned artifacts, but formal validation fails and cannot be reported as release-ready.

## Testing seams

### Seam A — production bootstrap

A public application bootstrap protocol exposes primary/secondary startup, lifecycle state publication, capture routing, and ordered shutdown. Tests inject paths, clocks, permission/provider state, capture services, and termination adapters. No test constructs unreachable private state.

### Seam B — release manifest and artifact validator

A deterministic release manifest describes the three architectures, feed URLs, public key, bundle identity, version, and artifact names. Unit tests cover missing members, duplicate architectures, mismatched versions/keys/feeds, placeholder or insecure URLs, and wrong executable slices. Script-level tests execute the validator against minimal fixture bundles and feeds.

### Seam C — system and provider integration

Signed-host checks exercise TCC, Keychain, global hotkey conflicts, multi-display frozen-frame timing, single-instance activation, login-item approval, Sparkle check/download/install, and offline ticket validation. Live provider checks are credential-gated and report explicit skipped/blocked status rather than passing silently.

## Evidence and stop conditions

Ticket 10 is complete only when:

- the production app is interactively usable through the confirmed flows;
- strict build and the full Swift Testing total pass;
- current-change UI renders are inspected in both languages and appearances;
- all prior ticket checklist entries are re-audited against the production host;
- all three signed DMGs and all three feeds pass the formal gates;
- required live provider contracts pass, or the affected provider is disabled in the signed release configuration;
- `review-code.md`, `review-tests.md`, `final-regression.md`, and `docs/features/v1-core.md` describe the same shipped behavior.

Until those conditions hold, the branch may contain a tested release pipeline, but the ticket and product release remain incomplete.
