#!/bin/bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 <version> <build-version> <appcast-base-url> <download-base-url> <sparkle-public-key> <output-directory>" >&2
    exit 64
fi

version="$1"
build_version="$2"
appcast_base_url="${3%/}"
download_base_url="${4%/}"
sparkle_public_key="$5"
output_root="$6"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
signing_identity="${MACOS_SIGNING_IDENTITY:-}"
notary_profile="${MACOS_NOTARY_PROFILE:-}"
sparkle_private_key_file="${SPARKLE_PRIVATE_KEY_FILE:-}"
sparkle_tools="$project_root/.build/artifacts/sparkle/Sparkle/bin"

require_value() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        echo "Missing required release configuration: $name" >&2
        exit 78
    fi
}

require_https() {
    local name="$1"
    local value="$2"
    if [[ "$value" != https://* || "$value" == *invalid* || "$value" == *example.com* ]]; then
        echo "$name must be a non-placeholder HTTPS URL: $value" >&2
        exit 78
    fi
}

require_value MACOS_SIGNING_IDENTITY "$signing_identity"
require_value MACOS_NOTARY_PROFILE "$notary_profile"
require_value SPARKLE_PRIVATE_KEY_FILE "$sparkle_private_key_file"
require_https appcast-base-url "$appcast_base_url"
require_https download-base-url "$download_base_url"
[[ -f "$sparkle_private_key_file" ]]
[[ -x "$sparkle_tools/generate_appcast" ]]
[[ -x "$sparkle_tools/sign_update" ]]
if [[ -e "$output_root" ]]; then
    echo "Output directory already exists: $output_root" >&2
    exit 73
fi

derived_public_key="$({
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        /usr/bin/xcrun swift "$project_root/Scripts/derive-sparkle-public-key.swift" \
        "$sparkle_private_key_file"
} 2>/dev/null)"
if [[ "$derived_public_key" != "$sparkle_public_key" ]]; then
    echo "Sparkle public key does not match the supplied private key." >&2
    exit 78
fi

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-release.XXXXXX")"
publish_staging=""
cleanup() {
    rm -rf "$staging_root"
    if [[ -n "$publish_staging" ]]; then
        rm -rf "$publish_staging"
    fi
}
trap cleanup EXIT
mkdir -p "$staging_root/apps" "$staging_root/dmgs" "$staging_root/appcasts"

sign_application() {
    local app="$1"
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    local sparkle="$framework/Versions/Current"
    local signable
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
        --sign "$signing_identity" \
        "$app/Contents/MacOS/VLMSnapperApp"
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$project_root/Distribution/VLMSnapper.entitlements" \
        --sign "$signing_identity" \
        "$app"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
}

notarize_and_staple() {
    local submission="$1"
    local staple_target="$2"
    local log="$3"
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        /usr/bin/xcrun notarytool submit "$submission" \
            --keychain-profile "$notary_profile" \
            --wait \
            --output-format json > "$log"
    local status
    status="$(/usr/bin/plutil -extract status raw -o - "$log")"
    if [[ "$status" != "Accepted" ]]; then
        echo "Apple notarization did not return Accepted for $submission: $status" >&2
        exit 1
    fi
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        /usr/bin/xcrun stapler staple "$staple_target"
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        /usr/bin/xcrun stapler validate "$staple_target"
}

create_dmg() {
    local app="$1"
    local dmg="$2"
    (
        local staging
        staging="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-release-dmg.XXXXXX")"
        trap 'rm -rf "$staging"' EXIT
        /usr/bin/ditto "$app" "$staging/VLMSnapper.app"
        ln -s /Applications "$staging/Applications"
        /usr/bin/hdiutil create \
            -quiet \
            -fs HFS+ \
            -format UDZO \
            -volname VLMSnapper \
            -srcfolder "$staging" \
            "$dmg"
    )
}

