#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's claude_failure_detail() -- hf7y/scheduler#31.
#
# THE BUG: a run that hit --max-turns with real commits already pushed and a
# run that crashed outright both landed in the log (and the durable run
# ledger, lib/run-record.sh) as the identical string "FAILED". chezz's
# 2026-08-05 run is the live case: two commits pushed, then
# "Error: Reached max turns (120)", rc=1 -- indistinguishable, from the log
# alone, from a run that did nothing and broke.
#
# Zach, on #31: yes, this should be a distinguishable outcome. It must NOT
# change what happens next -- a ceiling cutoff is still NOT-DONE, re-dispatch,
# metabolism unchanged (bin/verdict.sh's own rule: absence of a verdict is
# never "gave up"). This only makes the two causes legible, in the log line
# and in the JSONL ledger's status field.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Sourcing the whole engine would run a real job (clone, claude, push), so
# lift just the one function out of it -- same technique as
# notify-timeout-witness.sh and verdict-closeout-witness.sh. An extraction
# that stops matching is a FAILURE, not a pass by absence.
awk '/^claude_failure_detail\(\) \{$/,/^\}$/' "$LIB" > "$TMP/fn.sh"
grep -q 'reached max turns' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract claude_failure_detail() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

echo "== 1. the exact chezz #31 output -> ceiling, not auth"
printf 'some tool output\nError: Reached max turns (120)\n' > "$TMP/out"
DETAIL="$(claude_failure_detail "$TMP/out")"
[ "$DETAIL" = " (ceiling: max turns reached)" ] \
  && ok "classified as ceiling" \
  || bad "got '$DETAIL'"

echo "== 2. auth failure still classifies as auth, not ceiling"
printf 'Invalid API key * Please run /login\n' > "$TMP/out"
DETAIL="$(claude_failure_detail "$TMP/out")"
[ "$DETAIL" = " (auth: not logged in)" ] \
  && ok "classified as auth" \
  || bad "got '$DETAIL'"

echo "== 3. an unrecognized failure -> nothing (stays generic FAILED)"
printf 'Some other tool crashed unexpectedly\n' > "$TMP/out"
DETAIL="$(claude_failure_detail "$TMP/out")"
[ -z "$DETAIL" ] && ok "no detail invented for an unrecognized cause" \
  || bad "invented a detail: '$DETAIL'"

echo "== 4. a missing/unreadable transcript -> nothing, no crash"
DETAIL="$(claude_failure_detail "$TMP/does-not-exist" 2>/dev/null)"
RC=$?
[ "$RC" = "0" ] && [ -z "$DETAIL" ] \
  && ok "degrades to no-detail rather than erroring the caller" \
  || bad "rc=$RC detail='$DETAIL'"

echo "== 5. case-insensitive, and matches mid-transcript, not just first line"
printf 'turn 1\nturn 2\n...\nREACHED MAX TURNS (40)\n' > "$TMP/out"
DETAIL="$(claude_failure_detail "$TMP/out")"
[ "$DETAIL" = " (ceiling: max turns reached)" ] \
  && ok "matches regardless of case or position" \
  || bad "got '$DETAIL'"

echo "== 6. the ledger's status field carries the detail (lib/run-record.sh)"
# Not a mock of run_record_line -- the real function, called with the same
# positional shape run_record_closeout uses, so a signature drift here would
# fail this test rather than silently stop wiring the detail through.
# shellcheck disable=SC1091
. "$ROOT/lib/run-record.sh"
STATUS="FAILED"; STATUS_DETAIL=" (ceiling: max turns reached)"
LINE="$(run_record_line "job-1" "job" "chezz" "batch" "hf7y/chezz" "paced/x" \
  "2026-08-05T14:24:00Z" "2026-08-05T14:54:25Z" "1786" "1" \
  "${STATUS}${STATUS_DETAIL}" "abc1234" "def5678" "def5678" "" "")"
echo "$LINE" | grep -q '"status":"FAILED (ceiling: max turns reached)"' \
  && ok "status field distinguishes ceiling from generic FAILED" \
  || bad "status field did not carry the detail: $LINE"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
