# Ticket 26 — test review

Ticket: [26 — Make the DeepSeek reasoning timeout test deterministic](issues/26-deterministic-reasoning-timeout-test.md).

## Design review (2026-10-28)

Implementation base: `8c00b2d` (`origin/main`). Scope: the one rewritten test in
`Tests/VLMSnapperCoreTests/ProviderAdapterExecutorTests.swift`.

### Test design table

| # | Spec | Seam | Driving input | Assertion and expected-value source | Fixture shape | Expensive resources |
|---|---|---|---|---|---|---|
| T1 | v1-core §6 (reasoning refreshes the first-text deadline), Seam 2 | `ProviderAdapterExecutor.stream` with injected transport and timeout clock (existing seam: other tests here inject `ProviderTimeoutClock`) | DeepSeek stream: reasoning, reasoning, text, `[DONE]`; after each reasoning event the transport waits until the clock has armed a new first-text deadline, then fires the deadline armed before that event | events = `sourceDelta("Hello")`, metadata `chat_reasoning`, `completed` (unchanged literals); a deadline that was not superseded fires and fails the stream with `.firstTextTimeout` | recorded DeepSeek chat-completions SSE shape (`reasoning_content`, then `content`), unchanged from the current test | none |

### Dimension 1: Coverage

Same behaviour as before (§6 reasoning refresh); the race on real time is removed. The manual clock
also drives the failure branch: if reasoning did not supersede the deadline, firing it ends the stream.

### Dimension 2: Case design

Public seam with the existing clock injection; no internal state read. The clock completes a sleep only
when the test fires it and ends it on cancellation, as the real clock does.

### Dimension 3: False greens (design-time checks)

The test turns red when a deadline survives a reasoning event (to be shown with a temporary mutation of
the coordinator). A guard bounds the wait for a new deadline so a missing re-arm fails instead of
hanging. Expected events are literals.

### Dimension 4: Resource reuse

No expensive resource.

### Findings

None.
