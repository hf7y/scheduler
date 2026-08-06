#!/usr/bin/env bash
# paced-probe-order-witness.sh -- the usage gate is probed only for rows this
# account can actually dispatch.
#
# WHY THIS EXISTS. usage-paced-runner.sh's dispatch loop used to probe the
# usage gate at the TOP of every iteration and only afterwards ask whether the
# row it had drawn was executable under this uid. On monkey, where three unix
# accounts each walk the same three-row schedule/_paced.monkey.conf and each
# can execute exactly one of those rows, that bought 3 live probes per account
# per tick -- 9 host-wide -- to make 3 dispatch decisions. Every probe but one
# per account was spent learning something a stat(2) already knew.
#
# The gate probe is not free and it is not local: it is a live call against the
# ONE Anthropic account every host and every uid share. So the ordering is a
# real property, not a style preference, and it is the kind of property that
# re-inverts the first time somebody moves a block "for readability". Hence a
# witness rather than a comment.
#
# WHAT IS ASSERTED
#   1. A rotation whose next rows are foreign costs ZERO probes to walk past.
#   2. A rotation with exactly one runnable row costs exactly ONE probe.
#   3. A rotation with NO runnable row still terminates, in one lap, having
#      probed zero times -- this is the guarantee the `examined` counter
#      carries, and moving the runnability check ahead of the probe made
#      `examined` the ONLY thing carrying it.
#
# The gate is replaced by a counting stub via the runner's own USAGE_GATE knob,
# so this test spends no quota and dispatches no real work. Participant names
# are monkey's real three because schedule/FREEZE exempts exactly those on that
# host and PACED_HOST is pinned to monkey below; a name not in that file would
# be refused by freeze-check.sh and the test would measure the freeze instead.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

# One tick. $1 = 0-based index of the runnable row, or -1 for "none runnable".
# $2 = value to seed rotation.idx with (the row the previous tick landed on).
# Echoes "<probes> <dispatches> <exhausted-lines> <path to that tick's log>"
# -- the log path is carried out as a field because `tick` runs in a command
# substitution and cannot set a variable the caller will see.
tick() {
  local own_idx="$1" seed="$2"
  local h="$T/h$$-$RANDOM"; mkdir -p "$h/.local/share/scheduler-paced-runner"

  cat > "$h/gate.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROBE" >> "$PROBE_TALLY"
echo "verdict=RUN"
echo "# RUN -- witness stub; no live probe was made"
exit 0
EOF
  cat > "$h/own-run" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$h/gate.sh" "$h/own-run"

  local conf="$h/paced.conf" i=0 a
  : > "$conf"
  for a in ecosim bibliothecaire vim-arcade; do
    if [ "$i" -eq "$own_idx" ]; then
      echo "$a|1|$h/own-run $a batch" >> "$conf"
    else
      # A path that cannot exist: the same condition a foreign account's
      # scheduler-run presents to a uid that cannot read its $HOME.
      echo "$a|1|$h/not-mine-$a batch" >> "$conf"
    fi
    i=$((i + 1))
  done

  echo "$seed" > "$h/.local/share/scheduler-paced-runner/rotation.idx"

  PROBE_TALLY="$h/probes"; : > "$PROBE_TALLY"; export PROBE_TALLY
  HOME="$h" PACED_CONF="$conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    USAGE_GATE="$h/gate.sh" "$RUNNER" >/dev/null 2>&1

  local log="$h/.local/share/scheduler-paced-runner/run.log"
  # `grep -c` prints 0 AND exits 1 when there is no match, so a `|| echo 0`
  # here would emit the field TWICE and silently shift every field after it.
  # `|| true` keeps the count grep already printed.
  local nprobe ndisp nexh
  nprobe="$(wc -l < "$PROBE_TALLY")"
  ndisp="$(grep -c ' DISPATCH ' "$log" 2>/dev/null || true)"
  nexh="$(grep -c 'ROTATION EXHAUSTED' "$log" 2>/dev/null || true)"
  echo "${nprobe:-0} ${ndisp:-0} ${nexh:-0} $log"
}

# (1)+(2) own row LAST in the lap: two foreign rows walked, then a dispatch.
# seed=2 means the pointer wraps to row 0 first, so this walks the whole
# rotation -- the steady state of a real monkey account.
read -r probes disp _exh LAST_LOG <<< "$(tick 2 1)"
[ "$probes" = "1" ] || fail "own row last in lap: expected 1 probe, got $probes (a probe was spent on a foreign row)"
[ "$disp" = "1" ]   || fail "own row last in lap: expected 1 DISPATCH, got $disp"

# (2b) own row FIRST: one probe, one dispatch, no foreign row reached.
read -r probes disp _exh LAST_LOG <<< "$(tick 0 2)"
[ "$probes" = "1" ] || fail "own row first: expected 1 probe, got $probes"
[ "$disp" = "1" ]   || fail "own row first: expected 1 DISPATCH, got $disp"

# (3) NOTHING runnable: zero probes, one full lap, loop terminates.
read -r probes disp exh LAST_LOG <<< "$(tick -1 2)"
[ "$probes" = "0" ] || fail "no runnable row: expected 0 probes, got $probes"
[ "$disp" = "0" ]   || fail "no runnable row: expected 0 DISPATCH, got $disp"
[ "$exh" = "1" ]    || fail "no runnable row: expected ROTATION EXHAUSTED (the loop must end after one lap, not spin)"

if [ "$FAILED" -ne 0 ]; then
  echo "--- last tick's log ---"
  sed 's/^/  /' "${LAST_LOG:-/dev/null}" 2>/dev/null
  exit 1
fi
echo "OK: gate probed once per dispatchable row, never for a foreign one; empty lap terminates"
