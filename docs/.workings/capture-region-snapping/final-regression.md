# Capture region snapping — final documentation regression

## 2026-10-28

Scope: this change only (no ticket), `8c00b2d..HEAD` on `feat/capture-region-snapping`, code at
`5c96041`. Feature slug `v1-core`. Language census (`perl` Han/Latin counts): CONTEXT, spec, ADR-0014 and
the v1-core checklist are Chinese with English identifiers; the feature catalogue and prototype README
are English. Every search below has a Chinese and an English pattern.

### Stage 1: changed declarations

| Changed declaration surface | Compared with | Conclusion |
|---|---|---|
| Spec Solution sentence, §3 bullet, v1-core::REQ-006 AC-01–11, FM-47 | Implementation at `5c96041` (spec final check in `tasklist.md`) | True; installed-build checks pending (real window list, Dock/menu-bar geometry, physical hover) |
| Spec Implementation Decisions (window list, Dock strip, newest overlay, no Accessibility) | Resolver, adapter, controller, model guard | True; the newest-overlay rule written back from the code review |
| Spec Testing Decisions paragraph for REQ-006 | Tests C1–C7, U1–U12, A1–A6 and their fixtures | True after the 2026-10-28 correction: crop end points are judged at the overlay controller (U12), toolbar position in the app tests; gaps listed (auto-hide visible frame, latency, two displays) |
| Spec Prototype Coverage sentence, Out of Scope (window detection removed; Dock icons, element detection, toggles listed) | Confirmed prototype; user decisions of 2026-10-28 | True |
| `docs/features/v1-core.md` capture paragraph (region outline, click, drag, no single Dock icons) | Spec REQ-006 user-visible layer | Consistent; no implementation terms |
| `docs/adr/0014-snap-regions-from-window-list.md` | Spec and features | Not contradicted; spec cites ADR-0014 and the range 0001–0014 |
| `CONTEXT.md` term 吸附区域 and invariant (same moment as the frozen frame) | Spec REQ-006, implementation (own PID excluded, clipped to the display) | Same terms; invariant enforced by the resolver and the newest-overlay rule |
| Prototypes: snap-region page, toolbar page (1 px, no handles/label), shared CSS/JS, README, manifest | User decisions; implementation (1 pt accent border, no handles/label, no hairline) | Consistent with the app; colour tokens approximate the system accent (prototype-side reference) |
| v1-core checklist source table and REQ-006 coverage row | Sources in this conversation; gate log | True; coverage row marks installed-build checks as pending |

### Stage 2: related declarations

| Relation | Derivation | Conclusion |
|---|---|---|
| ADR-0014 ↔ `docs/adr/README.md` row | New ADR | Row added, title and status match |
| Feature file ↔ `docs/features/README.md` row | Row: "菜单栏截图、在线模型提取与翻译…" | Still true (capture covers region selection) |
| Spec ↔ `docs/specs/README.md` row | Row scope "截图、视觉模型文字提取…" | Still true |
| Prototype page ↔ `manifest.js` entry and capture-overlay README | New page | Entry `capture-overlay/snap-region` and README section added |
| Fact "window auto-detection is out of scope" ↔ other statements | `grep -rn -E '窗口自动识别\|自动识别窗口\|窗口识别' CONTEXT.md AGENTS.md docs --include='*.md'` and `grep -rn -i -E 'window (auto.?)?detect\|auto.?detect\|window recogn' …same` (excluding `docs/.workings/`) | No remaining statement |
| ADR range ↔ statements | `grep -rn -E 'ADR-0001 至\|0001.{0,4}001[34]\|ADRs? 0001' CONTEXT.md AGENTS.md docs/specs docs/features docs/adr/README.md` | Only the spec range sentence; reads 0001–0014 |
| Localised strings ↔ new behaviour | `git diff --stat 8c00b2d..HEAD -- VLMSnapper/Resources/Localization` (empty) | No new text: the highlight has no label, as REQ-006/AC-01 requires |
| Permission explanation (features line on screen access) ↔ new window list | Window bounds need no extra permission; no titles read | Still true |
| Rule "capture-overlay prototypes share tokens and toolbar" ↔ `docs/prototypes/check-shared-blocks.mjs` | Script checks both pages for stylesheet, script and declaration, plus a reverse check | Covered (`shared-blocks:ok:4`) |

### Stage 3: events

| Event | Follow-up | Conclusion |
|---|---|---|
| Out of Scope reversed (window detection now in scope) | Stage 2 search rows | No stale statement |
| New general rules: same-moment invariant; window list only to the newest overlay; app is the reference for the selection look | Canonical homes | CONTEXT invariant; spec Implementation Decisions; spec Prototype Coverage and prototype README |
| Two defects fixed during review | `review-code.md`, red/green logs | Recorded; no postmortem: caught by the review before any test run or user exposure |
| `Pending:` notes in scope | REQ-005 Pending (signed app, macOS 14.4–15) | Unchanged, not expired; no new Pending (installed-build checks happen before delivery) |
| Enumerable dimensions (providers, languages) | None changed | Nothing to check |
| Deferred work: `capabilities.toml` | User decision 2026-10-28: separate PR after this feature | Durable home: project memory note (outside the repository by the user's choice of a later PR) |

### Closeout conclusion

All rows converged as of `5c96041` plus the documentation commits. Remaining before delivery: the
post-implementation test check (running), installed-build checks, the final full gate.
