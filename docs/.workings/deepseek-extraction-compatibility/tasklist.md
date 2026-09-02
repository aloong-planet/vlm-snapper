# DeepSeek extraction compatibility repair

- [x] TDD: reproduce and normalize the observed DeepSeek `text` extraction field through the public stream decoder.
- [x] TDD: make the DeepSeek extraction prompt require the canonical `source` field.
- [x] TDD: make the protected live Provider gate exercise both extraction and translation.
- [x] Run targeted and full validation gates.
- [x] Complete the independent code review and record it in `review-code.md`.
- [x] Complete the independent test review and record it in `review-tests.md`.
- [x] Reconcile the spec, feature catalog, ADR, context, and release-gate documentation; record all three final-regression stages.
- [x] Commit, push, and open a pull request without AI attribution.

## Test seams

- `DeepSeekChatStreamDecoder.consume`: replay the sanitized shape of the observed live SSE response.
- `ProviderRequestFactory.makeRequest`: inspect the outbound DeepSeek request contract.
- `LiveProviderContractGate.run`: verify that release validation requests and reports both supported operations.
