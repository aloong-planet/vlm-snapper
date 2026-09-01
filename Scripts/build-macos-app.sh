#!/bin/bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 <universal|arm64|x64> <version> <build-version> <feed-url> <sparkle-public-key> <output-app>" >&2
    exit 64
fi

architecture="$1"
version="$2"
build_version="$3"
feed_url="$4"
sparkle_public_key="$5"
output_app="$6"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch_path="${VLMSNAPPER_SCRATCH_PATH:-$project_root/.build}"

case "$architecture" in
    universal|arm64|x64) ;;
    *)
        echo "Unsupported architecture: $architecture" >&2
        exit 64
        ;;
esac

build_architecture() {
    local triple="$1"
    if [[ "$triple" == "arm64-apple-macosx14.0" \
        && "$(/usr/bin/uname -m)" == "arm64" ]]; then
        DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
            /usr/bin/xcrun swift build \
                --scratch-path "$scratch_path" \
                --disable-build-manifest-caching \
                --configuration release \
                --product VLMSnapperApp \
                -Xswiftc -warnings-as-errors \
                -Xcc -Wall -Xcc -Wextra -Xcc -Werror
        return
    fi
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        /usr/bin/xcrun swift build \
            --scratch-path "$scratch_path" \
            --disable-build-manifest-caching \
            --configuration release \
            --triple "$triple" \
            --product VLMSnapperApp \
            -Xswiftc -warnings-as-errors \
            -Xcc -Wall -Xcc -Wextra -Xcc -Werror
}

release_bin_path() {
    local triple="$1"
    if [[ "$triple" == "arm64-apple-macosx14.0" \
        && "$(/usr/bin/uname -m)" == "arm64" ]]; then
        DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
            /usr/bin/xcrun swift build \
                --scratch-path "$scratch_path" \
                --disable-build-manifest-caching \
                --configuration release \
                --show-bin-path
        return
    fi
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
        /usr/bin/xcrun swift build \
            --scratch-path "$scratch_path" \
            --disable-build-manifest-caching \
            --configuration release \
            --triple "$triple" \
            --show-bin-path
}

arm64_bin=""
x64_bin=""
if [[ "$architecture" == "arm64" || "$architecture" == "universal" ]]; then
    build_architecture arm64-apple-macosx14.0
    arm64_bin="$(release_bin_path arm64-apple-macosx14.0)"
fi
if [[ "$architecture" == "x64" || "$architecture" == "universal" ]]; then
    build_architecture x86_64-apple-macosx14.0
    x64_bin="$(release_bin_path x86_64-apple-macosx14.0)"
fi

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-app.XXXXXX")"
cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT

app="$staging_root/VLMSnapper.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"

if [[ "$architecture" == "universal" ]]; then
    /usr/bin/lipo -create \
        "$arm64_bin/VLMSnapperApp" \
        "$x64_bin/VLMSnapperApp" \
        -output "$app/Contents/MacOS/VLMSnapperApp"
elif [[ "$architecture" == "arm64" ]]; then
    cp "$arm64_bin/VLMSnapperApp" "$app/Contents/MacOS/VLMSnapperApp"
else
    cp "$x64_bin/VLMSnapperApp" "$app/Contents/MacOS/VLMSnapperApp"
fi

resource_bin="$arm64_bin"
if [[ -z "$resource_bin" ]]; then
    resource_bin="$x64_bin"
fi
resource_bundle="$resource_bin/VLMSnapper_VLMSnapperUI.bundle"
if [[ ! -d "$resource_bundle" ]]; then
    echo "Missing VLMSnapper UI resource bundle: $resource_bundle" >&2
    exit 1
fi
/usr/bin/ditto "$resource_bundle" "$app/Contents/Resources/$(basename "$resource_bundle")"
for locale in en zh-Hans; do
    localized_resources="$app/Contents/Resources/$locale.lproj"
    mkdir -p "$localized_resources"
    cp \
        "$project_root/Distribution/$locale.lproj/InfoPlist.strings" \
        "$localized_resources/InfoPlist.strings"
done

sparkle_framework="$scratch_path/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
    echo "Missing resolved Sparkle framework: $sparkle_framework" >&2
    exit 1
fi
/usr/bin/ditto "$sparkle_framework" "$app/Contents/Frameworks/Sparkle.framework"

cp "$project_root/Distribution/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $feed_url" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $sparkle_public_key" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/Current"
for signable in \
    "$sparkle/XPCServices/Downloader.xpc" \
    "$sparkle/XPCServices/Installer.xpc" \
    "$sparkle/Updater.app" \
    "$sparkle/Autoupdate" \
    "$app/Contents/Frameworks/Sparkle.framework"; do
    /usr/bin/codesign \
        --force \
        --preserve-metadata=identifier,entitlements,requirements \
        --sign - \
        "$signable"
done
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$project_root/Distribution/VLMSnapper.entitlements" \
    "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"

if [[ -e "$output_app" ]]; then
    echo "Output app already exists: $output_app" >&2
    exit 73
fi
mkdir -p "$(dirname "$output_app")"
/usr/bin/ditto "$app" "$output_app"
