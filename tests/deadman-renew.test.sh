#!/usr/bin/env bash
# HERMETICITY: sources lib/deadman-switch.sh into a throwaway STATE_DIR under
# mktemp and drives it by hand. No clone, no network, no claude, no crontab,
# and no reference to any real job's state. `notify-send` is never reached
# because no case takes the trip path with a real desktop; the trip case writes
# to a fixture LOG and its notify call is already timeout-guarded in the lib.
#
# tests/deadman-renew.test.sh -- witness for deadman_renew, the polarity fix.
#
# THE LOAD-BEARING ASSERTION IS C.
#
# Everything else here checks plumbing. C is the actual claim: a job that keeps
# running does NOT expire. That was false for the entire life of this mechanism
# -- the stamp was written once, on the first run, and never again -- and on
# 2026-08-11 it had all three armed accounts on monkey scheduled to
# self-destruct inside 19 hours while working correctly.
#
# D is its necessary other half. A dead-man switch that can never fire is not a
# fixed dead-man switch, it is a deleted one, so the silence path must still
# trip. If C passes and D fails, this change made things worse.
#
# E guards the interaction that would be easiest to break by accident: the
# GAVE-UP brake in bin/usage-paced-runner.sh works by stamping expires_at IN
# THE PAST. Renewal must not be able to undo a brake applied after it.
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT

# shellcheck source=lib/deadman-switch.sh
. "$ROOT/lib/deadman-switch.sh"

fresh() { # <name> -> sets JOB_NAME/STATE_DIR/LOG for a clean fixture
  JOB_NAME="fixture-$1"
  STATE_DIR="$T/$1"; LOG="$T/$1.log"
  rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"; : > "$LOG"
  export JOB_NAME STATE_DIR LOG
}

echo "--- deadman renew (polarity) ---"

# --- A: first check bootstraps a stamp at now+EXPIRY_DAYS -------------------
fresh a; EXPIRY_DAYS=7
deadman_check >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$STATE_DIR/expires_at" ]; then
  ok "A first run bootstraps a stamp and does not trip"
else
  bad "A first run bootstraps" "rc=$rc, stamp present=$([ -f "$STATE_DIR/expires_at" ] && echo y || echo n)"
fi

# --- B: renew moves the stamp forward --------------------------------------
fresh b; EXPIRY_DAYS=7
deadman_check >/dev/null 2>&1
before="$(cat "$STATE_DIR/expires_at")"
# Re-stamp with a LONGER window so the move is unambiguous even when both
# writes land in the same second -- comparing now+7d to now+7d is a race, and a
# test that passes only because the clock ticked is not a test.
EXPIRY_DAYS=14 deadman_renew; rc=$?
after="$(cat "$STATE_DIR/expires_at")"
if [ "$rc" -eq 0 ] && [[ "$after" > "$before" ]]; then
  ok "B renew pushes the stamp forward"
else
  bad "B renew pushes forward" "rc=$rc, before=$before after=$after"
fi

# --- C: A JOB THAT KEEPS RUNNING NEVER EXPIRES ------------------------------
# THE LOAD-BEARING CASE. Simulate EXPIRY_DAYS=1 and ten consecutive daily runs,
# each one advancing a fake clock by a day. Under the old behaviour the stamp
# was written once and run 2 would have tripped.
# NO SIMULATED CLOCK. The first draft advanced a fake `now` with repeated
# `date -d "+N days"` calls and compared them to a stamp written by an earlier
# `date` call. Those two calls are microseconds apart, so whether the
# comparison tripped depended on whether a SECOND BOUNDARY happened to fall
# between them: it failed roughly one run in five. A test whose result depends
# on the clock ticking is not asserting anything about the code.
#
# The claim is stated directly instead, and it is the whole polarity change:
# a stamp that WOULD trip, does not trip once the job has run. Every timestamp
# below is either well in the past or well in the future, so no boundary
# matters.
fresh c
EXPIRY_DAYS=1
tripped=""
for run in 1 2 3 4 5 6 7 8 9 10; do
  # Each iteration: the job is at the very edge of expiry (a stamp an hour in
  # the past -- under the OLD behaviour this is exactly the state that killed
  # ecosim, since nothing ever moved the stamp).
  date -d "-1 hour" -Is > "$STATE_DIR/expires_at"
  # The run happens and reaches the end, so the engine renews.
  deadman_renew || { tripped="run $run (renew failed)"; break; }
  # The next tick checks. It must NOT trip.
  deadman_check >/dev/null 2>&1 || { tripped="run $run"; break; }
done
if [ -z "$tripped" ]; then
  ok "C ten consecutive runs from an about-to-expire stamp: never trips"
else
  bad "C a running job never expires" "tripped on $tripped"
fi

# --- D: SILENCE STILL TRIPS -------------------------------------------------
# The other half. Same fixture, but the job stops running: no renewal happens,
# so the stamp stays put and the clock passes it.
fresh d; EXPIRY_DAYS=7
date -d "-1 day" -Is > "$STATE_DIR/expires_at"   # a job last alive 8 days ago
deadman_check >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then
  ok "D a silent job still trips (exit 3)"
else
  bad "D silence still trips" "expected 3, got $rc"
fi
if grep -q 'dead-man switch tripped' "$LOG"; then
  ok "D2 the trip writes a run record to the log"
else
  bad "D2 trip writes a record" "no trip line in $LOG"
fi

# --- E: THE GAVE-UP BRAKE SURVIVES ------------------------------------------
# usage-paced-runner.sh brakes an IMPOSSIBLE participant by stamping in the
# past, AFTER the run. Renewal happens during the run, so the brake must win.
fresh e; EXPIRY_DAYS=7
deadman_renew                                     # the run renews...
# ...then the runner brakes. usage-paced-runner.sh writes `date -Is`, i.e. NOW.
# One second earlier is written here rather than exactly now, because
# deadman_check compares with a STRICT `>` against its own `date -Is`: a check
# in the SAME SECOND as the brake does not trip. That is harmless in production
# -- the earliest check is the next cron tick, hours later -- but a test that
# stamped `now` and checked immediately would be asserting the clock ticked
# mid-test, which is a flake, not an assertion. The strictness is noted in the
# PR as a real if currently unreachable edge.
date -d "-1 second" -Is > "$STATE_DIR/expires_at"
deadman_check >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then
  ok "E a GAVE-UP brake applied after renewal still stops the job"
else
  bad "E GAVE-UP brake survives renewal" "expected 3, got $rc"
fi

# --- F: broken contract is loud, not silently skipped -----------------------
( STATE_DIR="" deadman_renew >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then
  ok "F renew with no STATE_DIR is a loud broken contract (exit 2)"
else
  bad "F broken contract is loud" "expected 2, got $rc"
fi
( STATE_DIR="$T/does-not-exist" deadman_renew >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then
  ok "F2 renew into a missing STATE_DIR is exit 2, not a silent no-op"
else
  bad "F2 missing STATE_DIR is loud" "expected 2, got $rc"
fi

echo "deadman-renew: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
