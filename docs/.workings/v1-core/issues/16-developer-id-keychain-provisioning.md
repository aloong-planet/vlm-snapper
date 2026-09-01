# 16 — Developer ID Keychain provisioning

Status: completed

Blocked by: none

## Goal

让三个 Developer ID 发行架构在正式签名时嵌入匹配的分发 provisioning profile，并由 profile 动态派生应用身份与精确 Keychain access group，从而使已签名应用能够可靠使用 Data Protection Keychain；任何 profile、签名声明或真实 Keychain 验收不一致都必须在公证和发布前 fail closed。

## Acceptance

- 正式发布把 provisioning profile 视为仓库外必需输入；缺失、损坏、过期、渠道错误或身份不匹配时在签名前失败，不生成降级发行物。
- profile 的 App ID Prefix、Team ID、application identifier 与 Keychain allowlist 经验证后生成最终 App 的精确签名 entitlements，不硬编码账号前缀。
- profile 必须包含当前 Developer ID Application 签名证书，并在最终外层 App 签名前嵌入 `Contents/embedded.provisionprofile`。
- 嵌套代码按 nested-first 顺序签名，外层 App 最后签名；正式签名不使用 `codesign --deep` 代替逐层签名。
- Universal、arm64 与 x64 三个最终 App 均验证嵌入 profile、签名证书、hardened runtime、secure timestamp 与实际 entitlement 一致性。
- Universal 最终签名 App 在公证前执行 Data Protection Keychain 增、读、改、删烟测，使用随机假凭据并尽力清理；失败阻止整个版本。
- GitHub Actions 从受保护 secret 临时还原 profile，权限最小化并在 job 结束时清理；profile、解码 plist、派生 entitlements 与任何凭据均不进入仓库或 artifact。
- API Key 验证成功但 Keychain 写入失败时保留输入、拒绝保存 Provider 配置，并归类为本地安全存储错误。
- 聚焦测试、完整测试、shell 语法/契约测试、本地真实 Developer ID 签名验收、代码 review、测试 review 与文档一致性回归全部通过。

## Tasklist

- [x] Add profile contract tests and implement profile validation plus dynamic entitlement derivation.
- [x] Add signed bundle verification for all distribution architectures.
- [x] Add the app-owned Data Protection Keychain CRUD smoke-test entry point and release gate.
- [x] Wire the external profile into local release and GitHub Actions with fail-closed cleanup.
- [x] Preserve API key input and report local secure-storage failures accurately.
- [x] Run focused and full validation, including the downloaded real profile and local Developer ID signature.
- [x] Complete `/review-code` and resolve its findings.
- [x] Complete `/review-tests` and resolve its findings.
- [x] Run `/features-catalog` and final cross-document regression.
- [x] Commit, push, and open a PR without merging it.

## Comments

- 2026-09-01: The downloaded Developer ID distribution profile was decoded outside the Codex sandbox and confirmed to authorize `RHQ28XS7D9.com.loong.vlmsnapper` plus `RHQ28XS7D9.*`, include a DER profile, and contain the installed Developer ID Application certificate.
- 2026-09-01: This change introduces no new page, control, spacing, color, or user-visible state shape. It restores the existing local-storage error category, so the prototype gate is explicitly skipped.
- 2026-09-01: arm64, x64, and Universal temporary applications passed real Developer ID profile/signature verification. The final signed Universal process also passed Data Protection Keychain add/read/update/delete, and the full Xcode test run passed 229 tests in 61 suites.
