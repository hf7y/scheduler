#!/usr/bin/env bash
# run-ledger-witness.sh -- the append-only ledger, and the DONE cooldown it
# makes possible.
#
# HERMETICITY: full. Every case runs against a tempfile ledger via
# RUN_LEDGER_FILE; nothing reads or writes the live estate.
#
# hf7y/scheduler#54: DONE was recorded nine times across four accounts in one
# day and stopped nothing; bibliothecaire said DONE on six consecutive runs and
# was re-dispatched every time. The verdict is consumed at the next dispatch,
# so repetition was structurally unobservable -- you cannot detect it when each
# observation is deleted before the next arrives.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "run-ledger-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export RUN_LEDGER_FILE="$W/ledger.tsv"
. "$HERE/../lib/run-ledger.sh"

# --- 1. sourcing is inert -------------------------------------------------
[ ! -e "$RUN_LEDGER_FILE" ] && ok "sourcing the library creates nothing" \
  || bad "sourcing wrote a file -- a library must not act"

# --- 1b. THE PATH RESOLVES PER CALL ---------------------------------------
# It was a top-level assignment, so a caller exporting RUN_LEDGER_FILE AFTER
# sourcing got the default silently. tests/blocked-vocabulary-witness.sh did
# exactly that and wrote 23 fabricated rows into mandark's REAL ledger while
# believing itself hermetic. A test that is wrong about its own isolation is
# worse than one that admits it needs the estate.
( real="$HOME/.local/share/scheduler-paced-runner/ledger.tsv"
  had=no; [ -e "$real" ] && had=yes
  bash -c ". '$HERE/../lib/run-ledger.sh'; export RUN_LEDGER_FILE='$W/late.tsv'; ledger_append q b 1 BLOCKED why" 2>/dev/null
  [ -s "$W/late.tsv" ] || { echo FAILLATE; exit 0; }
  now=no; [ -e "$real" ] && now=yes
  [ "$had" = "$now" ] || { echo FAILREAL; exit 0; }
  echo OKLATE ) > "$W/late.res" 2>/dev/null
case "$(cat "$W/late.res" 2>/dev/null)" in
  OKLATE)   ok "RUN_TIME export is honoured, and the real ledger is untouched" ;;
  FAILLATE) bad "exporting RUN_LEDGER_FILE after sourcing had no effect -- writes go to the default" ;;
  FAILREAL) bad "the test wrote to the REAL ledger -- isolation is broken" ;;
  *)        bad "the per-call resolution check did not run" ;;
esac

# --- 2. append-only: rows accumulate, nothing is rewritten ----------------
ledger_append alpha batch 0 DONE "bar met"
ledger_append alpha batch 1 NOT-DONE "more to do"
n=$(grep -c . "$RUN_LEDGER_FILE")
[ "$n" -eq 2 ] && ok "two appends produce two rows" || bad "expected 2 rows, got $n"
first="$(head -1 "$RUN_LEDGER_FILE")"
ledger_append alpha batch 0 DONE "again"
[ "$(head -1 "$RUN_LEDGER_FILE")" = "$first" ] && ok "the first row is untouched by later appends" \
  || bad "an earlier row changed -- this is not append-only"

# --- 3. ONE ROW IS ONE LINE even with a hostile reason --------------------
# A reason carrying a tab or newline would split a row and every later reader
# would mis-parse from that point on -- corruption invisible until a count is
# wrong.
before=$(grep -c . "$RUN_LEDGER_FILE")
ledger_append beta batch 1 NOT-DONE "$(printf 'has\ta tab\nand a newline')"
after=$(grep -c . "$RUN_LEDGER_FILE")
[ $((after - before)) -eq 1 ] && ok "a reason with a tab and a newline still writes exactly one row" \
  || bad "a hostile reason wrote $((after-before)) rows"

# --- 4. absence is not evidence -------------------------------------------
[ "$(ledger_streak never-seen DONE)" = "0" ] && ok "an unknown project has a DONE streak of 0" \
  || bad "unknown project did not read as 0"
[ "$(ledger_since never-seen DONE)" -gt 1000 ] && ok "ledger_since on an unknown project reads as 'long ago', not 0" \
  || bad "absence read as 'it just happened' -- that would hold a project that never ran"

# --- 5. THE COOLDOWN ELAPSES. The bug this file exists for. ---------------
# A streak-based hold cannot work: skipping appends nothing, so the streak
# never changes and the project is stopped forever wearing a cooldown's name.
# Counting rows SINCE the DONE only elapses because the skip is recorded too.
export RUN_LEDGER_FILE="$W/cool.tsv"
C=3; seq_out=""
ledger_append p batch 0 DONE "bar met"
for i in 1 2 3 4 5; do
  since="$(ledger_since p DONE)"
  if [ "$since" -lt "$C" ]; then seq_out="$seq_out H"; ledger_append p batch - COOLDOWN held
  else seq_out="$seq_out D"; ledger_append p batch 1 NOT-DONE work; fi
done
[ "$seq_out" = " H H H D D" ] && ok "cooldown holds 3 opportunities then resumes on its own: $seq_out" \
  || bad "cooldown sequence was '$seq_out', want ' H H H D D'"

# --- 6. and it is not a permanent stop ------------------------------------
# The load-bearing assertion. If this ever fails, a finished project never runs
# again without a human, which is a brake with no thaw.
grep -q 'D' <<<"$seq_out" && ok "the project dispatches again without human intervention" \
  || bad "the project never resumed -- this is a stop, not a cooldown"

# --- 7. a NOT-DONE resets the streak --------------------------------------
export RUN_LEDGER_FILE="$W/reset.tsv"
ledger_append q batch 0 DONE x; ledger_append q batch 0 DONE y
[ "$(ledger_streak q DONE)" = "2" ] || bad "streak did not reach 2"
ledger_append q batch 1 NOT-DONE "new work arrived"
[ "$(ledger_streak q DONE)" = "0" ] && ok "new work resets the DONE streak immediately" \
  || bad "a NOT-DONE did not clear the streak"

printf '\nrun-ledger-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
