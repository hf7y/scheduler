#!/usr/bin/env bash
# gate-error-streak-witness.sh -- usage-paced-runner.sh must say something
# loud when the usage gate is BROKEN (rc=2, probe failed/unparseable), not
# just fold it silently into the same HOLD as a busy quota (rc=1).
#
# WHY THIS EXISTS. #191: rc=2 is deliberately treated as a fail-safe HOLD --
# this witness does not change that, and must not. But collapsing both rcs
# into one "HOLD (gate rc=$rc)" line meant a broken probe and a busy quota
# looked identical to anything not grepping run.log for "rc=2" by hand. On
# dexter, 332 ERROR ticks over three days -- including a 319-tick unbroken
# streak, ~57 consecutive hours -- went unnoticed until read from the log
# after the fact.
#
# WHAT IS ASSERTED
#   1. A single rc=2 tick still logs an ordinary HOLD line, no streak line.
#   2. GATE_ERROR_STREAK_THRESHOLD consecutive rc=2 ticks produce exactly one
#      GATE-ERROR-STREAK line, stamped with the streak length.
#   3. An intervening rc=1 (real HOLD -- the gate itself is working) resets
#      the counter: the next rc=2 run starts counting from 1, not from where
#      it left off. rc=0 (RUN) hits the same reset branch in the source, so
#      is not re-tested separately.
#
# The gate is a scripted stub via USAGE_GATE, so this spends no quota and
# dispatches no real work.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

H="$T/home"; mkdir -p "$H"
cat > "$H/own-run" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$H/own-run"

conf="$T/paced.conf"
echo "solo|1|$H/own-run solo batch" > "$conf"
# ROSTER is the only thing that arms a row (#364), so a fixture must name it.
roster="$T/ROSTER"
echo 'solo | solo@monkey | 20m | live' > "$roster"

GATE_RC_FILE="$T/gate-rc"
cat > "$H/gate.sh" <<'EOF'
#!/usr/bin/env bash
rc="$(cat "$GATE_RC_FILE")"
case "$rc" in
  0) echo "verdict=RUN" ;;
  1) echo "verdict=HOLD" ;;
  2) echo "verdict=ERROR reason=stub" ;;
esac
exit "$rc"
EOF
chmod +x "$H/gate.sh"

LOG="$H/.local/share/scheduler-paced-runner/run.log"

tick() {
  local rc="$1"
  echo "$rc" > "$GATE_RC_FILE"
  HOME="$H" PACED_CONF="$conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    SCHEDULER_ROSTER_FILE="$roster" \
    GATE_ERROR_STREAK_THRESHOLD=3 \
    USAGE_GATE="$H/gate.sh" "$RUNNER" >/dev/null 2>&1
}

streak_lines() { grep -c 'GATE-ERROR-STREAK' "$LOG" 2>/dev/null || true; }

# (1) one rc=2 tick: ordinary HOLD logged, no streak line yet (threshold=3).
tick 2
n="$(streak_lines)"
[ "${n:-0}" = "0" ] || fail "single ERROR tick: expected 0 GATE-ERROR-STREAK lines, got $n"
grep -q 'HOLD (gate rc=2)' "$LOG" || fail "single ERROR tick: expected an ordinary HOLD line"

# (2) two more rc=2 ticks (streak reaches 3): exactly one GATE-ERROR-STREAK line, n=3.
tick 2
tick 2
n="$(streak_lines)"
[ "${n:-0}" = "1" ] || fail "streak of 3: expected exactly 1 GATE-ERROR-STREAK line, got $n"
grep -q 'GATE-ERROR-STREAK n=3' "$LOG" || fail "streak of 3: expected the line to name n=3"

# (3) a real HOLD (rc=1) resets the counter -- confirmed by driving back up
# to threshold and checking the count restarted at 1, not resumed at 4.
tick 1
tick 2
n="$(streak_lines)"
[ "${n:-0}" = "1" ] || fail "after HOLD reset: expected still exactly 1 GATE-ERROR-STREAK line so far, got $n"
tick 2
tick 2
n="$(streak_lines)"
[ "${n:-0}" = "2" ] || fail "second streak of 3 after reset: expected 2 total GATE-ERROR-STREAK lines, got $n"

if [ "$FAILED" -ne 0 ]; then
  echo "--- run.log ---"
  sed 's/^/  /' "$LOG" 2>/dev/null
  exit 1
fi
echo "OK: consecutive gate ERROR (rc=2) ticks produce a distinct GATE-ERROR-STREAK line every threshold ticks; a real HOLD resets the count"
