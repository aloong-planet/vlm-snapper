# Capture self-exclusion code review

## 2026-09-03

### 【① 底层前提】

- Apple SDK header `SCShareableContent.h` declares `getCurrentProcessShareableContentWithCompletionHandler` as available from macOS 14.4 and describes the returned content as the windows, displays, and applications available to the current process. Building against a 14.0 package baseline failed at this API availability boundary; the 14.4 baseline compiles.
- The current-process application and every display passed to `SCContentFilter` come from one `SCShareableContent` value. The global fallback creates a second complete snapshot and does not retain objects from the failed primary snapshot.
- A command-line ScreenCaptureKit probe did not return within 60 seconds and was stopped. It is not treated as evidence about the signed application. Compositor-level exclusion remains an explicit signed-App integration check.

Conclusion: the API availability and same-snapshot object provenance are supported by current SDK and build evidence. The real compositing result is not claimed from unit tests or the CLI probe.

### 【② 可运行性】

- Success path: freeze all usable displays, create and display replacement overlays, commit the new capture generation, hide the toolbar, retire a terminal saved workspace if reserved, retire the known menu/management/onboarding sources, then cancel the previous selection session.
- Discovery, permission, all-display, and overlay-presentation failures clear only the pending request, cancel only the new capture session, and restore the reserved result workspace. A failed replacement keeps the previous overlay intact.
- Stale capture results and callbacks are guarded by request and active-selection generations. A newly opened workspace prevents an older pending request from committing.
- Review found one same-level escape: a replacement-capture failure alert could be hidden behind the still-valid `.screenSaver` overlay. The alert now uses a level immediately above that overlay only when an overlay is present.
- The previous pre-hide and next-run-loop coordinators were removed from the live code. A repository-wide source search found no remaining live references; matches only remain in historical `docs/.workings/v1-core/` records, which are preserved as historical construction notes.

Conclusion: after fixing the alert level, the enumerated success, failure, cancellation, retrigger, and stale-callback paths retain a valid current workspace or selection and do not expose a partially retired UI state.

### 【③ 安全正确性】

- Failure to resolve the current process or any display from one snapshot fails closed; the capture never falls back to including VLMSnapper windows.
- No Provider credential, screenshot path, network request, history schema, or user input boundary changed.
- Source retirement targets explicit VLMSnapper controllers. It does not enumerate or hide arbitrary `NSApp.windows`.

Conclusion: no new input, persistence, credential, or cross-application authority was introduced. Self-exclusion fails closed.

### 【④ 一致性】

- `Package.swift`, app `Info.plist`, architecture build triples, packaged-app verification, release appcast validation, specification, feature catalog, and ADR all state macOS 14.4.
- The feature catalog and specification no longer claim that menu, result, or management windows hide before freezing.
- Source and test names are English; no user-visible copy was added, so the enabled i18n dictionaries require no new keys.
- The removed dismissal coordinator was speculative generality after capture stopped depending on popover closure. Its removal is limited to the files already changed for this behavior.

Conclusion: current code and authoritative documentation use the same capture order and minimum-system contract. No deferred refactor is required for this change.
