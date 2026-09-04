#!/usr/bin/env bash
# milestone-gate-witness.sh -- dispatch only while a milestone has an open
# issue; BLIND never reads as "finished".
# WHY. #541's predicate has one dangerous failure: an unreadable answer
# collapsing into 0. Zero stops a project, empty means we could not ask, and
# merging them stops all nineteen accounts on one expired token. Also: holding
# never writes ROSTER (#291). gh and the gate are stubbed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

mkdir -p "$T/schedule"
echo "EXEMPT: ecosim@monkey" > "$T/schedule/FREEZE"
export SCHEDULER_FREEZE_FILE="$T/schedule/FREEZE"
export SCHEDULER_FREEZE_CACHE="$T/freeze-cache"
ROSTER="$T/schedule/ROSTER"
echo 'ecosim         | ecosim@monkey         | 20m | live' > "$ROSTER"
export SCHEDULER_ROSTER_FILE="$ROSTER"
ROSTER_BEFORE="$(cat "$ROSTER")"

tick() {
  local ghmode="$1"; shift
  local h="$T/h$$-$RANDOM"; mkdir -p "$h/.local/share/scheduler-paced-runner" "$h/bin"

  cat > "$h/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *milestones*)
    if [ "$ghmode" = blind ]; then exit 1; fi
    echo "$ghmode"
    ;;
  *) echo "milestone-gate-witness: unexpected gh call: \$*" >&2; exit 64 ;;
esac
EOF
  cat > "$h/gate.sh" <<'EOF'
#!/usr/bin/env bash
echo "verdict=RUN"
exit 0
EOF
  cat > "$h/own-run" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$h/bin/gh" "$h/gate.sh" "$h/own-run"

  echo "ecosim|1|$h/own-run ecosim batch" > "$h/paced.conf"
  echo 0 > "$h/.local/share/scheduler-paced-runner/rotation.idx"

  env "$@" \
    HOME="$h" PATH="$h/bin:$PATH" \
    PACED_CONF="$h/paced.conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    SCHEDULER_FREEZE_FILE="$SCHEDULER_FREEZE_FILE" \
    SCHEDULER_FREEZE_CACHE="$SCHEDULER_FREEZE_CACHE" \
    SCHEDULER_ROSTER_FILE="$SCHEDULER_ROSTER_FILE" \
    TEMPO_ENABLED=0 \
    USAGE_GATE="$h/gate.sh" "$RUNNER" >/dev/null 2>&1

  echo "$h/.local/share/scheduler-paced-runner/run.log"
}

has() { grep -q "$2" "$1" 2>/dev/null; }

LOG="$(tick 2)"
has "$LOG" ' DISPATCH ' || fail "1 open milestone: expected a DISPATCH, got none ($LOG)"
has "$LOG" 'MILESTONE-HELD' && fail "1 open milestone: held a project that has work to do"

LOG="$(tick 0)"
has "$LOG" 'MILESTONE-HELD' || fail "0 open milestones: expected MILESTONE-HELD ($LOG)"
has "$LOG" ' DISPATCH ' && fail "0 open milestones: dispatched a project that has hit its milestone"

LOG="$(tick blind)"
has "$LOG" 'MILESTONE-BLIND' || fail "unreadable milestones: expected MILESTONE-BLIND ($LOG)"
has "$LOG" ' DISPATCH ' && fail "unreadable milestones: dispatched despite holding by default"
has "$LOG" 'MILESTONE-HELD' && fail "unreadable milestones read as MILESTONE-HELD -- BLIND collapsed into 'finished', which is the failure this witness exists for"

LOG="$(tick blind MILESTONE_GATE_BLIND_HOLDS=0)"
has "$LOG" ' DISPATCH ' || fail "MILESTONE_GATE_BLIND_HOLDS=0: expected a DISPATCH ($LOG)"

LOG="$(tick 0 MILESTONE_GATE=0)"
has "$LOG" ' DISPATCH ' || fail "MILESTONE_GATE=0: expected a DISPATCH ($LOG)"
has "$LOG" 'MILESTONE-' && fail "MILESTONE_GATE=0: the gate still spoke"

[ "$(cat "$ROSTER")" = "$ROSTER_BEFORE" ] || fail "the milestone gate rewrote schedule/ROSTER -- holding is not parking (#291)"

[ "$FAILED" -eq 0 ] && echo "PASS: milestone-gate-witness"
exit "$FAILED"
