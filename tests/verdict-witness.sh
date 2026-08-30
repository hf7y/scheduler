#!/usr/bin/env bash
# Witness for NOT-DONE vs GAVE-UP -- bin/verdict.sh and the runner wiring.
#
# The defect this exists to prevent is an ecosystem with no brake, or with a
# brake on the wrong pedal. Before 2026-07-29 the runner's only outcome signal
# was `rc`, and rc=1 meant BOTH "hit --max-turns with work left" (dispatch it
# again) and "concluded the bar cannot be met" (stop dispatching it). Live
# evidence, dexter's own run.log that day: rc=1 at 12:41, rc=0 at 13:05, rc=1
# at 14:08 -- nothing downstream could tell which was which.
#
# This drives the REAL runner (not a reimplementation of its logic) against a
# fake rotation under a fake HOME, and asserts four things. The fourth is the
# one that rots:
#   1. no verdict + rc!=0  => NOT-DONE, and metabolism is NOT reduced
#   2. explicit IMPOSSIBLE => GAVE-UP, and expires_at IS stamped
#   3. explicit DONE       => DONE, and metabolism is NOT reduced
#   4. a verdict from a PREVIOUS run cannot be read as this run's -- the
#      runner consumes it at dispatch. Without that, one IMPOSSIBLE would
#      brake a participant permanently, on every subsequent silent run.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
VERDICT="$ROOT/bin/verdict.sh"
[ -x "$RUNNER" ]  || { echo "runner not executable: $RUNNER"; exit 1; }
[ -x "$VERDICT" ] || { echo "verdict.sh not executable: $VERDICT"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# The classifier's own selftest must pass before the wiring is worth testing.
if "$VERDICT" --selftest >/dev/null 2>&1; then ok "verdict.sh --selftest"
else bad "verdict.sh --selftest failed"; "$VERDICT" --selftest; fi

# --- drive the real runner once, with a one-participant rotation ------------
# Returns the run log on stdout. $1 = what the fake agent should do.
# TMP is created by the CALLER, not here: run_tick's output is consumed via
# $(...), which runs it in a subshell, so anything it assigned would be lost
# and the expires_at assertions would silently test an empty path.
run_tick() {
  local behaviour="$1" pre_verdict="${2:-}"
  mkdir -p "$TMP/.local/share"

  # The fake agent: writes a verdict (or not), then exits with a chosen rc.
  cat > "$TMP/agent.sh" <<AGENT
#!/usr/bin/env bash
case "$behaviour" in
  silent-fail)  exit 1 ;;
  gave-up)      STATE_ROOT="$TMP/.local/share" "$VERDICT" set alpha IMPOSSIBLE "probed the gate, it 401s forever" >/dev/null; exit 1 ;;
  done)         STATE_ROOT="$TMP/.local/share" "$VERDICT" set alpha DONE "bar met" >/dev/null; exit 0 ;;
esac
AGENT
  chmod +x "$TMP/agent.sh"
  echo "alpha|1|1|$TMP/agent.sh" > "$TMP/rot.conf"
  # ROSTER is the only thing that arms a row (#364); PACED_HOST is pinned so
  # the fixture row matches wherever this suite runs.
  echo 'alpha | alpha@testhost | 20m | live' > "$TMP/ROSTER"

  # Seed a verdict as if left by an EARLIER run (case 4).
  if [ -n "$pre_verdict" ]; then
    STATE_ROOT="$TMP/.local/share" "$VERDICT" set alpha "$pre_verdict" "left over from a previous run" >/dev/null
  fi

  HOME="$TMP" \
  PACED_CONF="$TMP/rot.conf" \
  PACED_HOST=testhost \
  SCHEDULER_ROSTER_FILE="$TMP/ROSTER" \
  PACED_FORCE=1 \
  PACED_MAX_PER_TICK=1 \
  SCHEDULER_FREEZE_FILE="$TMP/no-such-freeze" \
    bash "$RUNNER" >/dev/null 2>&1
  cat "$TMP/.local/share/scheduler-paced-runner/run.log" 2>/dev/null
}

