#!/usr/bin/env bash
# milestone-chain-witness.sh -- a milestone that empties can name a successor
# in its OWN description (`NEXT: <title>`); the gate still holds (mcount==0
# does not become a DISPATCH -- that would reopen exactly the self-feeding
# hazard #541/#575 exist to prevent) but logs which case it is: a chain
# waiting on a successor that has no open issue yet (MILESTONE-CHAIN-HELD) vs
# a project that named no successor at all (MILESTONE-HELD, unchanged, and
# terminal in the sense #582 asks for -- "the end of a chain holds, and logs
# why"). Runs the REAL --jq filter against a fixture, like
# milestone-self-fed-witness.sh does for issues, not a hand-simulated count.
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

tick() {  # <milestones-json> -> "log run.log" path; runs the runner's REAL --jq filter on the fixture
  local milestones_json="$1"
  local h="$T/h$$-$RANDOM"; mkdir -p "$h/.local/share/scheduler-paced-runner" "$h/bin"
  printf '%s' "$milestones_json" > "$h/milestones-fixture.json"

  cat > "$h/bin/gh" <<EOF
#!/usr/bin/env bash
argv=("\$@")
case "\$*" in
  *milestones*)
    filter=""
    for i in "\${!argv[@]}"; do
      [ "\${argv[\$i]}" = "--jq" ] && filter="\${argv[\$((i+1))]}"
    done
    jq -r "\$filter" "$h/milestones-fixture.json"
    ;;
  *) echo "milestone-chain-witness: unexpected gh call: \$*" >&2; exit 64 ;;
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

  env HOME="$h" PATH="$h/bin:$PATH" \
    PACED_CONF="$h/paced.conf" PACED_HOST=monkey PACED_MAX_PER_TICK=1 \
    SCHEDULER_FREEZE_FILE="$SCHEDULER_FREEZE_FILE" \
    SCHEDULER_FREEZE_CACHE="$SCHEDULER_FREEZE_CACHE" \
    SCHEDULER_ROSTER_FILE="$SCHEDULER_ROSTER_FILE" \
    TEMPO_ENABLED=0 \
    USAGE_GATE="$h/gate.sh" "$RUNNER" >/dev/null 2>&1

  echo "$h/.local/share/scheduler-paced-runner/run.log $h/.local/share/scheduler-paced-runner/ledger.tsv"
}

has() { grep -q "$2" "$1" 2>/dev/null; }

# empty milestone, successor declared -> chained hold, names the successor, never a DISPATCH
CHAINED='[{"title":"Week 1","open_issues":0,"description":"Wrapping up.\nNEXT: Week 2"}]'
read -r LOG LEDGER <<<"$(tick "$CHAINED")"
has "$LOG" 'MILESTONE-CHAIN-HELD' || fail "empty milestone naming a successor: expected MILESTONE-CHAIN-HELD ($LOG)"
has "$LOG" 'Week 2' || fail "the successor's title should appear in the log line ($LOG)"
has "$LOG" ' DISPATCH ' && fail "a chained-but-empty successor must not become a DISPATCH -- that reopens the self-feeding hazard (#541/#575) ($LOG)"
has "$LEDGER" 'MILESTONE-CHAIN-HELD' || fail "expected a MILESTONE-CHAIN-HELD ledger row ($LEDGER)"

# empty milestone, no successor declared -> the plain, terminal MILESTONE-HELD (unchanged)
TERMINAL='[{"title":"Week 1","open_issues":0,"description":"Wrapping up, nothing more planned."}]'
read -r LOG LEDGER <<<"$(tick "$TERMINAL")"
has "$LOG" 'MILESTONE-HELD' || fail "empty milestone, no successor: expected plain MILESTONE-HELD ($LOG)"
has "$LOG" 'MILESTONE-CHAIN-HELD' && fail "no NEXT: line was declared -- must not manufacture a chain ($LOG)"

# empty milestone, description absent entirely (GitHub allows null) -> same terminal path, must not crash
NULL_DESC='[{"title":"Week 1","open_issues":0,"description":null}]'
read -r LOG LEDGER <<<"$(tick "$NULL_DESC")"
has "$LOG" 'MILESTONE-HELD' || fail "null description: expected plain MILESTONE-HELD, not a crash ($LOG)"
has "$LOG" 'MILESTONE-CHAIN-HELD' && fail "null description: must not manufacture a chain ($LOG)"

# an open milestone with an open issue -> unaffected by any of this, regression check
LIVE='[{"title":"Week 1","open_issues":2,"description":"NEXT: Week 2"}]'
read -r LOG LEDGER <<<"$(tick "$LIVE")"
has "$LOG" ' DISPATCH ' || fail "1 actionable milestone: expected a DISPATCH regardless of any NEXT: line ($LOG)"
has "$LOG" 'MILESTONE-HELD' && fail "1 actionable milestone: must not hold ($LOG)"
has "$LOG" 'MILESTONE-CHAIN-HELD' && fail "1 actionable milestone: a NEXT: line on a non-empty milestone is not a hold reason ($LOG)"

[ "$FAILED" -eq 0 ] && echo "PASS: milestone-chain-witness"
exit "$FAILED"