verify_final_dmg() {
    local dmg="$1"
    local architecture="$2"
    local feed_url="$3"
    (
        local mountpoint
        local attached=false
        mountpoint="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-release-mount.XXXXXX")"
        cleanup_mount() {
            if [[ "$attached" == true ]]; then
                /usr/bin/hdiutil detach -quiet "$mountpoint" || true
            fi
            rmdir "$mountpoint" 2>/dev/null || true
        }
        trap cleanup_mount EXIT
        /usr/bin/hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mountpoint" "$dmg"
        attached=true
        "$project_root/Scripts/verify-macos-app.sh" \
            "$mountpoint/VLMSnapper.app" \
            "$architecture" \
            "$version" \
            "$build_version" \
            "$feed_url" \
            "$sparkle_public_key"
        /usr/sbin/spctl --assess --type execute --verbose=4 "$mountpoint/VLMSnapper.app"
        DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
            /usr/bin/xcrun stapler validate "$mountpoint/VLMSnapper.app"
        /usr/bin/hdiutil detach -quiet "$mountpoint"
        attached=false
        rmdir "$mountpoint"
    )
    /usr/sbin/spctl --assess --type open --context context:primary-signature \
        --verbose=4 "$dmg"
}

for architecture in arm64 x64 universal; do
    feed_url="$appcast_base_url/appcast-$architecture.xml"
    app="$staging_root/apps/$architecture/VLMSnapper.app"
    "$project_root/Scripts/build-macos-app.sh" \
        "$architecture" \
        "$version" \
        "$build_version" \
        "$feed_url" \
        "$sparkle_public_key" \
        "$app"
    sign_application "$app"
    app_zip="$staging_root/apps/VLMSnapper-$version-mac-$architecture.zip"
    /usr/bin/ditto -c -k --keepParent "$app" "$app_zip"
    notarize_and_staple \
        "$app_zip" \
        "$app" \
        "$staging_root/apps/notary-$architecture.json"

    dmg="$staging_root/dmgs/VLMSnapper-$version-mac-$architecture.dmg"
    create_dmg "$app" "$dmg"
    /usr/bin/codesign --force --timestamp --sign "$signing_identity" "$dmg"
    notarize_and_staple \
        "$dmg" \
        "$dmg" \
        "$staging_root/dmgs/notary-$architecture.json"
    verify_final_dmg "$dmg" "$architecture" "$feed_url"

    appcast_directory="$staging_root/appcasts/$architecture"
    mkdir -p "$appcast_directory"
    /usr/bin/ditto "$dmg" "$appcast_directory/$(basename "$dmg")"
    "$sparkle_tools/generate_appcast" \
        --ed-key-file "$sparkle_private_key_file" \
        --download-url-prefix "$download_base_url" \
        --maximum-versions 1 \
        --maximum-deltas 0 \
        -o "appcast-$architecture.xml" \
        "$appcast_directory"
    appcast="$appcast_directory/appcast-$architecture.xml"
    enclosure_url="$(/usr/bin/xmllint --xpath \
        'string(//*[local-name()="enclosure"]/@url)' "$appcast")"
    enclosure_signature="$(/usr/bin/xmllint --xpath \
        'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' \
        "$appcast")"
    expected_url="$download_base_url/$(basename "$dmg")"
    if [[ "$enclosure_url" != "$expected_url" || -z "$enclosure_signature" ]]; then
        echo "Invalid appcast enclosure for $architecture." >&2
        exit 1
    fi
    "$sparkle_tools/sign_update" \
        --verify \
        --ed-key-file "$sparkle_private_key_file" \
        "$dmg" \
        "$enclosure_signature"
    "$sparkle_tools/sign_update" \
        --verify \
        --ed-key-file "$sparkle_private_key_file" \
        "$appcast"
done

output_parent="$(dirname "$output_root")"
mkdir -p "$output_parent"
output_parent="$(cd "$output_parent" && pwd)"
publish_staging="$(mktemp -d "$output_parent/.vlmsnapper-publish.XXXXXX")"
for architecture in universal arm64 x64; do
    /usr/bin/ditto \
        "$staging_root/dmgs/VLMSnapper-$version-mac-$architecture.dmg" \
        "$publish_staging/VLMSnapper-$version-mac-$architecture.dmg"
    /usr/bin/ditto \
        "$staging_root/appcasts/$architecture/appcast-$architecture.xml" \
        "$publish_staging/appcast-$architecture.xml"
done
/bin/mv "$publish_staging" "$output_root"
publish_staging=""

echo "Formal macOS release artifacts verified in $output_root"
