# Provider Refresh presentation follow-up

Approved: Refresh A, with model help/error sharing one content-sized row. No additional empty error block.

- [x] Prototype confirmation: user approved compact help/error replacement and continuing implementation.
- [x] Baseline: continue the existing dirty Ticket 23 branch without discarding pending work; fetched origin for comparison.
- [x] TDD: real coordinator + suspended model-list boundary; preserve configuration while busy, success/failure/card return and exclusivity.
- [x] Native UI: fixed Refresh progress, stable credential/footer controls, inline model error feedback; both languages.
- [x] Strict build and all Swift test partitions: 331 non-App + 11 App + 2 isolated XCTest methods; six Python cases and 58-row ownership gate; shell syntax and diff whitespace passed.
- [x] Native render evidence: 24 current-source images (two languages, two appearances, two widths, three states); representative normal/busy/failure surfaces visually compared. These are not physical-click acceptance.
- [x] Review code independently, record findings.
- [x] Review tests independently, record findings and red evidence.
- [x] Spec/features consistency and scoped final regression. Do not claim full Ticket 23 closure from this fix.
- [x] Installed-app physical Refresh acceptance: user confirmed build 27 after local installation on 2026-09-08.
- [ ] Full Ticket 23 release/feature gates remain separate; this accepted increment does not close the ticket.

Test seams: ProviderSetupSession public operations/snapshots backed by the real ProviderConfigurationCoordinator, injected model-list API and in-memory credential/metadata storage; native ManagementCenterView presentation tests.

## 2026-09-08 — User-requested local installation

Built current worktree (base af4ffcd plus pending changes) as arm64 0.1.0 build 27. Developer ID signing, embedded profile/entitlements verification, package verification and isolated Data Protection Keychain CRUD passed. Old App exited normally through its Quit action. Installed at `/Applications/VLMSnapper.app`; previous build 26 retained at `/Applications/VLMSnapper.app.backup-20260908-162412-build26`. Installed executable matches the verified build and was launched. No user configuration/TCC reset, real Provider key read, force termination, push, release or notarization. Physical Refresh acceptance remains pending. Build/sign/verify logs: `/private/tmp/vlmsnapper-refresh-{build27,sign27,verify27}.log`.

Evidence: `/private/tmp/provider-refresh-{red,red2,green1,core,render,strict,full,app,native-paste,native-closed}.log`. The first red is the incorrect validating phase; the second red is lost configuration and discarded completion after switching back. Compiler/setup errors are not red evidence. Render output is under the system temporary directory's `vlmsnapper-provider-refresh-renders/`. The added application test drives the production Refresh callback through HTTP parsing and observes busy → 503 → manual retry, not only a manually constructed snapshot.

## 2026-09-08 — Acceptance and publication authorization

The user confirmed the installed build 27 and then explicitly requested pushing and merging. Publish the current accepted application-test wiring and Refresh follow-up as an incremental change; keep Ticket 23 in-progress with its outstanding full-feature visual/reconciliation gates. This authorization does not request a tag, release or further installation. The installation entry above records the earlier pending checkpoint; physical Refresh acceptance is now passed by the user, not inferred from render tests.
