# Test review: DeepSeek extraction compatibility

Date: 2026-09-02

## Behavioral coverage

- A sanitized fixture reproduces the observed DeepSeek Chat Completions stream whose extraction JSON contains only `text`; it must emit canonical source deltas, metadata, usage, and completion.
- DeepSeek translation rejects the `text` alias.
- DeepSeek extraction rejects the alias when any extra field is present.
- The outbound extraction prompt requires the canonical `source` shape.
- The live gate sends both extraction and translation requests, reports them separately, preserves per-operation request metadata, and does not short-circuit the second operation after the first fails.
- Missing configuration, blank configuration, normalized request failure, and incomplete output remain covered.

## Test-quality review

The observed-response fixture is based on sanitized real API structure rather than the desired specification, so it can detect the original mismatch. Assertions use public decoder events and serialized report fields instead of private parser state.

During mutation review, the combined live-gate test attempted a positional array access after its report-count assertion failed, producing an out-of-range crash. The test now locates reports by operation with a required-value assertion, so a missing report fails diagnostically without masking the cause.

## Mutation evidence

1. Removing `text` from the DeepSeek extraction allowlist made `observedTextFieldIsNormalizedForExtraction` fail with `malformedOutput`; restoring the compatibility made it pass.
2. Reducing the live gate to translation only made `configuredProviderPassesCompleteExtractionAndTranslation` fail because the extraction report and request were absent; restoring both operations made it pass.
3. Before the prompt change, the exact prompt-contract test failed against the previous generic wording; it passes only with the canonical `source` instruction.

## Validation evidence

- Targeted live-gate suite: 8 tests passed.
- Final full build: passed.
- Final full suite: 237 tests in 63 suites passed.
- Protected live DeepSeek gate with a generated PNG: extraction passed in 2,453 ms and translation passed in 2,206 ms; the other unconfigured Providers were reported as blocked.

The user's original screenshot was not resent after the repair because the system denied that external upload without explicit authorization. This leaves an end-to-end replay gap for that exact image, but not for the sanitized response-shape regression or the synthetic live Provider contract.

## Findings

No unresolved false-positive or missing regression assertion remains in the changed test scope. The exact user-image replay remains an explicit external-validation gap.
