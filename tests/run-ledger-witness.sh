#!/usr/bin/env bash
# Witness for bin/scheduler's last_run_verdict() -- the fact source behind
# the glance's run ledger (sprint step 3).
#
# What this is here to prevent, in order of how badly it would hurt:
#  1. A FAILED or still-running last run rendered as ok. The ledger exists
#     because the LAST RUN column already had this failure mode (it reads
#     a report mtime, and a failed run writes no report).
#  2. An unreadable cross-account job rendered as anything but BLIND --
#     the one rule state_account() declares non-negotiable.
#  3. A stale line from an OLD run answering for the newest one. That cost
#     real diagnosis time twice on 2026-07-25, which is why the slicing
#     exists at all.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/scheduler"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# bin/scheduler dispatches on "$1" at the bottom, so it cannot be sourced.
# Lift the one function under test out of it and stub its collaborators --
# the parsing is what this witness is about, not sudo or conf lookup.
awk '/^last_run_verdict\(\) \{$/,/^\}$/' "$SRC" > "$TMP/fn.sh"
grep -q 'BLIND' "$TMP/fn.sh" || { echo "FAIL: could not extract last_run_verdict from $SRC"; exit 1; }

ACCT=""; READABLE=1
state_account()  { printf '%s' "$ACCT"; }
state_home()     { printf '%s' "$TMP"; }
state_readable() { [ "$READABLE" = "1" ]; }
state_exists()   { [ -f "$2" ]; }
state_cat()      { cat "$2" 2>/dev/null; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

DIR="$TMP/.local/share/j"; mkdir -p "$DIR"
verdict() { last_run_verdict p j | cut -f1; }
detail()  { last_run_verdict p j | cut -f3-; }

echo "== 1. no job name -> nojob, not a guess"
[ "$(last_run_verdict p '' | cut -f1)" = "nojob" ] && ok "nojob" || bad "got $(last_run_verdict p '' | cut -f1)"

echo "== 2. no log at all -> nolog, and names the path"
[ "$(verdict)" = "nolog" ] && ok "nolog" || bad "got $(verdict)"
[[ "$(detail)" == *"$DIR"* ]] && ok "names the directory it looked in" || bad "detail hides the path"

echo "== 3. a clean run -> ok"
printf '=== 2026-07-28T01:00:00-05:00 ===\nwork\n=== done 2026-07-28T01:05:00-05:00 (300s) ===\n' > "$DIR/sweep.log"
[ "$(verdict)" = "ok" ] && ok "ok" || bad "got $(verdict)"

echo "== 4. THE REGRESSION: a FAILED run after an earlier clean one -> FAILED"
# The old proxy (report mtime) keeps showing the earlier success here.
printf '=== 2026-07-28T02:00:00-05:00 ===\nboom\n=== FAILED 2026-07-28T02:01:00-05:00 (60s) ===\n' >> "$DIR/sweep.log"
[ "$(verdict)" = "FAILED" ] && ok "the newest run wins" || bad "got $(verdict) -- an old success answered for a failure"

echo "== 5. skipped is not success and not failure"
printf '=== 2026-07-28T03:00:00-05:00 ===\n=== skipped (precheck) 2026-07-28T03:00:01-05:00 (1s) ===\n' >> "$DIR/sweep.log"
[ "$(verdict)" = "skipped" ] && ok "skipped" || bad "got $(verdict)"

echo "== 6. started with no completion line -> running, never ok"
printf '=== 2026-07-28T04:00:00-05:00 ===\nhalfway\n' >> "$DIR/sweep.log"
[ "$(verdict)" = "running" ] && ok "running" || bad "got $(verdict) -- an unfinished run must not read as clean"
[[ "$(detail)" == *"2026-07-28T04:00:00"* ]] && ok "names when it started" || bad "no start time in detail"

echo "== 7. stale lines from OLD runs must not leak into the newest verdict"
# run 6 above is the newest and contains no WARNING; runs 3-5 are older.
printf '=== 2026-07-28T05:00:00-05:00 ===\n=== done 2026-07-28T05:01:00-05:00 (60s) ===\n' >> "$DIR/sweep.log"
[ "$(verdict)" = "ok" ] && ok "newest slice only" || bad "got $(verdict)"

echo "== 8. the older run.log dialect is read, not reported as never-run"
rm -f "$DIR/sweep.log"
printf '==== 2026-07-28T06:00:00-05:00 j start ====\n=== FAILED 2026-07-28T06:02:00-05:00 ===\n' > "$DIR/run.log"
[ "$(verdict)" = "FAILED" ] && ok "run.log dialect read" || bad "got $(verdict)"

echo "== 9. THE RULE: an unreadable cross-account job is BLIND, never \$HOME's answer"
ACCT="svc-someone"; READABLE=0
[ "$(verdict)" = "BLIND" ] && ok "BLIND" || bad "got $(verdict) -- fell back to a path it never probed"
[[ "$(detail)" == *"svc-someone"* ]] && ok "names the account" || bad "BLIND without naming who to ask"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
