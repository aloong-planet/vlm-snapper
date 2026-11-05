#!/bin/bash
# Offline gate plus an explicitly selected live gate. Native tests may activate windows.
set -euo pipefail
live_provider=""
live_model=""
credential_args=()
desktop="when-changed"
if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
    echo "Usage: $0 [--offline | --desktop | --live-provider <provider> --live-model <model> [--keychain]]"
    echo "Default: offline only. Live mode adds two paid model requests, without retries."
    echo "Desktop AX cases run when a change touches what they cover. --desktop always runs them."
    exit 0
fi
if [[ $# -eq 1 && "$1" == --offline ]]; then
    shift
elif [[ $# -eq 1 && "$1" == --desktop ]]; then
    desktop="always"
    shift
elif [[ $# -gt 0 ]]; then
    if [[ $# -lt 4 || $# -gt 5 || "$1" != --live-provider || "$3" != --live-model ]]; then
        echo "Invalid arguments; use --help." >&2; exit 64
    fi
    live_provider="$2"
    live_model="$4"
    case "$live_provider" in openai|gemini|deepseek) ;; *) exit 64 ;; esac
    if [[ -z "${live_model//[[:space:]]/}" || "$live_model" == --* ]]; then exit 64; fi
    if [[ $# -eq 5 ]]; then
        [[ "$5" == --keychain ]] || exit 64
        credential_args=(--keychain)
    fi
fi
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
evidence="$(mktemp -d "${TMPDIR:-/tmp}/vlmsnapper-full-regression.XXXXXX")"
echo "Evidence: $evidence"
run_stage() {
    local name="$1"
    shift
    echo "Running $name"
    if "$@" > "$evidence/$name.log" 2>&1; then
        echo "PASS $name"
    else
        local result=$?
        echo "FAIL $name (exit $result): $evidence/$name.log" >&2
        return "$result"
    fi
}
# Any answer other than a clear "not needed" runs the cases, including the check itself failing.
desktop_cases_needed() {
    [[ "$desktop" == always ]] && return 0
    local result=0
    python3 Scripts/desktop-regression-needed.py || result=$?
    [[ "$result" -ne 10 ]]
}
run_stage strict-build swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror
run_stage script-tests python3 -m unittest discover -s Scripts/tests -p 'test_*.py' -v
run_stage checklist python3 Scripts/verify-feature-checklist.py docs/.workings/v1-core/checklist.md
run_stage localization-keys python3 Scripts/verify-localization-keys.py
run_stage shell-syntax bash -c 'for script in Scripts/*.sh; do bash -n "$script" || exit; done'
run_stage non-app swift test --skip ProviderApplicationTests
python3 Scripts/verify-swift-testing-log.py "$evidence/non-app.log"
run_stage app swift test --filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu
python3 Scripts/verify-swift-testing-log.py "$evidence/app.log"
run_stage native-paste swift test --filter ProviderApplicationTestsNativeMenu.testNativeMainMenuPasteValidatesThroughRealKeyWindow
grep -F 'Executed 1 test, with 0 failures' "$evidence/native-paste.log"
run_stage native-closed swift test --filter ProviderApplicationTestsNativeMenu.testValidationCompletesWhileManagementRemainsClosed
grep -F 'Executed 1 test, with 0 failures' "$evidence/native-closed.log"
run_stage native-thrown swift test --filter ProviderApplicationTestsNativeMenu.testThrownNativeOperationReleasesViewsWithoutChangingExistingWindows
grep -F 'Executed 1 test, with 0 failures' "$evidence/native-thrown.log"
if desktop_cases_needed; then
    run_stage accessibility python3 Scripts/test-provider-accessibility.py
else
    echo "SKIP accessibility: this change does not touch what the desktop AX cases cover; --desktop runs them."
fi
echo "Offline regression passed. Evidence: $evidence"
if [[ -n "$live_provider" ]]; then
    run_stage live-provider bash Scripts/test-live-provider.sh "$live_provider" "$live_model" \
        "$evidence/live-provider.json" "${credential_args[@]}"
    echo "Offline and selected live Provider regression passed. Evidence: $evidence"
else
    echo "Live Provider regression NOT RUN; no claim of model/account compatibility."
fi
