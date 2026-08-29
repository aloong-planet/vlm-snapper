#!/bin/bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 <app> <universal|arm64|x64> <version> <build-version> <feed-url> <sparkle-public-key>" >&2
    exit 64
fi

app="$1"
architecture="$2"
version="$3"
build_version="$4"
feed_url="$5"
sparkle_public_key="$6"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/VLMSnapperApp"

[[ -f "$info" ]]
[[ -x "$executable" ]]
[[ -d "$app/Contents/Frameworks/Sparkle.framework" ]]
[[ -d "$app/Contents/Resources/VLMSnapper_VLMSnapperUI.bundle" ]]

assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$info")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected $key: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_plist_value CFBundleIdentifier com.loong.vlmsnapper
assert_plist_value CFBundleShortVersionString "$version"
assert_plist_value CFBundleVersion "$build_version"
assert_plist_value LSMinimumSystemVersion 14.0
assert_plist_value LSUIElement true
assert_plist_value \
    NSScreenCaptureUsageDescription \
    "VLMSnapper needs access to screen content so you can capture a selected area for text extraction or translation."
assert_plist_value SUFeedURL "$feed_url"
assert_plist_value SUPublicEDKey "$sparkle_public_key"
assert_plist_value SUEnableAutomaticChecks true
assert_plist_value SUAllowsAutomaticUpdates false
assert_plist_value SUEnableInstallerLauncherService true
assert_plist_value SUEnableSystemProfiling false
assert_plist_value SURequireSignedFeed true
assert_plist_value SUVerifyUpdateBeforeExtraction true

assert_localized_plist_value() {
    local locale="$1"
    local expected="$2"
    local localized_info="$app/Contents/Resources/$locale.lproj/InfoPlist.strings"
    local actual
    if [[ ! -f "$localized_info" ]]; then
        echo "Missing localized Info.plist strings: $localized_info" >&2
        exit 1
    fi
    actual="$(
        /usr/bin/plutil \
            -extract NSScreenCaptureUsageDescription raw \
            -o - \
            "$localized_info"
    )"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected $locale NSScreenCaptureUsageDescription: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_localized_plist_value \
    en \
    "VLMSnapper needs access to screen content so you can capture a selected area for text extraction or translation."
assert_localized_plist_value \
    zh-Hans \
    "VLMSnapper 需要访问屏幕内容，以便截取你选择的区域并进行文字提取或翻译。"

scheduled_interval="$(/usr/libexec/PlistBuddy -c "Print :SUScheduledCheckInterval" "$info")"
if [[ "$scheduled_interval" != "21600" && "$scheduled_interval" != "21600.000000" ]]; then
    echo "Unexpected SUScheduledCheckInterval: $scheduled_interval" >&2
    exit 1
fi

actual_architectures="$(/usr/bin/lipo -archs "$executable")"
case "$architecture" in
    universal)
        [[ "$actual_architectures" == *arm64* && "$actual_architectures" == *x86_64* ]]
        ;;
    arm64)
        [[ "$actual_architectures" == "arm64" ]]
        ;;
    x64)
        [[ "$actual_architectures" == "x86_64" ]]
        ;;
    *)
        echo "Unsupported architecture: $architecture" >&2
        exit 64
        ;;
esac

/usr/bin/otool -L "$executable" | /usr/bin/grep -Fq '@rpath/Sparkle.framework/'
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"

entitlements="$(mktemp "${TMPDIR:-/tmp}/vlmsnapper-entitlements.XXXXXX")"
cleanup() {
    rm -f "$entitlements"
}
trap cleanup EXIT
/usr/bin/codesign -d --xml --entitlements :- "$app" > "$entitlements" 2>/dev/null

assert_entitlement_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected entitlement $key: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_entitlement_value com.apple.security.app-sandbox true
assert_entitlement_value com.apple.security.assets.pictures.read-write true
assert_entitlement_value com.apple.security.network.client true
assert_entitlement_value \
    com.apple.security.temporary-exception.mach-lookup.global-name:0 \
    com.loong.vlmsnapper-spki
assert_entitlement_value \
    com.apple.security.temporary-exception.mach-lookup.global-name:1 \
    com.loong.vlmsnapper-spks
