#!/bin/bash
# Full local gate. Native AppKit tests may activate their isolated windows.
set -euo pipefail
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
run_stage strict-build swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror
run_stage script-tests python3 -m unittest discover -s Scripts/tests -p 'test_*.py' -v
run_stage checklist python3 Scripts/verify-feature-checklist.py docs/.workings/v1-core/checklist.md
run_stage shell-syntax bash -c 'for script in Scripts/*.sh; do bash -n "$script" || exit; done'
run_stage non-app swift test --skip ProviderApplicationTests
python3 Scripts/verify-swift-testing-log.py "$evidence/non-app.log"
run_stage app swift test --filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu
python3 Scripts/verify-swift-testing-log.py "$evidence/app.log"
run_stage native-paste swift test --filter ProviderApplicationTestsNativeMenu.testNativeMainMenuPasteValidatesThroughRealKeyWindow
rg -F 'Executed 1 test, with 0 failures' "$evidence/native-paste.log"
run_stage native-closed swift test --filter ProviderApplicationTestsNativeMenu.testValidationCompletesWhileManagementRemainsClosed
rg -F 'Executed 1 test, with 0 failures' "$evidence/native-closed.log"
run_stage accessibility python3 Scripts/test-provider-accessibility.py
echo "Full local regression passed. Evidence: $evidence"
