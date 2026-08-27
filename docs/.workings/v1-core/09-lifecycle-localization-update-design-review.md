# Ticket 09 — Design review

## Reviewed assumptions

1. **No production executable yet** — Ticket 09 can implement and render the application-level modules and native adapters, but cannot truthfully claim signed process, login-item, or updater installation validation. Those remain explicit Ticket 10 gates.
2. **Single instance must precede side effects** — election is one startup interface, not checks scattered around database, hotkey, cleanup, and updater constructors.
3. **A lock file is not a lease** — only the held kernel lock proves ownership, so a crash cannot permanently block launch.
4. **Diagnostics need structural privacy** — a typed event without a message field is safer than redacting arbitrary strings after collection.
5. **Language strategy differs from language value** — persisting `system` preserves future system changes; concrete resolution happens before the first frame.
6. **Login registration has an approval state** — `register()` returning without an error cannot be rendered as enabled until status is reread.
7. **Sparkle owns download truth** — the public custom user-driver reply begins download; delegate/user-driver callbacks, not UI taps or timers, determine downloading and ready states.
8. **The confirmed decision supersedes the old spec** — automatic downloading and its preference are removed everywhere before implementation.

## Interface review

- Primary startup exposes one high-leverage outcome and a lifetime lease. Deleting the module would spread ordering and ownership rules across every subsystem, so it earns its seam.
- Diagnostics accept one typed event and expose cleanup/export. Sanitization, naming, retention, JSON encoding, gzip, and continuation behavior stay local.
- Language resolution is pure and independently testable; UserDefaults and Bundle lookup are adapters rather than part of the resolver interface.
- Login item maps a small product state over the wider ServiceManagement status surface.
- Update UI consumes one snapshot plus explicit intents. Sparkle types do not leak into menu/settings, and test adapters can drive every transition without network or an appcast.

## Risks and gates

- `DistributedNotificationCenter` and `NSRunningApplication` wake behavior can differ in an App Sandbox and simultaneous cold launch; the kernel lock protects correctness, while signed integration decides whether activation needs a different adapter.
- A custom `SPUUserDriver` is a larger adapter than the standard controller, but it is required for a product-owned Download button through public Sparkle interfaces. Missing protocol callbacks must fail safe and receive direct adapter tests.
- Sparkle feed URLs, EdDSA key, architecture routing, `SUEnableAutomaticChecks`, `SUAllowsAutomaticUpdates`, and the 21,600-second interval belong to signed product configuration in Ticket 10. Ticket 09 tests adapter configuration and state, not a fake release.
- Gzip output must be mutation-tested against decompression and exact allowlisted JSON; an extension alone is not compression evidence.

## Decision

The reviewed design covers Ticket 09 without moving release/signing claims forward. Implementation may proceed test-first at the five public seams, then extend the confirmed UI and run rendering/full-package gates.
