# ADR-0016: File the application tests by module

- Status: Accepted (2026-11-10)

## Context

The application tests in `Tests/VLMSnapperAppTests` run through the whole application, and were split out of one 4,375-line file so that someone changing one module reads and runs a small set of tests. The Core tests are already filed in a folder per module, the clusters in the contents of `docs/CONTEXT.md`. The `/tdd` placement rule files tests that run through the whole application by the feature document whose rule they assert, named with its slug and split only by that document's sections. In this repository one feature document, `docs/features/v1-core.md`, covers every application test, so the two layouts give different files.

## Options

1. **File the application tests by module, in a folder per cluster of `docs/CONTEXT.md` as the Core tests are, with a file per subject inside each folder**
2. File them by the sections of `docs/features/v1-core.md`, with names that carry `v1-core` — rejected by the user on 2026-11-10: it leaves the application tests in a different layout from every other test target, and a module's tests no longer sit in one folder.

## Decision

We adopt **option 1**. A test in `Tests/VLMSnapperAppTests` goes in the folder of the module it tests and is named for what it tests. Helpers shared by these files stay in `Tests/VLMSnapperAppTests/Support`. A placement check for these tests reads the module folder, not the feature document.

## Consequences

- Positive: every test target has the same layout, and the tests of one module sit in one folder of each target.
- Negative: one section of the feature document can have its tests in more than one folder. "Extract and translate operations", for example, is tested in `CaptureAndResults` and in `ModelsAndProviders`.
- Negative: this departs from the `/tdd` placement rule, so a review that applies the rule has to read this ADR.
- Neutral: the other `/tdd` rules, on layers, duplicate tests and shared helpers, still apply to these tests.

## Sources

- The user's request of 2026-11-04 to trim the tests and split them by module.
- The user's decision of 2026-11-10, in the review of the application-test split, to keep the module layout.
- The contents of `docs/CONTEXT.md`, for the module clusters.
