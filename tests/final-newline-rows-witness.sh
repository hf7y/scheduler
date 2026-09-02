#!/usr/bin/env bash
# `read` returns non-zero on a newline-less last line AFTER assigning, so an
# unguarded |-row loop drops it -- dcp-gate-site was invisible to four readers.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }

echo "final-newline-rows-witness.sh"

echo "-- every |-row reader tolerates a missing final newline"
mapfile -t unguarded < <(
  grep -rn "while IFS='|' read -r" "$REPO/bin" "$REPO/lib" 2>/dev/null \
    | grep -v '|| \[ -n' | grep -v '<<<'
)
# Exempt: dresse.sh reads a here-string, bin/scheduler:2254 reads a pipe.
filtered=()
for u in "${unguarded[@]}"; do
  case "$u" in *dresse.sh*|*"} | while IFS="*) continue ;; esac
  filtered+=("$u")
done
if [ "${#filtered[@]}" -eq 0 ]; then
  ok "no unguarded row reader"
else
  bad "unguarded row readers (add \`|| [ -n \"\$first\" ]\`):"
  printf '        %s\n' "${filtered[@]}"
fi

echo "-- paced_membership_set reads the last row of a newline-less file"
mkdir -p "$T/schedule"
printf '# rotation\nalpha|1|1|/x/a\nomega|1|1|/x/o' > "$T/schedule/_paced.testhost.conf"
# shellcheck source=lib/paced-conf.sh
. "$REPO/lib/paced-conf.sh"
paced_membership_set "$T" >/dev/null 2>&1
members="$PACED_MEMBERS"
case " $members " in
  *" omega "*) ok "the last row is a member" ;;
  *)           bad "the last row was dropped: members=[$members]" ;;
esac
case " $members " in
  *" alpha "*) ok "and the rows before it still are" ;;
  *)           bad "an earlier row was lost too: members=[$members]" ;;
esac

echo
printf 'final-newline-rows: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
