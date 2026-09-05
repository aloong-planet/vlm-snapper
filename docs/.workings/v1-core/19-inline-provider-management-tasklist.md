# Ticket 19 implementation tasklist

- [x] Verify the confirmed management-center and onboarding prototypes cover every user-visible Ticket 19 change.
- [x] Audit commits `340bcf3` and `a97bd73` against all six Ticket 19 acceptance criteria without including later Ticket 20-22 draft changes.
- [x] Run the focused Provider presentation, onboarding, configuration, and setup-session tests against an isolated `a97bd73` source snapshot.
- [x] Run strict build, complete tests, localization parity, prototype syntax, render-contract checks, and `git diff --check` against that snapshot.
- [x] Capture fresh normal and narrow production renders and verify the confirmed structural geometry.
- [x] Prove the retired standalone Provider setup surface is absent from production sources, harnesses, tests, localization, prototypes, and manifests while retaining the non-UI `ProviderSetupSession` domain type.
- [x] Reconcile every Ticket 19 criterion to a gate, test, or reproducible evidence artifact.
- [x] Run `/review-code` and save the Ticket 19 review to `docs/.workings/v1-core/review-code.md`.
- [x] Run `/review-tests` and save the Ticket 19 review to `docs/.workings/v1-core/review-tests.md`.
- [x] Perform the Ticket 19 spec read-only terminal audit, then run `/features-catalog` consistency closeout for this user-visible change.

## Execution note

Ticket 19 was published after its implementation commits already existed. The original red-green history therefore cannot be recreated honestly. This pass treated the exact `a97bd73` tree as the implementation candidate, validated its public seams and render evidence in isolation, and added the missing confirmed geometry through a new red-green cycle. The first red was a missing-symbol compile failure, so test review also changed all four values by one point and verified four correctly attributed assertion failures before restoring the accepted values.
