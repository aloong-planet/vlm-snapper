# Ticket 23 — 2026-09-08 visual audit

## Scope and conclusion

Audited merged commit `0febbb48fcd9acccdefc67dc9015ebf92605511c` (#27). This is a visual audit, not a product change or full-feature closeout. **Visual consistency remains open.** No implementation, prototype, installed app, release or GitHub state was changed.

Following `ui-design`, fresh native renders were inspected rather than treating test success as visual acceptance. Following `features-catalog`, findings remain owned by Ticket 23 and its visual-consistency criterion; the approved design is not rewritten to match an unapproved implementation deviation.

## Evidence and limits

- Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun swift test --filter Ticket13RenderingTests`.
- Result: exit 0; three tests passed. The primary matrix generated 52 PNGs, all visually inspected. The separately generated 24 Refresh state PNGs and cleared-candidate PNG were not individually reviewed in this audit; generation alone is not acceptance.
- Preserved primary renders: `/private/tmp/vlmsnapper-visual-audit-20260908.3wrZcw/vlmsnapper-ticket13-renders/`; log: `/private/tmp/vlmsnapper-visual-audit-20260908.3wrZcw/render.log`. These are local temporary evidence, not committed assets.
- The browser rejected access to the local HTML prototype under its URL security policy. No alternate browser, copied/served URL or indirect browser execution was used. Prototype comparison here is against its local source and confirmed README contract, **not fresh browser pixels**.
- `Ticket13RenderingTests.swift:473` renders fixed-size, borderless, non-key `NSWindow` content. This does not establish real titlebar safety, menu-bar anchoring, focus, foreground/background behavior, hover, scrolling reachability or animated transitions.
- According to the project capability declaration, i18n is enabled: English and Simplified Chinese were inspected in light/dark appearance. RTL mirroring is not enabled; that check is skipped.

## Coverage matrix

Every row below includes `en-light`, `en-dark`, `zhHans-light`, `zhHans-dark`. Sizes are content points, not PNG pixels. A page inspected does not imply all its interactive states were covered.

| Surface / file prefix | Size | Observation |
|---|---|---|
| Menu / `menu` | 300 × 394 | Capture label centered, narrow panel retained; English update title truncates. Fixed-height fixture prevents a product-level conclusion about panel clipping. |
| Onboarding / `onboarding` | 760 × 540 | Required cards and actions visible; confirmed structure differences VA-01. |
| Permission recovery / `permission` | 620 × 390 | Headline, instructions and footer actions readable in all four renders; OS positioning not tested. |
| Storage/privacy / `privacy` | 620 × 520 | Four information sections visible; English fills more height. Actual window fitting remains unverified. |
| Result / `result` | minimum 1020 × 620 | Top operation controls and two-column content visible; no content-level header overlap observed. Real titlebar and active control styling unverified. |
| History / `management` | 1200 × 720 | List/detail/metrics visible; Chinese filter label differs from prototype (VA-04). |
| History / `management-minimum` | 920 × 620 | Filter/search and detail remain within content bounds; long model ID wraps. Same VA-04. |
| General settings / `management-general` | 1200 × 720 | Initial viewport readable; Diagnostics and lower scroll content are not fully covered by this static render. |
| Provider / `management-provider` | 1200 × 720 | Two columns visible; control geometry and footer styles differ (VA-02/03). |
| Provider / `management-provider-minimum` | 920 × 620 | Columns stack; model control does not fill the row like the prototype. |
| Capture toolbar / `toolbar` | 780 × 320 fixture canvas | Single-row controls visible; real screen-edge placement and material against arbitrary desktop not established. |
| Provider recovery / `provider-recovering` | 920 × 620 | Recovery status readable; this fixture covers initial load, not a previously populated busy card. |
| Provider storage error / `provider-storage-error` | 920 × 620 | Error copy wraps and actions remain in bounds. |

## Findings and ownership

All findings below belong to **Ticket 23 visual consistency**. Recommend resolving the established layout/style differences before marking that criterion complete. This audit does not authorize implementation or new icon choices.

### VA-01 — Onboarding does not reproduce confirmed Direction A

- Native: `VLMSnapper/UI/OnboardingView.swift:28` uses a separate full-width heading/divider; the blocker is a plain warning label; footer places Finish Later at the far left and Start Using at the far right. Readiness icons are bare symbols (`:125`).
- Prototype: `docs/prototypes/onboarding/prototype-structure-directions.html:127` and `:219` define an app-mark/intro group; `:133` and `:225` define a tinted bordered gate with heading/detail; `:230` groups both actions on the right and places the privacy note on the left. Direction A is selected in its README.
- Impact: all onboarding language/appearance variants. The flow may work, but the information hierarchy and composition remain different.
- Recommendation: align the native introduction, gate and footer to the confirmed structure; keep permission/Provider gating semantics unchanged. App-mark selection must respect the existing icon approval process.

### VA-02 — Provider model row geometry differs

- Native: `ManagementCenterView.swift:662` uses two fixed 400-point columns. At `:780`, the model `Picker` has no full-width/32-point shell; Refresh uses a 104 × 24 label inside native button chrome. In minimum-width renders the dropdown/Refresh group leaves unused horizontal space.
- Prototype: `prototype-management-center.html:102` uses a 1:1.1 flexible grid; `:118`–`:121` define a stretching model selector, 32-point controls and 128-point Refresh button. The grid stacks below the `:196` breakpoint.
- Impact: configured Provider cards in both wide and narrow layouts; the key/model controls do not form the same aligned row.
- Recommendation: preserve the accepted stable Refresh busy/error presentation while aligning selector expansion, overall control height and button width. Verify actual control bounds, not just label bounds.

### VA-03 — Provider footer and field-label styling differs

- Native: `ManagementCenterView.swift:625` leaves Remove Configuration in the default button style; renders show a filled gray button rather than the prototype's red text action. `:633` explicitly paints Currently Used with secondary text. `:684` uses a headline API Key label.
- Prototype: `prototype-management-center.html:150` defines a transparent destructive action, `:147` a green current-provider note and `:104` a smaller secondary field label.
- Impact: configured Provider cards in both appearances. Recommendation: align these explicit visual roles; do not infer that `.destructive` alone guarantees the required macOS appearance.
- Existing unresolved icon discrepancy remains: prototype DS/OA/G letter marks versus native shared CPU symbol. Do not silently copy letter icons or choose replacements. This pre-existing decision is already assigned to Ticket 23; the audit did not enumerate every icon carrier in the repository.

### VA-04 — History adds a visible filter label absent from prototype

- Native: `ManagementCenterView.swift:340` supplies `operationSelector` to a segmented Picker without `.labelsHidden()`. The Chinese renders show “操作类型”; English renders do not show an equivalent label in the same space.
- Prototype: `prototype-management-center.html:231` exposes the filter name through `aria-label`, not a visible preceding label.
- Impact: Chinese History at default/minimum widths; segment widths and starting position differ. Recommendation: preserve the accessible label but suppress its visible layout if following the confirmed prototype.

### VA-05 — English menu update title truncates at the accepted 300-point width

- Evidence: `menu-en-light.png` and `menu-en-dark.png`; the title is shortened to “VLMSnapper 1.1.0 is a…”.
- Source: `MenuBarPanelView.swift:378` applies a single-line limit while sharing width with update icon and Download button.
- Impact: available-update state, English. Download remains visible, so this is a lower-priority readability issue, not an inaccessible update action.
- Recommendation: evaluate shorter localized title or better row allocation without widening the user-approved panel; retain under Ticket 23 until decided.

## Evidence artifacts: do not report as established App bugs

- Menu arrow/bottom clipping in some fixed-size images: production `MenuBarPanelController` sizes to fitting content; the render fixture forces height 394. Requires real-panel confirmation, not changing the App to fit the fixture.
- English target-language names inside Chinese result/toolbar images are hardcoded test inputs (`Ticket13RenderingTests.swift:395`, `:413`), not proof of a production localization failure.
- English recent/history content and missing menu thumbnails are fixture data, not evidence of untranslated UI or failed real-image loading.
- Some synthetic history images lose their drawn title across fixture renders. `sampleImage` uses an `NSImage` drawing closure (`:461`); no real saved-image regression is established here. Repeat with a deterministic image before drawing a product conclusion.
- Inactive native segmented/button coloring is not sufficient evidence of the active App appearance; do not force colors based on a non-key test window.

## Why render tests did not reject these differences

`Ticket13RenderingTests.swift:265` checks expected filenames; `:497` checks that PNG data exceeds 10 KB. These ensure render production, not agreement with a visual baseline. A changed layout can still satisfy both checks. Keep these generation checks, but complete human side-by-side review and add targeted geometry assertions for the accepted contracts; do not describe these tests as pixel-parity gates.

## Remaining acceptance

1. Resolve VA-01–04 against the confirmed design, decide VA-05 and the already-pending Provider icon choice.
2. Obtain permitted prototype screenshots/render access for same-state, same-size comparison. Browser-policy denial must not be bypassed.

## 2026-09-08 follow-up — user approved items 1–4

Implemented on `codex/align-confirmed-visuals` from merged `0febbb48fcd9acccdefc67dc9015ebf92605511c`. The preceding audit remains the historical baseline.

| Item | Correction and evidence |
|---|---|
| VA-01 | Native onboarding now follows intro/brand, icon-card/status, tinted readiness and grouped-footer composition. Content 900×604 with a 760-point readable column. Four fresh bilingual light/dark renders checked; initial English footer clipping at old size fixed. |
| VA-02 | Flexible 1:1.1 fields, full-width 32-point native model picker and 128×32 Refresh; eight normal/minimum Provider renders inspected. Real native bounds first failed against 24-point/143-point baseline and pass after replacement. |
| VA-03 | API Key secondary heading; red transparent Remove Configuration; green Current status; outlined Refresh/current-selection actions. Same Provider renders plus sampled idle/busy/failure images inspected. |
| VA-04 | Extra visible operation-filter label removed while the accessible label remains. Eight normal/minimum History renders inspected; no filtering logic changed. |

Current evidence: `/private/tmp/vlmsnapper-visual-alignment-evidence.NxghbV/surfaces/` and `refresh/`. Preview artifacts are native view renders, not installed-app screenshots. Existing synthetic-image/title and inactive-control limitations above still apply.

The new native menu test run timed out once while waiting for the management key window, before Paste; unchanged isolated rerun passed. This is not a stable-native-acceptance claim. VA-05, prototype Provider icon choice, full same-state browser/native comparison and physical window/hover checks remain in Ticket 23. No installed App was changed.
3. Verify real active windows, menu anchoring/outside-click dismissal, focus/hover, and scrolled General Settings content. Retain prior manual acceptance separately; this audit does not invalidate it or extend it to untested states.
4. Re-run the visual matrix after any approved fixes and the complete Ticket 23 closeout gates. No visual or full-ticket checkbox is marked complete by this report.
