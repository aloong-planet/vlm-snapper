#!/bin/bash
# Usage: gate.sh <log-file>. Version manifest, then the project's offline gate,
# then every per-stage evidence log it wrote (full output).
log="$1"
cd /Users/loong_zhou/CascadeProjects/vlm-snapper || exit 2
export PYTHONDONTWRITEBYTECODE=1
{
  echo "== version"
  echo "\$ git rev-parse HEAD"; git rev-parse HEAD
  echo "\$ git status --porcelain --untracked-files=all"; git status --porcelain --untracked-files=all
  echo "-- manifest"
  echo "\$ git status --porcelain --untracked-files=all | while IFS= read -r line; do path=\"\${line:3}\"; [ -e \"\$path\" ] && echo \"\$(git hash-object -- \"\$path\")  \$path\" || echo \"deleted  \$path\"; done"
  git status --porcelain --untracked-files=all | while IFS= read -r line; do
    path="${line:3}"
    if [ -e "$path" ]; then echo "$(git hash-object -- "$path")  $path"; else echo "deleted  $path"; fi
  done
  echo "== command: PATH=<scratch rg shim>:\$PATH bash Scripts/test-local-regression.sh --offline"
} > "$log" 2>&1
PATH="/private/tmp/claude-501/-Users-loong-zhou-CascadeProjects-vlm-snapper/ced9312a-2254-4011-9516-18529f20df8b/scratchpad/bin:$PATH" bash Scripts/test-local-regression.sh --offline >> "$log" 2>&1
code=$?
echo "== exit: $code" >> "$log"
evidence="$(grep -m1 '^Evidence: ' "$log" | sed 's/^Evidence: //')"
for f in "$evidence"/*.log; do
  echo "== evidence log: $f" >> "$log"
  cat "$f" >> "$log"
done
exit $code
