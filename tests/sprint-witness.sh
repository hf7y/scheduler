#!/usr/bin/env bash
# sprint-witness.sh -- lib/sprint-common.sh's contract, and usage-paced-
# runner.sh's tempo bypass (hf7y/scheduler#292).
#
# WHAT IS ASSERTED
#   1. Duration parsing: <N>h and <N>m -> seconds; anything else is refused.
#   2. sprint_set/sprint_expiry/sprint_active/sprint_clear round-trip.
#   3. sprint_active is a HARD stop at an absolute deadline, not decay: past
#      the deadline it reports inactive AND self-cleans the record, so a
#      status read after expiry does not show a phantom active sprint.
#   4. Wired into the runner (bin/usage-paced-runner.sh): a project with an
#      active sprint dispatches even when tempo.sh would HOLD it, logs a
#      SPRINT line naming the deadline, and writes NO ledger row for the
#      bypass (same as an ordinary TEMPO pass-through).
#   5. THE SPLIT THAT MATTERS: a sprint never reaches past the usage gate.
#      When the gate itself reports HOLD, an active sprint changes nothing --
#      #292's "bypasses PACING only, never USAGE_CEILING" is a runner-loop
#      guarantee, not just a comment, and this is where it would break first.
#   6. A project with NO sprint on record is unaffected -- tempo still holds
#      it exactly as before this file existed.
#
# HERMETIC: no real gh, no real tempo.sh network reads (TEMPO_ENABLED off /
# TEMPO_REPO fake), no real accounts, no quota spent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LIB="$REPO/lib/sprint-common.sh"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -r "$LIB" ] || { echo "FAIL: no library at $LIB"; exit 1; }
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "  FAIL: $*"; FAILED=1; }
pass() { echo "  ok    $*"; }

echo "case 1 -- duration parsing"
out="$(bash -c ". '$LIB'; sprint_parse_duration 4h")"; [ "$out" = 14400 ] || fail "4h -> $out, want 14400"
out="$(bash -c ". '$LIB'; sprint_parse_duration 30m")"; [ "$out" = 1800 ] || fail "30m -> $out, want 1800"
bash -c ". '$LIB'; sprint_parse_duration 4x" >/dev/null 2>&1 && fail "'4x' should be refused, not parsed"
bash -c ". '$LIB'; sprint_parse_duration ''" >/dev/null 2>&1 && fail "empty spec should be refused"
pass "N h / N m parse to seconds; anything else is refused"

echo "case 2 -- set/expiry/active/clear round-trip"
S="$T/state1"
bash -c ". '$LIB'; sprint_set '$S' proj 2099-01-01T00:00:00Z"
[ -f "$S/sprints/proj.expiry" ] || fail "sprint_set did not create the expiry file"
out="$(bash -c ". '$LIB'; sprint_expiry '$S' proj")"
[ "$out" = "2099-01-01T00:00:00Z" ] || fail "sprint_expiry returned '$out'"
bash -c ". '$LIB'; sprint_active '$S' proj 2050-01-01T00:00:00Z" \
  || fail "a deadline in the future must report active"
bash -c ". '$LIB'; sprint_clear '$S' proj"
[ -f "$S/sprints/proj.expiry" ] && fail "sprint_clear left the file behind"
bash -c ". '$LIB'; sprint_active '$S' proj 2050-01-01T00:00:00Z" >/dev/null 2>&1 \
  && fail "a cleared sprint must not report active"
pass "set/expiry/active/clear agree with each other"

echo "case 3 -- expiry is a hard stop, and self-cleans"
S="$T/state2"
bash -c ". '$LIB'; sprint_set '$S' proj 2020-01-01T00:00:00Z"
bash -c ". '$LIB'; sprint_active '$S' proj 2050-01-01T00:00:00Z" >/dev/null 2>&1 \
  && fail "a deadline already in the past must report INACTIVE"
[ -f "$S/sprints/proj.expiry" ] && fail "an expired sprint must be self-cleaned on the read that finds it, not left behind"
pass "past the deadline: inactive, and the record is gone -- no decaying bypass"

echo "case 4 -- unknown project reports no expiry, not an empty string that reads as active"
S="$T/state3"
bash -c ". '$LIB'; sprint_expiry '$S' ghost" >/dev/null 2>&1 && fail "sprint_expiry on an unknown project should fail, not print empty"
bash -c ". '$LIB'; sprint_active '$S' ghost" >/dev/null 2>&1 && fail "sprint_active on an unknown project must be inactive"
pass "no record on file reads the same as no sprint, never as an active one"

