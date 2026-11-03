# macOS signing and notarization

This page explains the inputs and guarantees of the installer builds. The commands themselves are declared under `macos-distribution` in `capabilities.toml`.

## Local builds

The `local` profile builds arm64, x64 and universal DMGs under `release/<version>-development/`. Its DMGs are ad-hoc signed and not notarized, so they are only for development.

`VERSION`, `BUILD_VERSION`, `APPCAST_BASE_URL`, `SPARKLE_PUBLIC_ED_KEY` and `OUTPUT_ROOT` are optional and have development defaults.

## Release builds

The `release` profile builds the same three architectures. For each one it:

1. Signs the app with Developer ID and embeds the provisioning profile.
2. Notarizes and staples the app, then does the same for its DMG.
3. Checks the final DMG with `verify-macos-app.sh`, `spctl` and `stapler`.
4. Generates the Sparkle appcast and verifies its signatures.

The universal app also runs a Data Protection Keychain check after signing. Any failure stops the whole release, and files reach the output directory only after all three architectures pass. That directory must not already exist.

### Command inputs

Set these before running the `release` command:

| Variable | Value |
|---|---|
| `VERSION` | Marketing version |
| `BUILD_VERSION` | Build version, which must increase with each release |
| `APPCAST_BASE_URL` | Public HTTPS directory for the appcasts |
| `DOWNLOAD_BASE_URL` | Public HTTPS directory for the DMGs |
| `SPARKLE_PUBLIC_KEY` | Sparkle public key, which must match the private key below |
| `OUTPUT_ROOT` | Output directory |

The script also reads these credentials from the environment:

| Variable | Value |
|---|---|
| `MACOS_SIGNING_IDENTITY` | Developer ID Application identity |
| `MACOS_NOTARY_PROFILE` | `notarytool` keychain profile |
| `SPARKLE_PRIVATE_KEY_FILE` | File holding the Sparkle private key |
| `MACOS_PROVISIONING_PROFILE` | Developer ID provisioning profile for `com.loong.vlmsnapper` |

The provisioning profile and private key stay outside the repository. The Sparkle tools must already exist under `.build/artifacts`, so resolve the Swift packages first.

## CI

- `ci.yml` builds the three development packages on every pull request and on pushes to `main`.
- `formal-release-verification.yml` is the release gate and runs only when started manually. It checks the live Provider contracts, installs the credentials into a temporary keychain, runs the release build and uploads the result as the `VLMSnapper-<version>-verified` artifact.

The formal workflow does not publish anything. Publishing the verified files is a separate manual step.

### Workflow secrets

- Signing: `MACOS_DEVELOPER_ID_P12_BASE64`, `MACOS_DEVELOPER_ID_P12_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `MACOS_BUILD_KEYCHAIN_PASSWORD`, `MACOS_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`
- Notarization: `MACOS_NOTARY_APPLE_ID`, `MACOS_NOTARY_TEAM_ID`, `MACOS_NOTARY_PASSWORD`
- Sparkle: `SPARKLE_PRIVATE_KEY`, `SPARKLE_PUBLIC_KEY`
- Live Provider gate: `OPENAI_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, plus the `VLMSNAPPER_OPENAI_MODEL`, `VLMSNAPPER_GEMINI_MODEL` and `VLMSNAPPER_DEEPSEEK_MODEL` repository variables
