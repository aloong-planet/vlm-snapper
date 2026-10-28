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
durable home yet and is handed to the user for a decision. The re-check after the
post-implementation test review is below.

## 2026-10-28 re-check after the post-implementation test review

Scope: changes in `8bd52f2..533de26` plus the uncommitted finding-12 record
fix, the postmortem and the features sentence below. Same language census and
per-language searches as above.

### Stage 1: changed declarations

| Changed declaration surface | Compared with | Conclusion |
|---|---|---|
| Spec REQ-005/AC-05 added sentence (replaced selection ends while pending) | `cancelCapture` active branch (`533de26`), test A12 | True |
| `docs/features/v1-core.md` display-change sentence (capture freezing to replace that selection ends with it; next shortcut opens at once) | Spec AC-05 and AC-01 | Consistent, user-visible terms only |
| `docs/postmortems/pending-capture-overlay-pitfalls.md` (new) | `review-code.md` findings, `review-tests.md` findings 9-12, `tasklist.md` run counts | Each cause chain and count matches its record |
| Test-file header (CI native cases, two new gaps) | `ci.yml`, `Scripts/test-local-regression.sh`, actual tests | True |
| v1-core checklist rows REQ-005/AC-01/02/03/05/06 | Tests at `533de26` | True |
| Test review and code review records | Findings 2-12 and their handling | Consistent; finding 2 left to the user |

### Stage 2: related declarations

| Relation | Derivation | Conclusion |
|---|---|---|
| Postmortem file ↔ an index | `ls docs/postmortems`; `grep -rn 'postmortems/' docs CONTEXT.md AGENTS.md` (only `docs-layout.md`, which lists the directory) | No index exists for postmortems; nothing to update |
| Spec AC-05 ↔ features ↔ CONTEXT ↔ ADRs | `grep -rn -E '被替换.{0,40}(显示器\|失效)\|显示器变化.{0,60}(替换\|快捷键)' CONTEXT.md AGENTS.md docs/specs docs/features docs/adr` (only spec AC-05) and `grep -rn -i -E 'replac.{0,60}(display\|disconnect)\|display change.{0,80}(replac\|shortcut)' …same paths` (no match; the new features sentence was read directly in Stage 1) | Features updated; CONTEXT and ADRs carry no statement about this edge |
| Spec Testing Decisions (composition tests) ↔ new tests A11, A12 | Read of the REQ-005 testing paragraph | Paragraph names the observables used; still true |

### Stage 3: events

| Event | Follow-up | Conclusion |
|---|---|---|
| Product defect fixed (finding 10) | Spec, features, postmortem | All three updated |
| Test infrastructure rule already landed (fixture identity) | Spec Testing Decisions | Unchanged, still true |
| `Pending:` notes | Expiry check | Unchanged |
| Requirement identifiers | No new identifier; AC-05 extended in place | Nothing to verify |

### Closeout conclusion

All rows converged after the re-check. Items handed to the user: the missing
`capabilities.toml` (mutation testing and working language unconfirmed), CI's
single-file shell syntax check, and adding the thrown-operation native case to
CI and the local gate.

## 2026-10-28 re-check after user feedback on the installed build (window-open animation)

Scope: `0829955..HEAD` (fix `17dbf8d`, test and records `fa6b881`) plus the
documentation of this round. Trigger: the user's failure report on the
installed 0.1.2 (`install.md`). Language census of the touched files
(`perl` count of Han and Latin characters): features English (2 Han
characters), spec, ADR-0013, postmortem and checklist Chinese with English
identifiers; every search below has a Chinese and an English pattern.

### Stage 1: changed declarations

