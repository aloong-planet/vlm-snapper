# Instant capture overlay final documentation regression

## 2026-10-28

Scope: this change only (no ticket), `850f64d..HEAD` plus uncommitted
documentation at the time of writing. Feature slug `v1-core`. Follows the
per-change layout of earlier `docs/.workings/<change>/final-regression.md`
reports. Searched files use Chinese and English (character census: CONTEXT,
spec, ADRs, READMEs and AGENTS contain both; the feature catalogue is English
apart from one quoted label), so every search below has one pattern per
language.

### Stage 1: changed declarations

| Changed declaration surface | Compared with | Conclusion |
|---|---|---|
| `docs/specs/v1-core.md` Solution, §3 entry bullet, §6 workspace bullet, FM-23, FM-25 | Implementation (`beginCapture`, `commit`, `withdrawPendingCapture`, `abandonPendingCapture`) | True: overlay first, sources and workspace retired after the frozen frame shows, rollback on failure |
| `docs/specs/v1-core.md` `v1-core::REQ-005` AC-01–07 | Implementation and tests (spec final check in `tasklist.md`) | True; parts not driven by tests are the REQ-005 Pending and the gaps listed in the test-file header (rechecked after the post-implementation findings 3-6) |
| `docs/specs/v1-core.md` Implementation Decisions, Testing Decisions, Prototype Coverage, Further Notes | Implementation, tests, fixture | True; fixture identity rule matches the committed fixture |
| `docs/features/v1-core.md` capture, workspace and management-center sentences | Spec user-visible layer | Consistent: immediate selection view, frozen image in place, Esc while pending, retirement after the frozen image; no implementation terms |
| `docs/adr/0013-show-pending-overlay-before-freezing.md` | Spec and features | Not contradicted; spec cites ADR-0013 and ADR range 0001–0013 |
| `docs/adr/0010-…` appended revision note | ADR-0013 decision | Consistent; earlier decision text left unchanged (append-only) |
| `CONTEXT.md` two relationship sentences | Spec FM-25 and §3 | Same order and terms (选区遮罩, 冻结帧, 来源界面); no new term needed because the pending overlay is not a separately visible concept |
| `VLMSnapper/UI/FrozenCaptureOverlayController.swift` comments | Measured behaviour (`measurements.md`, `review-code.md`) | Causal statements limited to verified facts |
| `Tests/VLMSnapperAppTests/ProviderApplicationTests.swift` header gaps | Actual test reach | True: hit testing, compositor exclusion, two-display and modal-alert paths are not reached |
| Prototype `docs/prototypes/capture-overlay/` | Implementation | Unaffected: it covers the post-selection toolbar; overlay appearance unchanged |

### Stage 2: related declarations

| Relation | Derivation | Conclusion |
|---|---|---|
| ADR file ↔ `docs/adr/README.md` row | New ADR-0013 | Row added with matching title and status |
| Spec ↔ `docs/specs/README.md` row | Spec scope unchanged | Row still true |
| Feature file ↔ `docs/features/README.md` row | One-line summary unchanged | Row still true |
| Fact "overlay appears only after freezing" ↔ statements elsewhere | `grep -rn -E '冻结.{0,40}(遮罩\|再显示\|后显示\|再原子)\|遮罩.{0,30}(显示后\|成功显示\|成功覆盖)\|先冻结' CONTEXT.md AGENTS.md docs` and `grep -rn -i -E 'after.{0,30}(overlay\|freez)\|before.{0,20}(overlay\|freez)\|freeze first\|overlay (is )?(visible\|ready\|appears)' Sources VLMSnapper Scripts docs/features` (excluding `docs/.workings/` history) | Hits were the spec, CONTEXT lines 111/116, features and ADR-0010; all updated or covered by the append-only revision note. Historical construction notes are not authoritative and stay unchanged |
| Localised strings ↔ capture order | `grep -rn -E '冻结\|遮罩' Sources VLMSnapper Scripts`; English dictionary checked by key | Only `capture.failed.body` (no frame from any display), still true |
| Rule "checklist owns every spec requirement" ↔ `Scripts/verify-feature-checklist.py` | Gate reads only `US-`/`FM-` rows of the ownership section | REQ-005 coverage is recorded in the checklist's source → spec table and guarded by review, not by this gate |
| Rule "release scripts are syntax-checked" ↔ CI `bash -n Scripts/*.sh` | Read of `.github/workflows/ci.yml` | Finding (pre-existing, outside this change): `bash -n` treats files after the first as arguments, so CI checks only the first script; `Scripts/test-local-regression.sh` checks each file. Reported to the user for a decision |

### Stage 3: events

| Event | Follow-up | Conclusion |
|---|---|---|
| ADR count changed 12 → 13 | `grep -rn -E 'ADR-0001 至\|0001.{0,4}0012\|ADR-0012' docs CONTEXT.md AGENTS.md` | Only the spec range sentence enumerates ADRs; updated to 0013 |
| New `Pending:` (REQ-005 signed-app compositing and physical clicks on macOS 14.4–15) | Expiry check | Not expired; condition stated as a checkable product fact |
| Existing `Pending:` notes (REQ-001 hardware, Provider limits, DeepSeek model) | Expiry check | Unaffected by this change |
| New rule: non-opaque capture windows take mouse events explicitly | Canonical home | Spec Implementation Decisions (plus code comment) |
| New rule: fixtures identify pre-existing windows by retained identity, not address | Canonical home | Spec Testing Decisions (composition fixture paragraph) |
| New evidence for open Ticket 24 (toolbar wait during a locked session) | Ticket comment | Appended to `docs/.workings/v1-core/issues/24-native-test-wait-timeouts.md` with the preserved log |
| Requirement identifier allocation | `git log --all -S 'REQ-004'` (hit: open PR #34), `git log --all -S 'REQ-005'` (none) | REQ-005 used; recorded in the v1-core checklist |

### Closeout conclusion

All rows converged. One out-of-scope finding (CI shell-syntax coverage) has no
durable home yet and is handed to the user for a decision. This report is
re-checked after the post-implementation test review in case it changes code,
tests or documentation.
