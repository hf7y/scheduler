#!/usr/bin/env bash
# milestone-gate-witness.sh -- dispatch only while a milestone has an open
# issue A RUN COULD CLOSE; BLIND never reads as "finished".
# WHY. #541's predicate has one dangerous failure: an unreadable answer
# collapsing into 0. Zero stops a project, empty means we could not ask, and
# merging them stops all nineteen accounts on one expired token. Also: holding
# never writes ROSTER (#291). #587 adds a second failure the same shape: an
# issue labelled `needs-human` -- one a run is forbidden to close -- must not
# hold the gate open either, the way tempo.sh already excludes it from
# `actionable`. gh and the gate are stubbed; the milestone-issues call runs
# the runner's REAL --jq filter against a fixture, the way
# milestone-self-fed-witness.sh does, so the label filter itself is exercised.
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

# tick <mode> <issues-json> [env...] -> run.log path
#   mode: milestones-blind | issues-blind | ok
#   issues-json: fixture fed to the runner's REAL --jq filter for the
#     issues?state=open call (ignored when mode != ok)
tick() {
  local mode="$1" issues_json="$2"; shift 2
  local h="$T/h$$-$RANDOM"; mkdir -p "$h/.local/share/scheduler-paced-runner" "$h/bin" "$h/tempo-conf"
  printf '%s' "$issues_json" > "$h/issues-fixture.json"

  cat > "$h/bin/gh" <<EOF
#!/usr/bin/env bash
argv=("\$@")
case "\$*" in
  *milestones*)
    if [ "$mode" = milestones-blind ]; then exit 1; fi
    echo ""
    ;;
  *issues*state=open*)
    if [ "$mode" = issues-blind ]; then exit 1; fi
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
    TEMPO_CONF_DIR="$h/tempo-conf" \
    USAGE_GATE="$h/gate.sh" "$RUNNER" >/dev/null 2>&1

  echo "$h/.local/share/scheduler-paced-runner/run.log"
}

has() { grep -q "$2" "$1" 2>/dev/null; }

ONE_OPEN='[{"number":10,"milestone":{"number":1,"state":"open"},"labels":[]}]'
EMPTY='[]'
NEEDS_HUMAN_ONLY='[{"number":97,"milestone":{"number":1,"state":"open"},"labels":[{"name":"needs-human"}]}]'
MIXED='[{"number":97,"milestone":{"number":1,"state":"open"},"labels":[{"name":"needs-human"}]},{"number":98,"milestone":{"number":1,"state":"open"},"labels":[]}]'

LOG="$(tick ok "$ONE_OPEN")"
has "$LOG" ' DISPATCH ' || fail "1 open actionable issue: expected a DISPATCH, got none ($LOG)"
has "$LOG" 'MILESTONE-HELD' && fail "1 open actionable issue: held a project that has work to do"

LOG="$(tick ok "$EMPTY")"
has "$LOG" 'MILESTONE-HELD' || fail "0 open issues: expected MILESTONE-HELD ($LOG)"
has "$LOG" ' DISPATCH ' && fail "0 open issues: dispatched a project that has hit its milestone"

# #587: chezz's case -- a milestone's only open issue is needs-human. A run
# may not close it, so it must not count as permission to dispatch either.
LOG="$(tick ok "$NEEDS_HUMAN_ONLY")"
has "$LOG" 'MILESTONE-HELD' || fail "needs-human-only milestone: expected MILESTONE-HELD, the label must not hold the gate open ($LOG)"
has "$LOG" ' DISPATCH ' && fail "needs-human-only milestone: dispatched on the authority of an issue it may not touch"

# A milestone with a needs-human issue AND a plain one still has real work.
LOG="$(tick ok "$MIXED")"
has "$LOG" ' DISPATCH ' || fail "needs-human plus a plain issue: expected a DISPATCH, the plain issue is still actionable ($LOG)"
has "$LOG" 'MILESTONE-HELD' && fail "needs-human plus a plain issue: held despite one closeable issue remaining"

LOG="$(tick milestones-blind "$EMPTY")"
has "$LOG" 'MILESTONE-BLIND' || fail "unreadable milestones list: expected MILESTONE-BLIND ($LOG)"
has "$LOG" ' DISPATCH ' && fail "unreadable milestones list: dispatched despite holding by default"
has "$LOG" 'MILESTONE-HELD' && fail "unreadable milestones list read as MILESTONE-HELD -- BLIND collapsed into 'finished', which is the failure this witness exists for"

# The label-aware issues call can fail independently of the milestones call;
# that must hold BLIND too, not fall back to the raw (pre-#587) open count.
LOG="$(tick issues-blind "$EMPTY")"
has "$LOG" 'MILESTONE-BLIND' || fail "unreadable issues list: expected MILESTONE-BLIND ($LOG)"
has "$LOG" ' DISPATCH ' && fail "unreadable issues list: dispatched despite holding by default"

LOG="$(tick milestones-blind "$EMPTY" MILESTONE_GATE_BLIND_HOLDS=0)"
has "$LOG" ' DISPATCH ' || fail "MILESTONE_GATE_BLIND_HOLDS=0: expected a DISPATCH ($LOG)"

LOG="$(tick ok "$EMPTY" MILESTONE_GATE=0)"
has "$LOG" ' DISPATCH ' || fail "MILESTONE_GATE=0: expected a DISPATCH ($LOG)"
has "$LOG" 'MILESTONE-' && fail "MILESTONE_GATE=0: the gate still spoke"

[ "$(cat "$ROSTER")" = "$ROSTER_BEFORE" ] || fail "the milestone gate rewrote schedule/ROSTER -- holding is not parking (#291)"

[ "$FAILED" -eq 0 ] && echo "PASS: milestone-gate-witness"
exit "$FAILED"
