#!/usr/bin/env bash
# tempo-witness.sh -- bin/tempo.sh is the thermostat's setpoint (#147, #66 §3),
# and usage-paced-runner.sh obeys it.
#
# WHAT IS ASSERTED
#   1. The arithmetic: want_min = BASE*PIVOT/actionable, clamped both ends.
#   2. The inversion: blocked labels are SUBTRACTED, so a tracker that is
#      entirely human-gated paces at MAX_MIN rather than at maximum speed.
#      This is the one #147 calls a runaway if it is backwards.
#   3. HOLD below want_min, RUN at or above it.
#   4. A neighbouring brake's hold row does not reset tempo's clock.
#   5. BLIND is exit 2, and the runner treats it as a hold -- never a run.
#   6. The cache spares a held tick its network round-trip.
#   7. Wired: the runner logs TEMPO and dispatches nothing while tempo holds.
#   8. A tempo hold appends NO ledger row -- the deliberate difference from the
#      DONE cooldown, which would otherwise have its counts inflated.
#
# HERMETIC: `gh` is a stub on PATH and the ledger is a temp file, so this
# reads no tracker, spends no quota and dispatches no real work.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TEMPO="$REPO/bin/tempo.sh"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -x "$TEMPO" ] || { echo "FAIL: no tempo at $TEMPO"; exit 1; }
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "  FAIL: $*"; FAILED=1; }
pass() { echo "  ok    $*"; }

# --- the gh stub. Answers with whatever COUNTS holds, and records that it was
# called, so the cache assertion can tell a fetch from a reuse.
mkdir -p "$T/bin"
COUNTS="$T/counts"; CALLS="$T/gh-calls"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo call >> "$GH_CALLS"
cat "$GH_COUNTS"
EOF
chmod +x "$T/bin/gh"
export GH_COUNTS="$COUNTS" GH_CALLS="$CALLS"
export PATH="$T/bin:$PATH"

LEDGER="$T/ledger.tsv"
export STATE_DIR="$T/state" RUN_LEDGER_FILE="$LEDGER" TEMPO_REPO="fake/repo"
mkdir -p "$STATE_DIR"

# open<TAB>blocked, the two numbers gh's --jq prints.
set_counts() { printf '%s\t%s\n' "$1" "$2" > "$COUNTS"; rm -f "$STATE_DIR"/tempo-*.count; }
# a dispatch row <n> minutes ago
row() { printf '%s\tmonkey\tacct\t%s\tbatch\t%s\t%s\tr\n' \
          "$(date -Is -d "-$1 min")" "${2:-p}" "${3:-0}" "${4:-WORKED}" >> "$LEDGER"; }

run_tempo() { TEMPO_CACHE_MIN=0 "$TEMPO" "$@" 2>&1; }
want_of() { sed -n 's/.*want_min=\([0-9]*\).*/\1/p' <<<"$1"; }

echo "case 1 -- the arithmetic"
set_counts 12 0; : > "$LEDGER"
out="$(run_tempo p)"
[ "$(want_of "$out")" = "120" ] || fail "12 actionable at BASE=120/PIVOT=12 should want 120, got: $out"
set_counts 24 0
out="$(run_tempo p)"
[ "$(want_of "$out")" = "60" ] || fail "24 actionable should want 60 (twice the work, twice the pace), got: $out"
set_counts 6 0
out="$(run_tempo p)"
[ "$(want_of "$out")" = "240" ] || fail "6 actionable should want 240, got: $out"
[ "$FAILED" = 0 ] && pass "want_min = BASE*PIVOT/actionable"

echo "case 2 -- clamps"
set_counts 400 0
out="$(run_tempo p)"
[ "$(want_of "$out")" = "20" ] || fail "a flooded tracker must clamp at MIN_MIN=20, got: $out"
set_counts 1 0
out="$(run_tempo p)"
[ "$(want_of "$out")" = "1440" ] || fail "a near-empty tracker must clamp at MAX_MIN=1440, got: $out"
pass "neither an empty nor a flooded tracker produces an absurd pace"

echo "case 3 -- THE INVERSION: blocked labels are subtracted, not counted"
set_counts 40 40
out="$(run_tempo p)"
[ "$(want_of "$out")" = "1440" ] \
  || fail "40 open, ALL human-gated, must pace at MAX_MIN -- got: $out (if this reads 36, the sensor is backwards and #147's runaway is live)"
grep -q 'actionable=0' <<<"$out" || fail "expected actionable=0, got: $out"
set_counts 40 16
out="$(run_tempo p)"
[ "$(want_of "$out")" = "60" ] || fail "40 open minus 16 blocked = 24 actionable should want 60, got: $out"
pass "a human-gated tracker dispatches LESS, not more"

echo "case 4 -- HOLD below want_min, RUN at or above"
set_counts 12 0; : > "$LEDGER"; row 10
out="$(run_tempo p)"; rc=$?
[ "$rc" = 1 ] || fail "10 min since dispatch against want 120 must HOLD (exit 1), got rc=$rc: $out"
grep -q 'verdict=HOLD' <<<"$out" || fail "expected verdict=HOLD, got: $out"
: > "$LEDGER"; row 130
out="$(run_tempo p)"; rc=$?
[ "$rc" = 0 ] || fail "130 min against want 120 must RUN (exit 0), got rc=$rc: $out"
pass "the clock decides, and says which number it compared"

