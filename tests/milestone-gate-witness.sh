#!/usr/bin/env bash
# milestone-gate-witness.sh -- dispatch only while a milestone has an open,
# unblocked issue; BLIND never reads as "finished" (#587: needs-human/assigned
# subtract from the count, same as tempo.sh's ACTIONABLE).
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

tick() {  # <milestones-json|BLIND> <issues-json> [env...]; runs the runner's REAL --jq filters on the fixtures
  local ms_json="$1" iss_json="$2"; shift 2
  local h="$T/h$$-$RANDOM"; mkdir -p "$h/.local/share/scheduler-paced-runner" "$h/bin"
  printf '%s' "$ms_json" > "$h/ms-fixture.json"
  printf '%s' "$iss_json" > "$h/issues-fixture.json"
  local blind_ms=0; [ "$ms_json" = BLIND ] && blind_ms=1

  cat > "$h/bin/gh" <<EOF
#!/usr/bin/env bash
argv=("\$@")
case "\$*" in
  *milestones?state=open*)
    [ "$blind_ms" = 1 ] && exit 1
    cat "$h/ms-fixture.json"
    ;;
  *issues?state=open*)
    filter=""
    for i in "\${!argv[@]}"; do
      [ "\${argv[\$i]}" = "--jq" ] && filter="\${argv[\$((i+1))]}"
    done
    jq -r "\$filter" "$h/issues-fixture.json"
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

MS_TWO='[{"number":1,"description":""},{"number":2,"description":""}]'
MS_ONE='[{"number":1,"description":""}]'
MS_EMPTY='[]'
UNBLOCKED_TWO='[{"number":10,"milestone":{"number":1,"state":"open"},"labels":[],"assignees":[]},{"number":11,"milestone":{"number":2,"state":"open"},"labels":[],"assignees":[]}]'
NO_ISSUES='[]'
NEEDS_HUMAN_ONLY='[{"number":12,"milestone":{"number":1,"state":"open"},"labels":[{"name":"needs-human"}],"assignees":[]}]'
ASSIGNED_ONLY='[{"number":13,"milestone":{"number":1,"state":"open"},"labels":[],"assignees":[{"login":"zach"}]}]'
MIXED_SAME_MILESTONE='[{"number":14,"milestone":{"number":1,"state":"open"},"labels":[{"name":"needs-human"}],"assignees":[]},{"number":15,"milestone":{"number":1,"state":"open"},"labels":[],"assignees":[]}]'

LOG="$(tick "$MS_TWO" "$UNBLOCKED_TWO")"
has "$LOG" ' DISPATCH ' || fail "2 unblocked milestones: expected a DISPATCH, got none ($LOG)"
has "$LOG" 'MILESTONE-HELD' && fail "2 unblocked milestones: held a project that has work to do"

LOG="$(tick "$MS_EMPTY" "$NO_ISSUES")"
has "$LOG" 'MILESTONE-HELD' || fail "0 open milestones: expected MILESTONE-HELD ($LOG)"
has "$LOG" ' DISPATCH ' && fail "0 open milestones: dispatched a project that has hit its milestone"

LOG="$(tick "$MS_ONE" "$NEEDS_HUMAN_ONLY")"
has "$LOG" 'MILESTONE-HELD' || fail "#587: needs-human-only milestone must read as no actionable milestone ($LOG)"
has "$LOG" ' DISPATCH ' && fail "#587: dispatched on a milestone whose only open issue is needs-human"

LOG="$(tick "$MS_ONE" "$ASSIGNED_ONLY")"
has "$LOG" 'MILESTONE-HELD' || fail "assignee-only milestone must also read as no actionable milestone (tempo.sh's OR) ($LOG)"
has "$LOG" ' DISPATCH ' && fail "dispatched on a milestone whose only open issue carries an assignee"

LOG="$(tick "$MS_ONE" "$MIXED_SAME_MILESTONE")"
has "$LOG" ' DISPATCH ' || fail "milestone with one blocked and one unblocked issue: expected a DISPATCH ($LOG)"

# The blocked-label set is not read from TEMPO_BLOCKED_LABELS alone --
# milestone_blocked_labels() also resolves schedule/_tempo.conf, the same
# file tempo.sh itself reads, so the gate and the pacing setpoint can never
# disagree about which label means "not work a run can do" (#587).
CUSTOM_LABEL_ONLY='[{"number":16,"milestone":{"number":1,"state":"open"},"labels":[{"name":"needs-review"}],"assignees":[]}]'
CUSTOM_CONF_DIR="$T/custom-conf-$$"
mkdir -p "$CUSTOM_CONF_DIR"
echo 'TEMPO_BLOCKED_LABELS=needs-review' > "$CUSTOM_CONF_DIR/_tempo.conf"
LOG="$(tick "$MS_ONE" "$CUSTOM_LABEL_ONLY" TEMPO_CONF_DIR="$CUSTOM_CONF_DIR")"
has "$LOG" 'MILESTONE-HELD' || fail "schedule/_tempo.conf's TEMPO_BLOCKED_LABELS=needs-review must gate the same as the env var ($LOG)"
has "$LOG" ' DISPATCH ' && fail "dispatched on a milestone whose only open issue carries the conf-configured blocked label"

LOG="$(tick BLIND "$NO_ISSUES")"
has "$LOG" 'MILESTONE-BLIND' || fail "unreadable milestones: expected MILESTONE-BLIND ($LOG)"
has "$LOG" ' DISPATCH ' && fail "unreadable milestones: dispatched despite holding by default"
has "$LOG" 'MILESTONE-HELD' && fail "unreadable milestones read as MILESTONE-HELD -- BLIND collapsed into 'finished', which is the failure this witness exists for"

LOG="$(tick BLIND "$NO_ISSUES" MILESTONE_GATE_BLIND_HOLDS=0)"
has "$LOG" ' DISPATCH ' || fail "MILESTONE_GATE_BLIND_HOLDS=0: expected a DISPATCH ($LOG)"

LOG="$(tick "$MS_EMPTY" "$NO_ISSUES" MILESTONE_GATE=0)"
has "$LOG" ' DISPATCH ' || fail "MILESTONE_GATE=0: expected a DISPATCH ($LOG)"
has "$LOG" 'MILESTONE-' && fail "MILESTONE_GATE=0: the gate still spoke"

[ "$(cat "$ROSTER")" = "$ROSTER_BEFORE" ] || fail "the milestone gate rewrote schedule/ROSTER -- holding is not parking (#291)"

[ "$FAILED" -eq 0 ] && echo "PASS: milestone-gate-witness"
exit "$FAILED"
