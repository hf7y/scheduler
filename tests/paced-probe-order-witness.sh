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
#   1. A rotation whose other rows are foreign costs ZERO probes. Since
#      2026-08-19 those rows are filtered at load, so there is nothing to
#      walk past at all -- the guarantee is met earlier, not differently.
#   2. A rotation with exactly one runnable row costs exactly ONE probe.
#   3. A rotation with NO runnable row still terminates, in one lap, having
#      probed zero times -- this is the guarantee the `examined` counter
#      carries, and moving the runnability check ahead of the probe made
#      `examined` the ONLY thing carrying it.
#
# The gate is replaced by a counting stub via the runner's own USAGE_GATE knob,
# so this test spends no quota and dispatches no real work.
#
# The freeze allowlist is a FIXTURE, not the live schedule/FREEZE. It used to
# be the live file, with the participants chosen to match whoever happened to
# be exempt on monkey -- which made this witness fail whenever dispatch was
# legitimately paused. On 2026-08-15 a 4-day pause commented out all seven
# EXEMPT lines and CI then refused the pause: "expected 1 DISPATCH, got 0".
# A paused fleet is a state the repo must be allowed to be in, so the witness
# supplies its own allowlist and measures probe ordering, which is what it is
# for -- not the contents of the production file.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# The witness's own freeze allowlist -- see the header. freeze-check.sh reads
# SCHEDULER_FREEZE_FILE when set, so this decouples the test from whatever the
# live fleet's arm/pause state happens to be.
mkdir -p "$T/schedule"
for a in ecosim bibliothecaire vim-arcade; do
  echo "EXEMPT: $a@monkey" >> "$T/schedule/FREEZE"
done
export SCHEDULER_FREEZE_FILE="$T/schedule/FREEZE"
# The cache is keyed per-uid and would otherwise carry the live file's verdict
# into this run.
export SCHEDULER_FREEZE_CACHE="$T/freeze-cache"
# ...and the ROSTER needs the same fixture treatment, for a stronger reason.
# participant_enabled asks schedule/ROSTER and nothing else (#364), and
# roster_state_for reads $REPO_ROOT/schedule/ROSTER unless
# SCHEDULER_ROSTER_FILE points elsewhere. The rows below are real project
# names, so the LIVE roster -- parked throughout today -- would otherwise
# decide whether this test dispatches, failing it for a reason that has
# nothing to do with probe ordering. An EMPTY file worked only while an
# unnamed row fell back to the conf column, so it now states its rows.
{ echo 'ecosim         | ecosim@monkey         | 20m | live'
  echo 'bibliothecaire | bibliothecaire@monkey | 20m | live'
  echo 'vim-arcade     | vim-arcade@monkey     | 20m | live'
} > "$T/schedule/ROSTER"
export SCHEDULER_ROSTER_FILE="$T/schedule/ROSTER"
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

  # TEMPO_ENABLED=0 for the same reason the freeze allowlist is a fixture: this
  # witness measures GATE PROBE ORDERING, and the rows it uses are real project
  # names, so a live tempo would read those projects' real trackers over the
  # network and hold on whatever their backlogs happen to be today. That is a
  # second regulator's verdict deciding a test about the first one, and it
  # would make this suite non-hermetic. tests/tempo-witness.sh owns tempo.
  PROBE_TALLY="$h/probes"; : > "$PROBE_TALLY"; export PROBE_TALLY
  HOME="$h" PACED_CONF="$conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    SCHEDULER_FREEZE_FILE="$SCHEDULER_FREEZE_FILE" \
    SCHEDULER_FREEZE_CACHE="$SCHEDULER_FREEZE_CACHE" \
    TEMPO_ENABLED=0 \
    MILESTONE_GATE=0 \
    USAGE_GATE="$h/gate.sh" "$RUNNER" >/dev/null 2>&1

  local log="$h/.local/share/scheduler-paced-runner/run.log"
  # `grep -c` prints 0 AND exits 1 when there is no match, so a `|| echo 0`
  # here would emit the field TWICE and silently shift every field after it.
  # `|| true` keeps the count grep already printed.
  local nprobe ndisp nexh
  nprobe="$(wc -l < "$PROBE_TALLY")"
  ndisp="$(grep -c ' DISPATCH ' "$log" 2>/dev/null || true)"
  # Either terminator counts: the pre-2026-08-19 walk logged ROTATION
  # EXHAUSTED after a full lap; the runner now filters foreign rows at load
  # and never enters the loop at all. Both mean "ended, did not spin".
  nexh="$(grep -cE 'ROTATION EXHAUSTED|no runnable participant' "$log" 2>/dev/null || true)"
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

# (3) NOTHING runnable: zero probes, no dispatch, and it TERMINATES.
# Since 2026-08-19 foreign rows are dropped at load ("every runner runs only
# itself"), so this exits before the loop rather than walking a full lap. The
# guarantee under test is unchanged and strictly cheaper to meet.
read -r probes disp exh LAST_LOG <<< "$(tick -1 2)"
[ "$probes" = "0" ] || fail "no runnable row: expected 0 probes, got $probes"
[ "$disp" = "0" ]   || fail "no runnable row: expected 0 DISPATCH, got $disp"
[ "$exh" = "1" ]    || fail "no runnable row: expected a termination line (ROTATION EXHAUSTED, or the load-time no-runnable-participant exit) -- it must end, not spin"

if [ "$FAILED" -ne 0 ]; then
  echo "--- last tick's log ---"
  sed 's/^/  /' "${LAST_LOG:-/dev/null}" 2>/dev/null
  exit 1
fi
echo "OK: gate probed once per dispatchable row, never for a foreign one; empty lap terminates"
