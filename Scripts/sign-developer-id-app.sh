#!/bin/bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <app> <signing-identity> <profile> <signing-tool> <output-metadata>" >&2
    exit 64
fi

app="$1"
signing_identity="$2"
profile="$3"
signing_tool="$4"
output_metadata="$5"
project_root="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$app" ]]
[[ -f "$profile" ]]
[[ -x "$signing_tool" ]]
if [[ -e "$output_metadata" ]]; then
    echo "Signing metadata output already exists: $output_metadata" >&2
    exit 73
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-signing.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT
effective_entitlements="$temporary_root/effective-entitlements.plist"

"$signing_tool" prepare \
    "$profile" \
    com.loong.vlmsnapper \
    "$signing_identity" \
    "$project_root/Distribution/VLMSnapper.entitlements" \
    "$effective_entitlements" \
    "$output_metadata"

/usr/bin/ditto "$profile" "$app/Contents/embedded.provisionprofile"
framework="$app/Contents/Frameworks/Sparkle.framework"
sparkle="$framework/Versions/Current"
for signable in \
    "$sparkle/XPCServices/Downloader.xpc" \
    "$sparkle/XPCServices/Installer.xpc" \
    "$sparkle/Updater.app" \
    "$sparkle/Autoupdate" \
    "$framework"; do
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --preserve-metadata=identifier,entitlements,requirements \
        --sign "$signing_identity" \
        "$signable"
done
/usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$effective_entitlements" \
    --sign "$signing_identity" \
    "$app"

"$project_root/Scripts/verify-developer-id-app.sh" \
    "$app" \
    "$output_metadata" \
    "$signing_identity"
