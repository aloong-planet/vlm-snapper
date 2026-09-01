#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <app> <signing-metadata> <signing-identity>" >&2
    exit 64
fi

app="$1"
metadata="$2"
signing_identity="$3"
embedded_profile="$app/Contents/embedded.provisionprofile"

[[ -d "$app" ]]
[[ -f "$metadata" ]]
[[ -f "$embedded_profile" ]]

expected_profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :ProfileUUID' "$metadata")"
expected_profile_sha256="$(/usr/libexec/PlistBuddy -c 'Print :ProfileSHA256' "$metadata")"
expected_team_identifier="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier' "$metadata")"
expected_application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationIdentifier' "$metadata")"
expected_keychain_group="$(/usr/libexec/PlistBuddy -c 'Print :KeychainAccessGroup' "$metadata")"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-signature-verify.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

decoded_profile="$temporary_root/profile.plist"
signed_entitlements="$temporary_root/entitlements.plist"
/usr/bin/security cms -D -i "$embedded_profile" > "$decoded_profile"
/usr/bin/codesign -d --xml --entitlements :- "$app" \
    > "$signed_entitlements" 2>/dev/null

actual_profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$decoded_profile")"
actual_profile_sha256="$(/usr/bin/shasum -a 256 "$embedded_profile" | /usr/bin/awk '{print $1}')"
if [[ "$actual_profile_uuid" != "$expected_profile_uuid" ]]; then
    echo "Embedded provisioning profile UUID does not match validated metadata." >&2
    exit 1
fi
if [[ "$actual_profile_sha256" != "$expected_profile_sha256" ]]; then
    echo "Embedded provisioning profile bytes do not match validated metadata." >&2
    exit 1
fi

assert_entitlement() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$signed_entitlements")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Unexpected signed entitlement $key: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_entitlement com.apple.application-identifier "$expected_application_identifier"
assert_entitlement com.apple.developer.team-identifier "$expected_team_identifier"
assert_entitlement keychain-access-groups:0 "$expected_keychain_group"
if /usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:1' \
    "$signed_entitlements" >/dev/null 2>&1; then
    echo "The signed app must claim exactly one Keychain access group." >&2
    exit 1
fi

/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$app"
signature_details="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
if ! /usr/bin/grep -Fq "Authority=$signing_identity" <<< "$signature_details"; then
    echo "The app signature authority does not match the configured identity." >&2
    exit 1
fi
if ! /usr/bin/grep -Fq "TeamIdentifier=$expected_team_identifier" \
    <<< "$signature_details"; then
    echo "The app signature TeamIdentifier does not match the profile." >&2
    exit 1
fi
if ! /usr/bin/grep -Eq '^Timestamp=' <<< "$signature_details"; then
    echo "The app signature is missing a secure timestamp." >&2
    exit 1
fi
if ! /usr/bin/grep -Eq 'flags=.*runtime' <<< "$signature_details"; then
    echo "The app signature is missing hardened runtime." >&2
    exit 1
fi

echo "Developer ID profile and signature verified for $app"
