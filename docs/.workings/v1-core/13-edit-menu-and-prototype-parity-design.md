# Ticket 13 — Edit menu and confirmed prototype parity design

## Scope and source of truth

This ticket implements two already-confirmed contracts:

1. `docs/prototypes/application-menu/prototype-edit-menu.html` defines the complete native Edit menu.
2. The selected prototypes under `docs/prototypes/` define the information hierarchy, state vocabulary, layout density, and explicit geometry for every production surface.

The production app remains native AppKit/SwiftUI. Native controls, typography rasterization, menus, sheets, and accessibility behavior are not replaced with HTML. “Parity” means the same hierarchy, controls, state content, dimensions explicitly accepted by the user, and interaction outcomes. Intentional divergence requires updating and reconfirming the prototype first.

## Confirmed facts

- `Sources/VLMSnapperApp/main.swift:3` creates and runs `NSApplication`, but the application currently never installs `NSApp.mainMenu`.
- `Sources/VLMSnapperApp/VLMSnapperApplicationDelegate.swift:17` composes the production app without an application-menu builder.
- `VLMSnapper/UI/ProviderSetupView.swift:4` uses a standard text field, so the missing application Edit menu prevents normal Command-V routing rather than the field needing a custom clipboard implementation.
- `VLMSnapper/UI/MenuBarPanelView.swift:9` exposes only a minimal recent-item presentation; it cannot represent the confirmed thumbnail, operation/time, and status rows.
- `VLMSnapper/UI/ScreenCapturePermissionRecoveryView.swift:4` is a compact prompt, while the confirmed permission-recovery prototype is a structured recovery sheet.
- `VLMSnapper/UI/ManagementCenterView.swift:140` has the shared shell, but Provider settings still opens the setup sheet instead of presenting the confirmed provider cards in the settings page.
- Existing Ticket 07–10 rendering tests prove that views can render, but their PNG assertions do not prove hierarchy or geometry parity.

## Application menu contract

`VLMSnapperApplicationMenuBuilder` creates the native top-level Application, File, Edit, Window, and Help menus. Menu labels come from `VLMSnapperStrings` so English and Simplified Chinese stay key-parity checked.

The Edit submenu contains, in order:

1. Undo and Redo.
2. Cut, Copy, Paste, Paste and Match Style, Delete, and Select All.
3. Find submenu: Find, Find Next, Find Previous, Use Selection for Find, and Jump to Selection.
4. Spelling and Grammar submenu.
5. Substitutions submenu.
6. Transformations submenu.
7. Speech submenu.
8. Start Dictation.
9. Emoji & Symbols.

Text-editing items have `target == nil` and standard AppKit selectors. AppKit therefore resolves the active field editor through the responder chain and performs automatic validation. Find commands use `performTextFinderAction(_:)` with `NSTextFinder.Action` tags. Emoji & Symbols targets `NSApplication`; Dictation uses the platform selector and remains responder-driven.

The application installs the menu after localization is configured and rebuilds it before a language-triggered relaunch. Provider fields must not add custom Command-V handlers.

## Prototype-to-production matrix

| Surface | Confirmed contract | Production change |
| --- | --- | --- |
| Application menu | Complete native Edit menu; responder-based enablement | Add AppKit menu builder, localization, selector/shortcut tests, and application wiring |
| Menu bar panel | 370 pt panel, provider state in header, 36 pt primary capture, inline update notice, rich recent rows, two-column footer | Expand presentation model from real history/provider/update state and rebuild panel hierarchy |
| Onboarding | Single readiness checklist; permission and Provider are blockers; privacy is informative; one blocker notice | Align row geometry, state affordances, copy hierarchy, and readiness message |
| Storage privacy | Flat continuous detail sheet; no card grid and no “Open Storage Settings” action | Keep a single attached surface and align section rhythm/copy wrapping |
| Provider setup | 8 pt split sheet; Provider states in sidebar; validation keeps key editor and reveals model selector beneath | Preserve session behavior while aligning dimensions, subtitles, badges, footer, and narrow-layout constraints |
| Permission recovery | Attached structured panel with explanation, two recovery steps, footer note, cancel, and primary action | Replace the compact prompt while preserving the existing permission coordinator |
| Capture toolbar | 4 pt selection gap, 3 pt internal padding/gap, 25 pt controls, 6 pt corners | Retain current accepted constants and add an independent contract assertion |
| Result workspace | Header operation switcher, provider/language context, screenshot and result cards, original/translation sections, copy actions, status footer | Rebuild presentation around the existing workspace snapshot; show only data actually available |
| Management center | Shared sidebar shell; history type filter left/search right; rich record detail; inline Provider cards; flat General sections | Reuse existing management actions while replacing the sheet-only Provider page and aligning shell geometry |

