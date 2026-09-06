#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's provisional-verdict mechanism --
# hf7y/scheduler#347 item 3.
#
# THE GAP: a run that hits --max-turns still runs run_record_closeout and
# gets a real ledger row (#31, #544, #615). What has NEVER left a trace is
# the wrapper itself dying before it gets back there -- host reboot, OOM,
# `kill -9` on the whole job, not just `claude -p`. That run is completely
# silent, identical in every log to one that simply chose not to answer.
#
# THE FIX under test: a background watcher tails this run's OWN transcript
# (named by a UUID we pass via --session-id, not by reconstructing Claude
# Code's cwd-escaping) and, once it sees PROVISIONAL_VERDICT_TURNS assistant
# turns, drops a file outside claude's process tree. If the wrapper makes it
# back, the file is deleted (superseded by the real computed verdict). If it
# doesn't, the file survives to the NEXT run, which must say so instead of
# staying silent about it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# Lift just the three functions out of the engine -- sourcing the whole file
# would run a real job. Same technique as ceiling-breadcrumb-witness.sh. An
# extraction that stops matching is a FAILURE: the functions were renamed or
# reshaped without this witness tracking them.
awk '/^provisional_verdict_watch\(\) \{$/,/^\}$/' "$LIB" > "$TMP/fn.sh"
awk '/^provisional_verdict_watch_stop\(\) \{$/,/^\}$/' "$LIB" >> "$TMP/fn.sh"
awk '/^provisional_verdict_check_stale\(\) \{$/,/^\}$/' "$LIB" >> "$TMP/fn.sh"
grep -q 'provisional_verdict_watch()' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract provisional_verdict_watch() from $LIB"; exit 1; }
grep -q 'provisional_verdict_watch_stop()' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract provisional_verdict_watch_stop() from $LIB"; exit 1; }
grep -q 'provisional_verdict_check_stale()' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract provisional_verdict_check_stale() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

PROVISIONAL_VERDICT_SEARCH_ROOT="$TMP/claude-projects"
mkdir -p "$PROVISIONAL_VERDICT_SEARCH_ROOT/-some-escaped-cwd"

echo "== 1. transcript already past threshold -- watch writes the file immediately, no full poll wait"
SESSION="11111111-1111-1111-1111-111111111111"
TRANSCRIPT="$PROVISIONAL_VERDICT_SEARCH_ROOT/-some-escaped-cwd/$SESSION.jsonl"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf '{"type":"assistant","i":%d}\n' "$i" >> "$TRANSCRIPT"
  printf '{"type":"user","i":%d}\n' "$i" >> "$TRANSCRIPT"
done
OUT="$TMP/provisional-1.txt"
START=$(date +%s)
provisional_verdict_watch "$SESSION" 10 "$OUT" 1 60
ELAPSED=$(( $(date +%s) - START ))
if [ -f "$OUT" ]; then
  ok "provisional file written once the threshold was already met"
else
  bad "no provisional file written even though the transcript already had 12 assistant turns"
fi
[ "$ELAPSED" -lt 30 ] \
  && ok "returned promptly ($ELAPSED s) instead of running out the full max_wait" \
  || bad "took $ELAPSED s -- did not detect the already-met threshold on its first pass"
grep -q "$SESSION" "$OUT" 2>/dev/null \
  && ok "provisional file names the session it watched" \
  || bad "provisional file does not name the session: $(cat "$OUT" 2>/dev/null)"
grep -q "reached turn 12" "$OUT" 2>/dev/null \
  && ok "provisional file records the turn count observed" \
  || bad "provisional file does not record the turn count: $(cat "$OUT" 2>/dev/null)"

echo "== 2. transcript never reaches threshold -- watch gives up after max_wait, writes nothing"
SESSION2="22222222-2222-2222-2222-222222222222"
TRANSCRIPT2="$PROVISIONAL_VERDICT_SEARCH_ROOT/-some-escaped-cwd/$SESSION2.jsonl"
printf '{"type":"assistant","i":1}\n{"type":"user","i":1}\n' > "$TRANSCRIPT2"
OUT2="$TMP/provisional-2.txt"
provisional_verdict_watch "$SESSION2" 10 "$OUT2" 1 2
[ ! -e "$OUT2" ] \
  && ok "no provisional file written when the run never reached the checkpoint" \
  || bad "provisional file exists for a run that stayed below threshold: $(cat "$OUT2")"

echo "== 3. no transcript ever appears -- watch gives up cleanly, writes nothing"
SESSION3="33333333-3333-3333-3333-333333333333"
OUT3="$TMP/provisional-3.txt"
provisional_verdict_watch "$SESSION3" 10 "$OUT3" 1 2
[ ! -e "$OUT3" ] \
  && ok "no provisional file written when no transcript ever showed up" \
  || bad "provisional file exists with no transcript: $(cat "$OUT3")"

echo "== 4. watch_stop kills a still-running watch"
SESSION4="44444444-4444-4444-4444-444444444444"
OUT4="$TMP/provisional-4.txt"
provisional_verdict_watch "$SESSION4" 10 "$OUT4" 60 3600 &
WPID=$!
sleep 0.3
if kill -0 "$WPID" 2>/dev/null; then
  ok "watch is running before stop is called"
else
  bad "watch exited immediately -- test setup is broken, not exercising watch_stop"
fi
provisional_verdict_watch_stop "$WPID"
sleep 0.3
kill -0 "$WPID" 2>/dev/null \
  && bad "watch is still running after watch_stop" \
  || ok "watch_stop killed the still-running watch"

echo "== 5. watch_stop with no pid is a no-op, not an error"
provisional_verdict_watch_stop ""
ok "watch_stop with an empty pid returned without error"

echo "== 6. check_stale: no file present -- silent no-op"
PROVISIONAL_VERDICT_FILE="$TMP/does-not-exist-provisional.txt"
STALE_OUT="$(provisional_verdict_check_stale)"
[ -z "$STALE_OUT" ] \
  && ok "check_stale printed nothing when there is no stale file" \
  || bad "check_stale printed something with no file present: $STALE_OUT"

echo "== 7. check_stale: a stale file from a previous run -- reported and consumed"
PROVISIONAL_VERDICT_FILE="$TMP/stale-provisional.txt"
printf 'PROVISIONAL: session abc reached turn 14 (>= 10) at 2026-09-06T00:00:00Z\ntranscript: /somewhere/abc.jsonl\n' > "$PROVISIONAL_VERDICT_FILE"
STALE_OUT="$(provisional_verdict_check_stale)"
case "$STALE_OUT" in
  *"reached turn 14"*) ok "check_stale surfaces the previous run's provisional content" ;;
  *) bad "check_stale did not surface the stale content: $STALE_OUT" ;;
esac
[ ! -e "$PROVISIONAL_VERDICT_FILE" ] \
  && ok "stale provisional file consumed (deleted) after being reported" \
  || bad "stale provisional file still exists after check_stale -- would replay forever"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
