# Native acceptance follow-up review — 2026-09-06

Scope: the bounded runner and stage diagnostics added in this follow-up, plus interpretation of their acceptance evidence. Not the whole uncommitted Ticket 20 diff; no claim of ticket completion or PR readiness.

## Code review

- **① Underlying premises:** earlier key-window setup failures are documented but not reproduced this round. Existing source passed repeated native runs before changes. The proposed focus-competition explanation remains unconfirmed; no product/window activation rewrite was made. Default runner rebuilds the current source to avoid stale-artifact passes.
- **② Runtime behavior:** exit 0 alone was demonstrated insufficient using `/usr/bin/true`; the runner rejects it. The timeout branch was exercised against the real test executable with a 0.01-second limit and returned 124. Each native run has an independent child and a finite timeout. Failure stops the aggregate rather than skipping the sample. Build has its own 60-second deadline; it is separate from the 20-second native deadline.
- **③ Safety:** fixture key and private pasteboard only; no network or Keychain requests. Production insertion was mutated only temporarily, restored with an exact patch and rebuilt. Subprocess arguments do not use a shell; no broad process-name termination. Stage logs are constant identifiers, never credential data.
- **④ Consistency:** no new runtime product behavior, visuals, localization keys or geometry. Feature-catalog descriptions are unchanged by this follow-up. Existing harness modes are retained; the false root-cause hypothesis is not enshrined in comments. No additional refactor is proposed here.

## Test review

- **1. Coverage:** enumerate current boundaries: native context-menu lifecycle/Paste result/caret/unchanged clipboard; keyboard Paste with hidden/revealed fields; Edit hierarchy/selectors/localization/native-responder fallback; typed/pasted values, clear and refill, Validate/Return; unsafe-input suppression; selection-preserving visibility. Repeated runs cover the existing tests, not unimplemented draft/switch/submit-race requirements. Physical input, active-window visual parity, and live persistence remain gaps with explicit acceptance conditions in the tasklist.
- **2. Case design:** production management window and native secure editor are used; completion is checked after the assertions, not merely after opening a window. Context menu is opened through AppKit and its action invoked programmatically after tracking ends. This tests the native action boundary, not mouse hit-testing into the macOS context menu. Private clipboard preserves isolation.
- **3. False-pass checks:** actual insertion suppression followed by rebuild produces a content assertion failure; restoration/rebuild makes it green. This proves sensitivity to missing insertion, not every potential context-menu defect. Zero-exit/no-marker and deadline controls were separately rejected. Final 10-run stage-logged gate passed. The original 97-minute tool call has no diagnosed internal cause and is not described as repaired.

No whole-ticket review approval is issued. Remaining requirements and final installed-app/manual acceptance stay open under Ticket 20, not silently waived by these checks.
