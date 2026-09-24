#!/bin/bash
# Explicit paid-network gate; uses synthetic images, never production history.
set -euo pipefail
umask 077
usage() {
    echo "Usage: $0 <openai|gemini|deepseek> <model> <report.json> [--keychain]"
    echo "Runs extraction and translation once each; no retries. Default credentials: API-key env vars."
    echo "--keychain requires MACOS_SIGNING_IDENTITY; profile defaults to the installed App profile."
}
if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then usage; exit 0; fi
if [[ $# -lt 3 || $# -gt 4 ]]; then usage >&2; exit 64; fi
provider="$1"
model="$2"
report="$3"
case "$provider" in openai|gemini|deepseek) ;; *) usage >&2; exit 64 ;; esac
if [[ -z "${model//[[:space:]]/}" || "$model" == --* || -z "$report" ]]; then usage >&2; exit 64; fi
if [[ $# -eq 4 && "$4" != --keychain ]]; then usage >&2; exit 64; fi
if [[ "$report" != /* ]]; then report="$PWD/$report"; fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ $# -eq 4 ]]; then
    : "${MACOS_SIGNING_IDENTITY:?Required for protected Keychain test access}"
    profile="${MACOS_PROVISIONING_PROFILE:-/Applications/VLMSnapper.app/Contents/embedded.provisionprofile}"
    [[ -f "$profile" ]]
fi
swift build --product VLMSnapperLiveProviderGate
bin="$(swift build --show-bin-path)"
executable="$bin/VLMSnapperLiveProviderGate"
credential_args=()
if [[ $# -eq 4 ]]; then
    swift build --product VLMSnapperSigningTool
    staging_root="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-live-gate.XXXXXX")"
    trap 'rm -rf "$staging_root"' EXIT
    app="$staging_root/LiveProviderGate.app"
    mkdir -p "$app/Contents/MacOS"
    cp "$executable" "$app/Contents/MacOS/VLMSnapperLiveProviderGate"
    cp Distribution/LiveProviderGate-Info.plist "$app/Contents/Info.plist"
    cp "$profile" "$app/Contents/embedded.provisionprofile"
    "$bin/VLMSnapperSigningTool" prepare "$profile" com.loong.vlmsnapper \
        "$MACOS_SIGNING_IDENTITY" Distribution/LiveProviderGate.entitlements \
        "$staging_root/entitlements.plist" "$staging_root/signing.plist"
    codesign --force --sign "$MACOS_SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$staging_root/entitlements.plist" "$app"
    bash Scripts/verify-developer-id-app.sh "$app" "$staging_root/signing.plist" "$MACOS_SIGNING_IDENTITY"
    executable="$app/Contents/MacOS/VLMSnapperLiveProviderGate"
    credential_args=(--keychain)
fi
echo "Live gate: $provider / $model; two requests maximum; report: $report"
"$executable" --provider "$provider" --model "$model" --output "$report" "${credential_args[@]}"