| Changed declaration surface | Compared with | Conclusion |
|---|---|---|
| Spec REQ-005/AC-01 clause (first frame covers the whole display, no growing open animation) | `animationBehavior = .none` in the overlay panel; test "the pending overlay covers each display without an opening animation"; screen recording of 0.1.3 (5/5 full on the first frame) | True |
| Spec Implementation Decisions sentence (overlay windows disable the open animation) | Overlay panel init | True |
| Spec Testing Decisions sentence (frame and window-server bounds stay full; animation behavior is the in-process observable; first-frame coverage by recording) | Probe and test in `measurements.md`, `review-tests.md` U3 | True |
| `docs/features/v1-core.md` capture paragraph ("covering each whole display from its first frame") | Spec AC-01 | Consistent, user-visible terms only |
| ADR-0013 background, option 6, consequences | `measurements.md` on-screen table and in-process variants | Numbers match the recorded runs after the corrections in this round (old build 278–574 ms, new 82–161 ms, median 91 ms; reuse differences −2–22 and 15–33 ms) |
| Postmortem item 4, title and intro count | `review-code.md`, `measurements.md` | Cause chain, frame columns and counts match; the earlier unverified "300 ms" wording was removed here and in `review-code.md` |
| v1-core checklist row REQ-005/AC-01 | Test logs, recording, user message | True; user's re-check of 0.1.3 recorded as not yet done |
| Code comment on the panel and test comment | Probe (frame and bounds unchanged during the animation) | Causal statements verified |

### Stage 2: related declarations

| Relation | Derivation | Conclusion |
|---|---|---|
| Feature, spec, ADR files ↔ README rows | Titles and one-line summaries unchanged | Rows still true |
| Postmortem ↔ an index | No postmortem index (first round) | Nothing to update |
| Fact "overlay covers the whole display at once" ↔ other statements | `grep -rn -E '打开动画\|窗口动画\|由小到大\|整屏\|覆盖整块\|铺满' CONTEXT.md AGENTS.md docs/specs docs/features docs/adr docs/postmortems VLMSnapper/Resources/Localization` and `grep -rn -i -E 'animation(Behavior)?\|whole display\|full[- ]screen\|first frame\|dims the live' …same paths plus VLMSnapper/UI` | Hits: spec AC-01, ADR-0013 (updated), ADR-0010 "不等待窗口动画" (capture timing, unrelated, still true), management-center "铺满" lines (unrelated), the two `animationBehavior = .none` settings |
| Latency figures ↔ other statements | `grep -rn -E '4[–-]11\|160[–-]325\|10[–-]30 ?ms' CONTEXT.md AGENTS.md docs/specs docs/features docs/adr docs/postmortems` (no README or site directory exists) | Only ADR-0013; background, option 6 and consequences corrected to on-screen figures |
| Rule "overlay windows disable the open animation" ↔ the gate guarding it | `.github/workflows/ci.yml` line 36 runs `swift test --skip ProviderApplicationTests`, which includes the overlay controller suite; local gate non-app stage ran it (`logs/gate-full-animation-fix.log`) | Guarded in CI and locally; the visible effect itself is guarded only by the recorded measurement |
| Localised strings | No string changed | Nothing to check |

### Stage 3: events

| Event | Follow-up | Conclusion |
|---|---|---|
| User failure feedback on installed 0.1.2 | AC-01 reopened and extended, fix, test, checklist row, `install.md` quote | Done; the user's hands-on check of 0.1.3 is a deferred acceptance item |
| Postmortem item count 3 → 4 | `grep -rn -E '三个问题\|三个坑' docs CONTEXT.md` (outside `docs/.workings`) and `grep -rn -i -E 'three (problems\|pitfalls\|issues)' docs/postmortems docs/specs docs/features docs/adr docs/agents` | No other statement enumerates them |
| New rule (overlay open animation off) | Canonical home | Spec Implementation Decisions (plus code comment) |
| Earlier measurement claim found to be main-thread only | ADR-0013, `measurements.md` correction note | Corrected in place |
| Local reinstall 0.1.3 | `install.md` | Recorded |
| `Pending:` notes | Expiry check | REQ-005 Pending (signed app on macOS 14.4–15) unchanged and not expired |
| Requirement identifiers | AC-01 extended in place | No new identifier |

### Closeout conclusion

All rows converged. Deferred: the user's hands-on check of 0.1.3. Items handed
to the user earlier are unchanged.

