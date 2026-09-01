#!/usr/bin/env bash
# live-row-conf-witness.sh -- every LIVE schedule/ROSTER row's conf sets a
# non-empty BATCH_JOB_NAME.
#
# SALVAGED from tests/roster-diff-witness.sh case 5, which died with
# bin/roster-diff.sh (#429). This half was never roster-diff's:
# bin/scheduler-run:59 exits 2 on a batch tier whose BATCH_JOB_NAME is empty,
# so a live row over a blank field dispatches every tick and records nothing.
# nine-speakers ran that way for 571 ticks and the status page read it as
# "armed, never ran".
#
# The other half of case 5 -- that a live row's conf sets CRON_HOST and
# CRON_ACCOUNT -- went with roster-diff on purpose. Its failure text said
# "roster-diff derives parked for it and can never exit 0", which was the whole
# reason it existed; bin/sync-crontab.sh defaults CRON_ACCOUNT to the local
# account when unset, so its absence is not the outage this one is.
set -uo pipefail
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
echo "live-row-conf-witness"

while IFS='|' read -r name _acct _rate state; do
  name="${name//[[:space:]]/}"; state="${state//[[:space:]]/}"
  [ -n "$name" ] && [ "$state" = "live" ] || continue
  conf="$ROOT/schedule/$name.conf"
  if [ ! -r "$conf" ]; then
    bad "$name is live in ROSTER but schedule/$name.conf is not readable"
    continue
  fi
  if grep -qE '^BATCH_JOB_NAME="[^"]+"' "$conf"; then
    ok "$name.conf sets a non-empty BATCH_JOB_NAME"
  else
    bad "$name is live in ROSTER but $name.conf has no non-empty BATCH_JOB_NAME -- scheduler-run exits 2 every tick"
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT/schedule/ROSTER")

echo
echo "live-row-conf-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
