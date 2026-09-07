#!/usr/bin/env bash
# paced-roster-authority-witness.sh -- ACCOUNT MODE takes liveness from
# schedule/ROSTER when it has a row, not from _paced.<host>.conf's `enabled`
# column alone (hf7y/scheduler#282, the onekey gap).
#
# THE BUG THIS CATCHES: schedule/_paced.monkey.conf carried `crt|1|...` and
# `secretaire|1|...` (armed) on 2026-08-25 while schedule/ROSTER recorded
# both `parked`, on Zach's own quoted pause/de-animation directives. Nothing
# before this read the second file for the enabled decision, so a paused
# project kept being dispatched every tick. Fixtures below reproduce exactly
# that shape: a conf enabling a row ROSTER says is parked.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "paced-roster-authority-witness"

# Extract both functions so they're testable in isolation, same convention
# as roster_rows in roster-participants-witness.sh.
eval "$(sed -n '/^roster_state_for() {/,/^}/p' "$R")"
eval "$(sed -n '/^participant_enabled() {/,/^}/p' "$R")"
declare -F roster_state_for  >/dev/null && ok "roster_state_for extracted"  \
  || { bad "could not extract roster_state_for -- nothing below tested anything"; echo; exit 1; }
declare -F participant_enabled >/dev/null && ok "participant_enabled extracted" \
  || { bad "could not extract participant_enabled -- nothing below tested anything"; echo; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/schedule"
cat > "$TMP/schedule/ROSTER" <<'EOF'
# comment
alpha   | alpha@testhost   | 20m | live
crt     | crt@testhost     | 6h  | parked
gamma   | gamma@otherhost  | 6h  | live
EOF
REPO_ROOT="$TMP"

# --- roster_state_for --------------------------------------------------------
out="$(roster_state_for alpha testhost)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "live" ] && ok "roster_state_for reports live for a live row" \
  || bad "expected live/rc0, got rc=$rc out=$out"

out="$(roster_state_for crt testhost)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "parked" ] && ok "roster_state_for reports parked for a parked row" \
  || bad "expected parked/rc0, got rc=$rc out=$out"

roster_state_for gamma testhost >/dev/null 2>&1 \
  && bad "a row for another host must not match" \
  || ok "a row naming another host does not match"

roster_state_for nosuchproject testhost >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "an unknown project@host returns 1 (GAP: no row, not a guess)" \
  || bad "expected rc=1 (GAP) for an unknown project, got rc=$rc"

# THE BUG THIS SPINOFF FIXES (realisateur#350 investigation, 2026-09-07): a
# totally absent/unreadable ROSTER used to return the SAME rc=1 as an
# ordinary no-row miss above, so participant_enabled logged an identical
# "SKIP ... names no X@host row" line whether the file was fine and simply
# silent about this one project, or the whole arming surface had failed to
# read. rc=2 (BLIND) now distinguishes the systemic case from the routine one.
REPO_ROOT="$TMP/does-not-exist"
roster_state_for alpha testhost >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a missing ROSTER file returns 2 (BLIND), not the same 1 as a no-row GAP" \
  || bad "expected rc=2 (BLIND) for a missing ROSTER file, got rc=$rc"
REPO_ROOT="$TMP"

# --- participant_enabled: the actual dispatch decision ----------------------
# THE REGRESSION CASE: ROSTER says parked, so the row does not dispatch --
# whatever schedule/_paced.<host>.conf says about it.
participant_enabled crt testhost \
  && bad "crt is parked in ROSTER -- it must not dispatch" \
  || ok "ROSTER parked stops the dispatch (the crt/secretaire bug)"

# The mirror: ROSTER says live, so it dispatches.
cat >> "$TMP/schedule/ROSTER" <<'EOF'
delta   | delta@testhost   | 20m | live
EOF
participant_enabled delta testhost \
  && ok "ROSTER live dispatches" \
  || bad "delta is live in ROSTER and did not dispatch"

# NO ROW AT ALL IS A REFUSAL, not a fall-back to a second surface (#364):
# taking the conf column out of the signature leaves nothing to answer WITH.
LOG="$TMP/run.log"; log() { echo "$*" >> "$LOG"; }
participant_enabled epsilon testhost \
  && bad "epsilon has no ROSTER row -- an unnamed project must not dispatch" \
  || ok "no ROSTER row -> refuses; ROSTER is the only arming surface"
grep -q 'SKIP epsilon .*ROSTER names no epsilon@testhost row' "$LOG" \
  && ok "and it says so in the log rather than going dark silently" \
  || bad "the refusal wrote no SKIP line: $(cat "$LOG" 2>/dev/null)"

# THE OBSERVABILITY GAP THIS SPINOFF FIXES (realisateur#350 investigation,
# 2026-09-07): before this fix, a totally absent/unreadable ROSTER made
# EVERY row -- 19 of them, live on host monkey's clone-free pilot the day
# this was found -- log the exact same "SKIP ... names no X@host row" line
# as an ordinary, expected no-row miss (epsilon above). Nothing distinguished
# "this project just has no row yet" from "the whole arming surface failed
# to read." The dispatch DECISION must stay identical either way (still a
# skip, still no HOLD/abort -- that redesign is #350/#359, not this fix);
# only the LOG LINE should differ.
REPO_ROOT="$TMP/does-not-exist"
LOG="$TMP/run-blind.log"; log() { echo "$*" >> "$LOG"; }
participant_enabled zeta testhost \
  && bad "an unreadable ROSTER must not dispatch -- BLIND is not permission" \
  || ok "an unreadable ROSTER refuses the row, same dispatch outcome as a no-row GAP"
grep -q 'ROSTER UNREADABLE at .*-- BLIND, cannot arm zeta@testhost' "$LOG" \
  && ok "and it logs a loud, distinct BLIND line naming the unreadable path" \
  || bad "no distinct BLIND line for an unreadable ROSTER: $(cat "$LOG" 2>/dev/null)"
grep -q 'SKIP zeta .*names no zeta@testhost row' "$LOG" \
  && bad "the unreadable-file case must NOT reuse the routine no-row SKIP wording" \
  || ok "the unreadable-file case does not masquerade as a routine no-row SKIP"
REPO_ROOT="$TMP"

# The mirror, on a READABLE roster that simply has no row for this project:
# the ORIGINAL, routine message must still appear unchanged (not the new
# BLIND wording) -- this is the common case and must stay boring.
LOG="$TMP/run-gap.log"; log() { echo "$*" >> "$LOG"; }
participant_enabled epsilon testhost \
  && bad "epsilon still has no ROSTER row -- must not dispatch" \
  || ok "a readable ROSTER missing one project's row still refuses that row"
grep -q 'SKIP epsilon -- schedule/ROSTER names no epsilon@testhost row' "$LOG" \
  && ok "and the routine no-row SKIP wording is unchanged by this fix" \
  || bad "the routine no-row SKIP message changed or vanished: $(cat "$LOG" 2>/dev/null)"
grep -q 'BLIND' "$LOG" \
  && bad "a readable ROSTER with a merely-missing row must not print BLIND" \
  || ok "no spurious BLIND line for the ordinary no-row case"

# The signature IS the guarantee: a value never passed in cannot be consulted.
if sed -n '/^participant_enabled() {/,/^}/p' "$R" | grep -q '\$enabled\|{enabled'; then
  bad "participant_enabled reads an 'enabled' value again -- the second arming surface is back"
else
  ok "participant_enabled's body names no 'enabled' value at all"
fi
sed -n '/^participant_enabled() {/,/^}/p' "$R" | grep -qF 'local name="$1" host="$2"' \
  && ok "and its signature is <name> <host>, with no slot for a conf column" \
  || bad "participant_enabled's signature changed -- re-derive this witness against it"

# --- the runner's own loop calls participant_enabled, not the bare column ---
grep -q 'participant_enabled "\$name" "\$PACED_HOST" || continue' "$R" \
  && ok "the participant-loading loop consults participant_enabled, and hands it no conf column" \
  || bad "the loop no longer calls participant_enabled -- this witness is testing dead code"
grep -qE '^\s*\[ "\$\{enabled// /\}" = "1" \] \|\| continue' "$R" \
  && bad "the loop still has a bare enabled==1 check ahead of the ROSTER lookup" \
  || ok "no bare enabled==1 gate left ahead of the ROSTER lookup"

# --- the LAST row, on a file with no trailing newline (hf7y/scheduler#430) ---
# THE BUG THIS CATCHES: a bare `while read` drops a final line with no newline
# after it, so the dispatcher called the last row "no such row" every 20 min.
# printf, not a heredoc: a heredoc supplies the newline whose absence IS the bug.
printf '%s\n%s' '# comment' 'omega   | omega@testhost   | 20m | live' \
  > "$TMP/schedule/ROSTER"
out="$(roster_state_for omega testhost)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "live" ] \
  && ok "roster_state_for reads the last row of a file with no trailing newline" \
  || bad "the newline-less last row is invisible again (#430): rc=$rc out=$out"

# roster_rows reads stdin; the guard belongs on the loop either way.
eval "$(sed -n '/^roster_rows() {/,/^}/p' "$R")"
PACED_HOST=testhost
rows="$(roster_rows < "$TMP/schedule/ROSTER")"
printf '%s' "$rows" | grep -q '^omega|1|' \
  && ok "roster_rows emits the newline-less last row too" \
  || bad "roster_rows still drops the last row (#430): got '$rows'"

printf '\npaced-roster-authority-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
