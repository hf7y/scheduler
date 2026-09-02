#!/usr/bin/env bash
# final-newline-rows-witness.sh -- a row file whose last line has no newline
# still yields that row.
#
# WHY THIS EXISTS. schedule/_paced.monkey.conf and schedule/ROSTER both ended
# without a final newline. `while IFS='|' read -r ...` returns non-zero on the
# last, newline-less line -- after having assigned the variables -- so an
# unguarded loop DROPS it. Measured 2026-09-02: sync-crontab.sh did not know
# dcp-gate-site was a paced participant, so instead of suppressing its fixed
# nightly line it tried to write one into that account's crontab and failed on
# sudo. dcp-gate-site is `live`. Nothing was red; the row was simply not there.
#
# The newline is restored, but the newline is not the guarantee -- the next
# writer can drop it again, and the failure is silent. The guarantee is that
# every reader of these files tolerates it, which is what this asserts.
#
# HERMETIC: fixtures under a temp dir. Nothing reads the live schedule.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }

echo "final-newline-rows-witness.sh"

# 1. Every reader of a |-delimited row file guards its loop. Grepped rather
#    than driven, because these four live in three scripts with three
#    different entry conditions (root, a resolved host file, a subcommand),
#    and a grep that names the file and line is what a reader can act on.
echo "-- every |-row reader tolerates a missing final newline"
mapfile -t unguarded < <(
  grep -rn "while IFS='|' read -r" "$REPO/bin" "$REPO/lib" 2>/dev/null \
    | grep -v '|| \[ -n' \
    | grep -v '<<<'
)
# Two readers are exempt because their input cannot lack a final newline:
# dresse.sh reads a here-string block, and bin/scheduler:2254 reads a pipe.
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

# 2. The behaviour itself, through the one reader that can be driven offline.
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
