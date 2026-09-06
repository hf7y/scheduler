#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }

echo "no-hardcoded-tmp-witness.sh"

echo "-- no script writes a literal /tmp/<name> path"
mapfile -t hits < <(
  grep -rnE '(^|[^A-Za-z0-9_])/tmp/[A-Za-z0-9]' \
    "$REPO/bin" "$REPO/lib" "$REPO/schedule" \
    --include='*.sh' --include='*.conf' 2>/dev/null \
    | grep -vE '^\S+:[0-9]+:\s*#'
)
if [ "${#hits[@]}" -eq 0 ]; then
  ok "no hardcoded /tmp/<name> path outside a comment"
else
  bad "hardcoded /tmp/<name> path (use \$TMPDIR or mktemp instead):"
  printf '        %s\n' "${hits[@]}"
fi

echo
printf 'no-hardcoded-tmp: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