The current companion prototype does not contain a standalone “Check for Updates” row. The panel therefore shows update state only when an update is available; manual checking remains in General Settings. This latest confirmed prototype supersedes the older panel-row wording in the spec and feature catalog.

## Production data rules

- Provider badge uses the selected configured Provider and readiness state. No Provider is shown as available before configuration.
- Recent rows come from persisted history and expose actual operation, creation time, terminal status, and managed screenshot thumbnail when available.
- Result workspace shows the actual captured PNG and current streamed/final slots. It does not invent saved paths, latency, dimensions, or Provider results.
- Provider setup/sidebar and Management Provider cards use the complete persisted configuration map, not only the currently selected setup snapshot. Selecting or editing a Provider may open the existing setup flow, but every row must preserve its own configured/model state.
- Empty and failure states use localized production copy; prototype sample records are harness fixtures only.

## User-operation failure modes

1. User focuses an API-key field and presses Command-V: Paste targets the field editor and inserts clipboard text.
2. No editable responder exists: Paste and destructive edit items disable through native menu validation rather than failing silently.
3. User changes focus between fields: menu enablement and target resolution follow the new first responder.
4. User opens the left-click panel before configuring a Provider: the header reports setup required; Capture still routes to Provider setup.
5. User has no history: the recent section shows the production empty state without prototype samples.
6. Screenshot file is missing: the recent row/detail uses a safe placeholder and does not fail panel rendering.
7. Update state changes while the panel is open: the inline notice reflects the shared lifecycle snapshot; no stale downloaded state is fabricated.
8. Provider validation succeeds: the key editor stays in place and the model selector appears below it; no automatic model selection occurs.
9. Provider model list refresh removes the selected model: existing coordinator semantics clear it and the page shows model selection required.
10. Permission is denied or revoked: the structured recovery sheet explains the steps and performs only the existing explicit request/settings/restart actions.
11. Streaming result is partial: result sections render available partial text while preserving the operation state.
12. Management search/type filter changes: selection resolves to a visible record or the correct empty state; detail never shows a filtered-out stale record.
13. Narrow windows or long Provider/model labels: controls truncate within their columns and do not displace icons or primary actions.
14. English, Simplified Chinese, light, and dark appearance: hierarchy remains stable and every user-facing string comes from localization.

## TDD seams and vertical slices

1. Application-menu contract: fail on missing full hierarchy, selectors, targets, shortcuts, tags, localization, and responder Paste; implement only the menu builder and wiring.
2. Menu-panel presentation: fail on mapping real history/provider/update state into the confirmed row/header model; implement mapper and view hierarchy.
3. Recovery/setup/onboarding: fail on independent geometry/state contracts; implement each native surface without changing core coordinators.
4. Management center: fail on navigation/filter/provider-summary contracts; implement the shared-shell parity slice.
5. Result workspace and toolbar: fail on independent hierarchy/geometry contracts; implement missing workspace presentation and preserve accepted toolbar constants.
6. Rendering evidence: render every production surface for English/Chinese and light/dark, inspect the actual images, and correct visible divergence.

Tests must define expected menu order and accepted geometry independently from implementation constants. Screenshot byte count alone is not an acceptance gate.

## Validation gates

- Focused test after each red/green slice.
- Strict Swift/C warnings-as-errors build.
- Full Swift test suite.
- Real AppKit responder-chain Paste integration test.
- Named native renders for every surface in both languages and appearances, followed by visual inspection.
- Localization key parity and user-facing literal scan.
- `git diff --check` and source/test CJK scan.
- Updated `review-code.md`, `review-tests.md`, `final-regression.md`, spec, feature catalog, checklist, and prototype manifest.

## Out of scope

- Screenshot annotation or image editing.
- Local vision-model support.
- New Provider adapters or changes to request/retry semantics.
- New history fields solely to reproduce prototype demo metadata.
- Replacing standard AppKit controls with custom HTML-like widgets.