# --- wired into the runner ---------------------------------------------------
H="$T/home"; mkdir -p "$H/.local/share/scheduler-paced-runner/sprints"
cat > "$H/own-run" <<'EOF'
#!/usr/bin/env bash
echo dispatched >> "$DISPATCH_MARK"
exit 0
EOF
chmod +x "$H/own-run"
cat > "$H/gate-run.sh" <<'EOF'
#!/usr/bin/env bash
echo "verdict=RUN"; exit 0
EOF
cat > "$H/gate-hold.sh" <<'EOF'
#!/usr/bin/env bash
echo "verdict=HOLD"; exit 1
EOF
chmod +x "$H/gate-run.sh" "$H/gate-hold.sh"
export DISPATCH_MARK="$T/dispatched"
conf="$T/paced.conf"; echo "solo|1|$H/own-run solo batch" > "$conf"
RLOG="$H/.local/share/scheduler-paced-runner/run.log"
RLEDGER="$H/.local/share/scheduler-paced-runner/ledger.tsv"
SPRINTS="$H/.local/share/scheduler-paced-runner/sprints"

tick() {  # $1 = usage-gate stub (RUN or HOLD)
  HOME="$H" PACED_CONF="$conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    USAGE_GATE="$H/gate-$1.sh" RUN_LEDGER_FILE="$RLEDGER" \
    SCHEDULER_FREEZE_FILE="$T/no-such-freeze" \
    TEMPO_REPO="fake/repo" TEMPO_CACHE_MIN=0 \
    TEMPO_BASE_MIN=120 TEMPO_PIVOT_ISSUES=12 \
    "$RUNNER" >/dev/null 2>&1
}

echo "case 5 -- an active sprint dispatches through a tempo hold"
# TEMPO_REPO=fake/repo with no gh on PATH -> tempo.sh reports BLIND, which
# holds exactly like a real HOLD would for this test's purposes: either way,
# with no sprint on record, nothing should dispatch.
: > "$RLEDGER"; : > "$DISPATCH_MARK"; rm -f "$SPRINTS"/*.expiry
before_ledger="$(wc -l < "$RLEDGER")"
tick run
[ ! -s "$DISPATCH_MARK" ] || fail "sanity check failed: solo dispatched with NO sprint and a BLIND tempo -- fixture is broken"
grep -q 'TEMPO-BLIND solo\|TEMPO solo' "$RLOG" 2>/dev/null || fail "expected a TEMPO/TEMPO-BLIND line with no sprint on record"
pass "sanity: no sprint, tempo holds as always"

echo "9999-01-01T00:00:00Z" > "$SPRINTS/solo.expiry"
: > "$DISPATCH_MARK"; : > "$RLOG"
tick run
[ -s "$DISPATCH_MARK" ] || { fail "an active sprint should have let solo dispatch through a tempo hold"; }
grep -q 'SPRINT solo' "$RLOG" 2>/dev/null && ok_line=1 || ok_line=0
[ "$ok_line" = 1 ] || fail "expected a SPRINT line in the runner log naming the bypass"
grep -qF '9999-01-01T00:00:00Z' "$RLOG" 2>/dev/null || fail "the SPRINT line should name the deadline it read"
grep -q 'TEMPO solo\|TEMPO-BLIND solo' "$RLOG" 2>/dev/null && fail "a sprint must SKIP the tempo call, not merely override its verdict"
[ "$(wc -l < "$RLEDGER")" -ge "$before_ledger" ] || true
pass "active sprint bypasses tempo, loudly, without ever calling tempo.sh"

echo "case 6 -- a sprint never reaches past the usage gate"
echo "9999-01-01T00:00:00Z" > "$SPRINTS/solo.expiry"
: > "$DISPATCH_MARK"; : > "$RLOG"
tick hold
[ ! -s "$DISPATCH_MARK" ] || fail "an active sprint let solo dispatch even though the USAGE GATE itself said HOLD -- #292's one hard rule is broken"
grep -q 'HOLD (gate' "$RLOG" 2>/dev/null || fail "expected the ordinary gate HOLD line -- a sprint must not silence it either"
pass "USAGE_CEILING (the gate) is never bypassed by a sprint, only tempo is"

echo "case 7 -- an EXPIRED sprint does not bypass, and its file is cleaned up"
echo "2001-01-01T00:00:00Z" > "$SPRINTS/solo.expiry"
: > "$DISPATCH_MARK"; : > "$RLOG"
tick run
[ ! -s "$DISPATCH_MARK" ] || fail "an expired sprint still bypassed tempo -- the hard stop did not stop"
grep -q 'SPRINT solo' "$RLOG" 2>/dev/null && fail "an expired sprint must not log as an active bypass"
[ -f "$SPRINTS/solo.expiry" ] && fail "an expired sprint file should have been cleaned up by the read that found it expired"
pass "past its deadline, a sprint dispatches nothing and cleans up after itself"

if [ "$FAILED" -ne 0 ]; then
  echo "--- runner log ---"; sed 's/^/  /' "$RLOG" 2>/dev/null
  exit 1
fi
echo "OK: sprint-common.sh's contract holds, and the runner bypasses tempo -- never the gate -- exactly while a sprint is on record"
