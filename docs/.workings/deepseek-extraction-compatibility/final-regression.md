# Final documentation regression: DeepSeek extraction compatibility

Date: 2026-09-02

## Phase 1: declaration-to-implementation check

| Declaration | Verified implementation and tests | Result |
| --- | --- | --- |
| `docs/specs/v1-core.md` Provider adapter seam | DeepSeek extraction alone accepts the observed `text` field and emits canonical source events; translation and other Providers stay strict. | Consistent |
| ADR-0011 experimental model boundary | The canonical prompt is preferred, the exact observed alias is defensive, extra output fails, and the protected gate reports both operations independently. | Consistent |
| `docs/features/v1-core.md` Extract behavior | A real DeepSeek extraction result shape succeeds without adding a second request, automatic retry, or relaxed completion checks. | Consistent |

## Phase 2: relationship check

| Relationship | Check | Result |
| --- | --- | --- |
| Spec and feature catalog | Both describe one user action as one request and preserve immediate normalized failure. | Consistent |
| Spec and ADR | Both limit compatibility to DeepSeek extraction and retain canonical normalized events. | Consistent |
| ADR and release gate | The gate now executes and serializes `extract` and `translate` separately with redacted evidence. | Consistent |
| Context vocabulary | No product term, actor, or state-machine term changed; `CONTEXT.md` needs no update. | No change required |
| Prototype coverage | No user-visible layout, control, text, or interaction changed. | No prototype update required |
| i18n capability | No user-visible string changed. | No localization update required |
| Same-fact search | Repository-wide searches of report construction and parser initialization found no stale alternate contract in the changed scope. | Consistent |

## Phase 3: event and gate check

| Event or gate | Outcome |
| --- | --- |
| User-visible feature behavior changed | Updated the existing v1 feature catalog in the same change. |
| Provider member count or configuration surface changed | No; OpenAI, Gemini, and DeepSeek remain the same three Providers. |
| Formal release readiness changed | No. The synthetic DeepSeek extraction/translation contract passed, but the existing Pending items for request-size limits and the wider protected contract matrix remain. |
| New cross-project rule introduced | No; no `AGENTS.md`, project capability table, or global skill update is required. |
| Working evidence treated as authority | No; final behavior is declared in the spec, ADR, and feature catalog. This file records only the reconciliation. |

## Final result

The touched implementation, tests, spec, ADR, and feature catalog agree. Remaining release limitations stay explicitly Pending and are not represented as completed by this repair.
