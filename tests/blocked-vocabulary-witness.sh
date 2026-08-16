#!/usr/bin/env bash
# blocked-vocabulary-witness.sh -- BLOCKED is not INCOMPLETE, and only BLOCKED
# lengthens the interval.
#
# HERMETICITY: full. verdict.sh is driven with STATE_ROOT into a tempdir and the
# ledger with RUN_LEDGER_FILE; nothing touches the live estate.
#
# Zach, 2026-08-06: "failed runs should lengthen the interval on blocked. But
# not on incomplete." hf7y/scheduler#63. Before this, CONTINUE, a truncated run
# and a total blockage all classified NOT-DONE and re-dispatched identically --
# the interval could not respond because nothing in the signal distinguished
# them. The evidence was vim-arcade on 2026-08-06: four dispatches, all
# outcome=NOT-DONE, two of which had shipped real work and two of which had
# fallen over.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$HERE/../bin/verdict.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "blocked-vocabulary-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# --- 1. the READER, shipped before any writer ----------------------------
# #63: "Ship the reader before the writers" -- a BLOCKED written by a new brief
# and read by an old verdict.sh degrades silently to NOT-DONE plus a stderr
# line nobody reads.
out="$(STATE_ROOT="$W/a" bash "$V" set j BLOCKED 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "BLOCKED without a reason is refused" || bad "accepted a reasonless BLOCKED (rc=$rc)"
grep -qi 'requires a reason' <<<"$out" && ok "the refusal says a reason is required" || bad "no reason demanded: $out"

STATE_ROOT="$W/b" bash "$V" set j BLOCKED "no credential provisioned" >/dev/null 2>&1
o="$(STATE_ROOT="$W/b" bash "$V" classify j 1 2>/dev/null)"; rc=$?
[ "$o" = "BLOCKED" ] && ok "classify prints BLOCKED" || bad "classify printed '$o'"
[ "$rc" -eq 4 ] && ok "classify exits 4, distinct from NOT-DONE's 1 and GAVE-UP's 3" \
  || bad "classify exited $rc, want 4"

# --- 2. THE DISTINCTION THAT IS THE WHOLE POINT --------------------------
# CONTINUE and BLOCKED must not collapse. If these ever match, the interval
# cannot respond and this work is undone.
STATE_ROOT="$W/c" bash "$V" set j CONTINUE >/dev/null 2>&1
oc="$(STATE_ROOT="$W/c" bash "$V" classify j 1 2>/dev/null)"; rcc=$?
[ "$rcc" -ne 4 ] && ok "CONTINUE does not classify as BLOCKED (rc=$rcc)" \
  || bad "CONTINUE and BLOCKED collapsed -- the signal carries no distinction"
[ "$oc" = "NOT-DONE" ] && ok "CONTINUE still reads NOT-DONE, unchanged" || bad "CONTINUE now prints '$oc'"

# --- 3. absence is still never GAVE-UP -----------------------------------
# The pre-existing asymmetry must survive: silence means truncated, not failed.
oe="$(STATE_ROOT="$W/d" bash "$V" classify never-ran 1 2>/dev/null)"; rce=$?
[ "$rce" -eq 1 ] && ok "no verdict at all still classifies NOT-DONE (rc=1)" \
  || bad "absence now exits $rce -- silence must never become a brake"

# --- 4. the BACKOFF escalates and elapses --------------------------------
# Set BEFORE sourcing as well as after: the library now resolves per call, but
# a witness should not depend on that to stay out of the real ledger.
export RUN_LEDGER_FILE="$W/l.tsv"
. "$HERE/../lib/run-ledger.sh"
H=2; seq=""
sim() {
  local since run want r1 r2
  since="$(ledger_since p BLOCKED)"; run="$(ledger_run p BLOCKED BLOCKED-HOLD)"; [ "$run" -lt 1 ] && run=1
  want=$((H*run)); r1="$(ledger_reason p BLOCKED 1)"; r2="$(ledger_reason p BLOCKED 2)"
  [ -n "$r1" ] && [ "$r1" = "$r2" ] && want=$((want*2))
  if [ "$since" -lt 999999 ] && [ "$since" -lt "$want" ]; then seq="$seq H"; ledger_append p b - BLOCKED-HOLD w; return; fi
  seq="$seq D"; ledger_append p b 1 BLOCKED "$1"
}
# Four opportunities: dispatch, hold, hold, dispatch again. The fourth is the
# load-bearing one -- a backoff that never resumes is a stop, the same bug the
# DONE cooldown nearly shipped with.
sim "cred"; sim "cred"; sim "cred"; sim "cred"
grep -q 'D H H D' <<<" $seq" && ok "first blockage holds 2, then dispatches again:$seq" \
  || bad "unexpected backoff sequence:$seq"
grep -q 'D' <<<"${seq#* D}" && ok "the project is not stopped -- it retries without a human" \
  || bad "backoff never resumed: $seq"

# --- 5. THE SAME BLOCKER TWICE ESCALATES HARDER --------------------------
# The signal Zach actually asked for, and the reason BLOCKED carries a
# mandatory reason at all. Only observable because the ledger keeps the reason
# -- verdict.sh clear deletes it at the next dispatch.
export RUN_LEDGER_FILE="$W/same.tsv"
ledger_append p b 1 BLOCKED "cred"; ledger_append p b 1 BLOCKED "cred"
r1="$(ledger_reason p BLOCKED 1)"; r2="$(ledger_reason p BLOCKED 2)"
[ "$r1" = "$r2" ] && ok "a repeated blocker is detectable (both reasons read '$r1')" \
  || bad "could not compare consecutive blocker reasons: '$r1' vs '$r2'"

export RUN_LEDGER_FILE="$W/diff.tsv"
ledger_append p b 1 BLOCKED "cred"; ledger_append p b 1 BLOCKED "something else"
d1="$(ledger_reason p BLOCKED 1)"; d2="$(ledger_reason p BLOCKED 2)"
[ "$d1" != "$d2" ] && ok "a DIFFERENT blocker is distinguished from a repeat" \
  || bad "two different reasons compared equal -- escalation would fire wrongly"

# --- 6. the runner actually branches on 4 --------------------------------
grep -q 'vrc" -eq 4' "$HERE/../bin/usage-paced-runner.sh" \
  && ok "the dispatcher has a vrc -eq 4 branch" \
  || bad "nothing reads exit 4 -- BLOCKED would be computed and discarded, exactly as DONE was"

printf '\nblocked-vocabulary-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