echo "case 5 -- a neighbouring brake's hold row does not reset the clock"
: > "$LEDGER"; row 10 p 0 WORKED; row 0 p - COOLDOWN; row 0 p - BLOCKED-HOLD
out="$(run_tempo p)"
grep -qE 'since_min=(9|10|11)\b' <<<"$out" \
  || fail "COOLDOWN/BLOCKED-HOLD rows must be skipped; a fresh hold row would read since_min=0. got: $out"
pass "tempo measures since the last DISPATCH, not since the last row"

echo "case 6 -- BLIND is exit 2 and names what it could not read"
: > "$COUNTS"
out="$("$TEMPO" p 2>&1)"; rc=$?
[ "$rc" = 2 ] || fail "an empty answer from gh must be BLIND (exit 2), not a zero count. got rc=$rc: $out"
grep -q 'verdict=BLIND' <<<"$out" || fail "expected verdict=BLIND, got: $out"
out="$(TEMPO_REPO='' TEMPO_CONF_DIR="$T/nope" "$TEMPO" ghost 2>&1)"; rc=$?
[ "$rc" = 2 ] || fail "an unknown project must be BLIND, got rc=$rc: $out"
pass "an unreadable tracker is never an empty one"

echo "case 7 -- the cache spares a held tick its round-trip"
set_counts 12 0; : > "$LEDGER"; row 1; : > "$CALLS"
TEMPO_CACHE_MIN=30 "$TEMPO" p >/dev/null 2>&1
TEMPO_CACHE_MIN=30 "$TEMPO" p >/dev/null 2>&1
n="$(wc -l < "$CALLS")"
[ "$n" = "1" ] || fail "two calls within the TTL should fetch once, gh was called $n time(s)"
out="$(TEMPO_CACHE_MIN=30 "$TEMPO" p 2>&1)"
grep -q 'counts=cache' <<<"$out" || fail "a reused reading must say so on the verdict line, got: $out"
pass "one fetch, and the line admits which reading it used"

echo "case 8 -- wired into the runner: TEMPO holds, and writes no ledger row"
H="$T/home"; mkdir -p "$H/.local/share/scheduler-paced-runner"
cat > "$H/own-run" <<'EOF'
#!/usr/bin/env bash
echo dispatched >> "$DISPATCH_MARK"
exit 0
EOF
chmod +x "$H/own-run"
cat > "$H/gate.sh" <<'EOF'
#!/usr/bin/env bash
echo "verdict=RUN"; exit 0
EOF
chmod +x "$H/gate.sh"
export DISPATCH_MARK="$T/dispatched"
conf="$T/paced.conf"; echo "solo|1|$H/own-run solo batch" > "$conf"
RLOG="$H/.local/share/scheduler-paced-runner/run.log"
RLEDGER="$H/.local/share/scheduler-paced-runner/ledger.tsv"

tick() {
  HOME="$H" PACED_CONF="$conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    USAGE_GATE="$H/gate.sh" RUN_LEDGER_FILE="$RLEDGER" \
    SCHEDULER_FREEZE_FILE="$T/no-such-freeze" \
    TEMPO_REPO="fake/repo" TEMPO_CACHE_MIN=0 \
    "$RUNNER" >/dev/null 2>&1
}

# too soon: one dispatch a minute ago against a want of 120.
set_counts 12 0
: > "$RLEDGER"; printf '%s\tmonkey\tacct\tsolo\tbatch\t0\tWORKED\tr\n' "$(date -Is -d '-1 min')" > "$RLEDGER"
before="$(wc -l < "$RLEDGER")"
tick
[ ! -s "$DISPATCH_MARK" ] || fail "tempo said HOLD and the runner dispatched anyway"
grep -q 'TEMPO solo' "$RLOG" 2>/dev/null || fail "expected a TEMPO line in the runner log"
grep -q 'HOLD (gate' "$RLOG" 2>/dev/null && fail "a pace hold must not be logged in the gate's vocabulary"
[ "$(wc -l < "$RLEDGER")" = "$before" ] \
  || fail "a tempo hold appended a ledger row -- that inflates the row counts the DONE cooldown reads"
pass "held, in its own vocabulary, without writing a row"

# BLIND must not become a dispatch.
: > "$COUNTS"; : > "$DISPATCH_MARK"
tick
[ ! -s "$DISPATCH_MARK" ] || fail "tempo was BLIND and the runner dispatched anyway -- no setpoint is not permission"
grep -q 'TEMPO-BLIND solo' "$RLOG" 2>/dev/null || fail "expected a TEMPO-BLIND line naming the failure"
pass "BLIND holds"

# and it does let work through when the clock says so.
set_counts 12 0
printf '%s\tmonkey\tacct\tsolo\tbatch\t0\tWORKED\tr\n' "$(date -Is -d '-300 min')" > "$RLEDGER"
: > "$DISPATCH_MARK"
tick
[ -s "$DISPATCH_MARK" ] || fail "300 min against a want of 120 should have dispatched"
pass "and it is a regulator, not a stop"

if [ "$FAILED" -ne 0 ]; then
  echo "--- runner log ---"; sed 's/^/  /' "$RLOG" 2>/dev/null
  exit 1
fi
echo "OK: tempo paces each project by its actionable backlog, subtracts human-gated work, holds when BLIND, and the runner obeys it in its own vocabulary"
