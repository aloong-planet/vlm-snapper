# 17 — DeepSeek reasoning stream activity

Status: complete

Blocked by: none

## Goal

Prevent the DeepSeek experimental vision model from failing the 10-second
first-text deadline while it is continuously emitting valid reasoning stream
activity that is intentionally not shown to the user.

## Acceptance

- A valid non-empty DeepSeek `reasoning_content` delta resets the current
  10-second inactivity deadline without entering the public Provider event
  stream or result text.
- Before visible text begins, a subsequent 10 seconds with no valid activity
  still fails as `first_text_timeout`; after visible text begins, 10 seconds
  without activity still fails as `stream_stalled`.
- The 90-second total request deadline remains unchanged and cannot be extended
  by reasoning activity.
- OpenAI and Gemini timeout behavior remains unchanged.
- The recorded real response shape is covered by a deterministic regression
  test that is observed red before the implementation and green afterward.
- The same authorized source PNG completes 10 sequential DeepSeek extraction
  requests through the production adapter without a first-text timeout.
- Focused tests, the full test suite, code review, test review, and documentation
  consistency checks pass.

## Task list

- [x] Record the deterministic regression test red state.
- [x] Implement private DeepSeek activity propagation and timeout reset.
- [x] Run focused and full verification gates.
- [x] Run 10 authorized live extraction requests with the original PNG.
- [x] Complete code and test reviews.
- [x] Synchronize the spec, feature catalog, ADR evidence, and final regression.

## Comments

- 2026-09-02: Installed build 15 persisted `first_text_timeout` after 10,015 ms.
- 2026-09-02: Ten raw authorized requests with the same PNG all completed with
  valid `source` JSON. First visible content ranged from 4,151 to 16,676 ms;
  4 of 10 exceeded 10 seconds, while reasoning started within 577 to 1,144 ms.
- 2026-09-02: The focused executor regression failed before implementation with
  `firstTextTimeout` after 68 ms and passed after the private activity path was
  implemented.
- 2026-09-02: A second scope regression failed while buffered ordinary content
  was incorrectly treated as private activity, then passed after activity was
  narrowed to non-empty `reasoning_content` only.
- 2026-09-02: Ten sequential extraction requests with the exact authorized PNG
  passed through the production `ProviderAdapterExecutor`. Durations were
  8,112, 9,045, 8,845, 9,669, 6,484, 19,827, 6,396, 9,156, 7,633, and 16,234 ms;
  minimum 6,396 ms, median 8,945 ms, mean 10,140.1 ms, maximum 19,827 ms. Two
  requests exceeded 10 seconds overall and still completed; no request failed
  with `first_text_timeout`.
- 2026-09-02: The complete concurrent suite passed with 239 tests in 63 suites,
  and the warnings-as-errors build completed successfully.
