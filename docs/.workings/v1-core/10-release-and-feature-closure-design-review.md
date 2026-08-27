# Ticket 10 design review

## Review result

The release design is implementable without a new visual decision. Existing confirmed prototypes cover every production surface this ticket hosts. The review found and corrected one signed-host defect before implementation: the first draft described an app sandbox but omitted Sparkle's installer launcher configuration and bundle-scoped Mach lookup exceptions.

## Facts checked

1. The current package has no production executable target. Packaging the UI harness would not satisfy the ticket.
2. The exact Sparkle 2.9.6 artifact contains a universal framework, updater app, installer/downloader XPC services, `generate_appcast`, `generate_keys`, and `sign_update`.
3. Sparkle's exact-version test application enables `SUEnableInstallerLauncherService` and grants `<bundle-id>-spki` and `<bundle-id>-spks` Mach lookup exceptions for a sandboxed host.
4. `generate_appcast` accepts final DMGs, an HTTPS download prefix, and an EdDSA key from standard input. `sign_update --verify` can verify each enclosure signature.
5. The installed Xcode `notarytool` supports JSON output and waiting for a terminal result; `stapler` supports both application bundles and UDIF disk images.
6. This machine currently has no valid code-signing identity. Only a Gemini live-provider credential name is present; no OpenAI or DeepSeek credential name was found. No credential value was read.
7. The repository remains private. It cannot serve unauthenticated Sparkle feeds or release downloads to normal users while private.

## Design findings

### 1. Sparkle sandbox installation path — fixed

Failure mode: a sandboxed application could check or download an update but fail when launching the installer service. This would escape the library test layer and appear only in a signed installed host.

Correction: the design now requires installer-launcher configuration, the two bundle-scoped Mach exceptions, signed-feed verification, and update verification before extraction. The downloader XPC service remains disabled because the main app already has outbound network access.

### 2. False formal-release success — guarded

Failure mode: absent credentials could silently produce an ad-hoc or unsigned artifact and later steps could publish it.

Correction: formal mode checks credentials before assembly, distinguishes development artifacts in their names and reports, and permits no fallback. Publication occurs only after every architecture, provider, Apple, Gatekeeper, and EdDSA gate has completed.

### 3. Outer-container-only notarization — guarded

Failure mode: a stapled DMG may open offline while the application copied out of it has no stapled ticket.

Correction: each application is notarized and stapled before DMG creation. The final mounted DMG gate validates the inner application ticket separately from the outer DMG ticket.

### 4. Signing stale bytes — guarded

Failure mode: stapling changes DMG bytes, invalidating a previously calculated EdDSA signature.

Correction: appcast generation and EdDSA verification occur only after the final DMG has been stapled and re-verified.

### 5. Private feed host — explicitly blocked

Failure mode: a valid app could embed a feed URL that requires GitHub authentication, causing every user update check to fail.

Correction: the manifest requires public HTTPS URLs and formal release checks repository/feed reachability. Development builds may use an explicit non-release local configuration, but cannot pass formal validation.

### 6. Provider claims without credentials — explicitly blocked

Failure mode: recorded fixtures could be reported as current online compatibility.

Correction: fixture contracts and live release contracts are separate result classes. Missing credentials produce a blocking result for a Provider that is enabled in the signed release configuration, never a skip that counts as green.

## Remaining external gates

- Developer ID signing identity and Apple notarization credentials;
- Sparkle Ed25519 signing key pair;
- public HTTPS feed/download host or a public repository decision;
- protected OpenAI and DeepSeek credentials and current-account live contracts;
- initial release version and final release publication authorization.

These gates do not prevent implementation and development validation. They do prevent Ticket 10 from being marked complete or a release from being published until real evidence exists.
