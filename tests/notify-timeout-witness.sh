#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's notify() -- q-756f82.
#
# The bug this exists to prevent: a notification that never returns
# wedging the job it decorates. `notify-send ... 2>/dev/null || true`
# guards a notify-send that FAILS and does nothing about one that HANGS
# (live instance 2026-07-28: dbus socket present, nobody listening --
# see lib/deadman-switch.sh's deadman_check for the same guard applied
# there). In sweep-loop-common.sh the hang is worse than elsewhere, because
# the caller holds $LOCK and the registry marker, so it blocks the
# project's OTHER tier too.
#
# Two things must both hold, and the second is the one that rots first:
# the job survives (bounded), and the dropped notification is NOT silent.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# Sourcing the whole engine would run a real job (clone, claude, push), so
# lift just notify() out of it. If the extraction stops matching, that is a
# failure -- not a pass by absence.
awk '/^notify\(\) \{$/,/^\}$/' "$LIB" > "$TMP/notify.sh"
grep -q 'timeout ' "$TMP/notify.sh" \
  || { echo "FAIL: could not extract a notify() with a timeout from $LIB"; exit 1; }
LOG="$TMP/sweep.log"; : > "$LOG"
# shellcheck disable=SC1090
. "$TMP/notify.sh"

echo "== 1. notify-send that never returns -> bounded, and says so"
# The real failure shape: notify-send exists and blocks forever.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/bin/notify-send"
chmod +x "$TMP/bin/notify-send"
PATH="$TMP/bin:$PATH"

START=$(date +%s)
notify "job" "hello"; RC=$?
ELAPSED=$(( $(date +%s) - START ))

[ "$RC" = "0" ] && ok "returns 0 -- never becomes the caller's exit status" || bad "rc=$RC"
[ "$ELAPSED" -lt 30 ] && ok "returned in ${ELAPSED}s instead of hanging" || bad "took ${ELAPSED}s"
grep -q 'DROPPED' "$LOG" && ok "logged the dropped notification" \
  || bad "silent drop -- the failure is invisible in $LOG"
grep -q 'hello' "$LOG" && ok "log names WHICH notification was lost" \
  || bad "log does not say what was dropped"

echo "== 2. notify-send that succeeds -> quiet"
: > "$LOG"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/notify-send"
notify "job" "fine" && ok "rc 0 on success" || bad "nonzero on success"
[ ! -s "$LOG" ] && ok "no log noise when it worked" || bad "logged on the happy path: $(cat "$LOG")"

echo "== 3. notify-send that FAILS fast -> tolerated, still quiet"
# The case the old `|| true` already handled; it must keep working.
: > "$LOG"
printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > "$TMP/bin/notify-send"
notify "job" "nope" && ok "a failing notify-send does not abort the job" || bad "propagated rc 1"
grep -q 'DROPPED' "$LOG" && bad "a plain failure was mislabelled a timeout" \
  || ok "does not claim a timeout it did not see"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
