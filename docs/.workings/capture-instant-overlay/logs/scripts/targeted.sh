#!/bin/bash
log="$1"
cd /Users/loong_zhou/CascadeProjects/vlm-snapper || exit 2
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PYTHONDONTWRITEBYTECODE=1
{
  echo "== version"; echo "\$ git rev-parse HEAD"; git rev-parse HEAD
  echo "\$ git status --porcelain --untracked-files=all"; git status --porcelain --untracked-files=all
  echo "-- manifest"
  echo '$ git status --porcelain --untracked-files=all | while IFS= read -r l; do p="${l:3}"; if [ -e "$p" ]; then echo "$(git hash-object -- "$p")  $p"; else echo "deleted  $p"; fi; done'
  git status --porcelain --untracked-files=all | while IFS= read -r l; do p="${l:3}"; if [ -e "$p" ]; then echo "$(git hash-object -- "$p")  $p"; else echo "deleted  $p"; fi; done
} > "$log" 2>&1
overall=0
run() { echo "== command: $*" >> "$log"; "$@" >> "$log" 2>&1; local c=$?; echo "== exit: $c" >> "$log"; [ $c -eq 0 ] || overall=1; }
run /usr/bin/xcrun swift build -Xswiftc -warnings-as-errors -Xcc -Wall -Xcc -Wextra -Xcc -Werror
run /usr/bin/xcrun swift build --build-tests
run /usr/bin/xcrun swift test --skip-build --filter ProviderApplicationTests --skip ProviderApplicationTestsNativeMenu
for t in testNativeMainMenuPasteValidatesThroughRealKeyWindow testValidationCompletesWhileManagementRemainsClosed testThrownNativeOperationReleasesViewsWithoutChangingExistingWindows; do
  run /usr/bin/xcrun swift test --skip-build --filter "ProviderApplicationTestsNativeMenu.$t"
done
echo "== overall: $overall" >> "$log"; exit $overall
