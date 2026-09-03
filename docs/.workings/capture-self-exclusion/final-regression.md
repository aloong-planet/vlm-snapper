# Capture self-exclusion final documentation regression

## 2026-09-03

### Stage 1: statement-to-source verification

| Changed declaration surface | Comparison | Conclusion |
|---|---|---|
| `docs/specs/v1-core.md` | Capture success/failure sequences against application model, capturer, overlay, and controller changes | Matches the final freeze-first, fail-closed, atomic-replacement behavior; compositor verification is explicitly assigned to a signed app |
| `docs/features/v1-core.md` | User-visible capture behavior against specification and implementation | Describes excluded VLMSnapper windows, post-overlay hiding, failure preservation, and macOS 14.4 without introducing framework details in the changed capability text |
| ADR-0010 | Decision against same-snapshot filter construction and overlay transaction | Matches current implementation and records the macOS 14.4 tradeoff |
| `CONTEXT.md` | Menu, management center, and result-workspace terminology against spec/features | Uses one capture-order invariant: freeze while visible, then retire after overlay success |
| Package, plist, build, verify, and release scripts | Minimum-version declarations and gates against built artifact | Every active declaration is 14.4; fresh arm64 artifact reports Mach-O `minos 14.4` and passes verification |
| Localization dictionaries | Project capability declaration says i18n is enabled | No user-visible copy changed, so no key or translation update is required |
| Confirmed prototypes | Visual hierarchy and spacing against UI changes | No visual design or copy changed; only capture timing/window retirement changed, so existing prototypes remain valid |

### Stage 2: relationship verification

| Relationship | Enumeration or comparison | Conclusion |
|---|---|---|
| Spec file to spec index | `docs/specs/README.md` entry against unchanged spec title and scope | No index update required |
| ADR file to ADR index | `docs/adr/README.md` entry 0010 against unchanged title/status | No index update required |
| Feature file to feature index | `docs/features/` contains no README index | No index counterpart exists |
| Capture-order statements elsewhere | Repository search for pre-hide/close-before-freeze wording outside historical working notes | Authoritative spec, feature catalog, ADR, and CONTEXT agree; old statements remain only in preserved historical `docs/.workings/v1-core/` records |
| Minimum system statements elsewhere | Search for active `14.0`, `macOS 14+`, and `macosx14.0` declarations excluding vendor/build/history outputs | No active contradictory declaration remains; the old implementation-ticket note is historical and not authoritative |
| Minimum-version rule to gates | Package/plist declarations against build triples, packaged verifier, and appcast check | Build, verification, and release surfaces all enforce 14.4 |

### Stage 3: event verification

| Event | Required follow-up | Conclusion |
|---|---|---|
| Supported platform minimum changed from macOS 14.0 to 14.4 | Recheck every active minimum-version declaration and release gate | Completed; all active declarations and gates are 14.4 |
| Capture source-retirement order changed | Recheck every active capture-order statement and user-visible behavior description | Completed; pre-hide statements were rewritten to freeze first and hide after overlay success |
| New general invariant: never mix ScreenCaptureKit objects from different shareable-content snapshots | Record the rule in a durable design source | Recorded in ADR-0010 and the v1 specification |
| Pending notes | Search the changed authoritative documents for `Pending:` | Two existing Provider release-readiness notes remain; neither was introduced or made due by this capture change |
| Enumerated product members | Provider, language, channel, and operation member counts | Unchanged; no enumerated-member wording needs revision |

All queued statement/relationship checks converged without an unresolved documentation change.