# job_state is derived from the wrapper basename: agent.sh -> <HOME>/.local/share/agent.sh
stamped() { [ -f "$TMP/.local/share/agent.sh/expires_at" ]; }

echo "case 1 -- truncated/silent run must be NOT-DONE, and must NOT brake"
TMP="$(mktemp -d)"; log="$(run_tick silent-fail)"
grep -q 'outcome=NOT-DONE' <<<"$log" && ok "classified NOT-DONE" || { bad "expected outcome=NOT-DONE"; echo "$log" | tail -5; }
grep -q 'GAVE-UP' <<<"$log" && bad "silence was treated as giving up -- the exact inversion this guards" || ok "did not report GAVE-UP"
stamped && bad "expires_at stamped on a merely-truncated run (metabolism reduced on progress)" || ok "metabolism untouched"
# Silence must be NAMED, not just tolerated -- otherwise "never reports" and
# "said keep going" read identically in the log forever. This was the first
# live case: scheduler on dexter, 2026-07-29, max-turns with no verdict.
grep -q 'NO-VERDICT alpha' <<<"$log" && ok "absent verdict logged as NO-VERDICT" || { bad "silent run not distinguished from CONTINUE in the log"; echo "$log" | tail -5; }
# hf7y/scheduler#261: the NO-VERDICT case above is named in the run log, but
# the ledger row it writes carried an empty reason column -- indistinguishable
# from an account that is quietly fine. The reason is known at the moment the
# row is written (this is exactly that case), so it must not be blank.
ledger_row="$(tail -1 "$TMP/.local/share/scheduler-paced-runner/ledger.tsv" 2>/dev/null)"
ledger_reason="$(cut -f8 <<<"$ledger_row")"
[ -n "$ledger_reason" ] && ok "ledger reason is not blank on a no-verdict run ($ledger_reason)" \
  || bad "ledger row has an empty reason column for a NO-VERDICT run: $ledger_row"
rm -rf "$TMP"

echo "case 2 -- explicit IMPOSSIBLE must be GAVE-UP, and MUST brake"
TMP="$(mktemp -d)"; log="$(run_tick gave-up)"
grep -q 'outcome=GAVE-UP' <<<"$log" && ok "classified GAVE-UP" || { bad "expected outcome=GAVE-UP"; echo "$log" | tail -5; }
grep -q 'METABOLISM alpha' <<<"$log" && ok "logged the metabolism reduction" || bad "no METABOLISM line"
grep -q '401s forever' <<<"$log" && ok "carried the agent's reason into the log" || bad "reason not logged"
stamped && ok "expires_at stamped -- next tick will skip it" || bad "GAVE-UP did not stamp expires_at; it would keep dispatching"
rm -rf "$TMP"

echo "case 3 -- explicit DONE must be DONE, and must NOT brake"
TMP="$(mktemp -d)"; log="$(run_tick done)"
grep -q 'outcome=DONE' <<<"$log" && ok "classified DONE" || { bad "expected outcome=DONE"; echo "$log" | tail -5; }
stamped && bad "expires_at stamped on success" || ok "metabolism untouched"
grep -q 'NO-VERDICT' <<<"$log" && bad "NO-VERDICT logged for a run that DID write one" || ok "no spurious NO-VERDICT when a verdict exists"
rm -rf "$TMP"

echo "case 4 -- a PREVIOUS run's verdict must not be read as this run's"
# Seed IMPOSSIBLE, then run an agent that says nothing. If the runner did not
# consume the verdict at dispatch, this reads as GAVE-UP and brakes forever.
TMP="$(mktemp -d)"; log="$(run_tick silent-fail IMPOSSIBLE)"
grep -q 'outcome=NOT-DONE' <<<"$log" && ok "stale verdict consumed at dispatch" || { bad "stale IMPOSSIBLE leaked into this run -- a one-time give-up would brake permanently"; echo "$log" | tail -5; }
stamped && bad "stale verdict caused a brake" || ok "metabolism untouched"
rm -rf "$TMP"

echo
echo "verdict-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
