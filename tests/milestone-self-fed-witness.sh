#!/usr/bin/env bash
# milestone-self-fed-witness.sh -- MILESTONE-SELF-FED fires when an
# actionable milestone holds only agent-filed issues, and never blocks
# dispatch (#575 option (b): count it, but surface it -- #291 says only the
# predicate itself may stop dispatch).
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

# tick <issues-body-json-array> -> path to that run's ledger.tsv
#
# The stub runs the REAL jq filter the runner passes on the FIXTURE, rather
# than returning a hand-picked stand-in -- otherwise this witness would test
# the fixture, not milestone_self_fed()'s own query.
tick() {
  local issues_json="$1"
  local h="$T/h$$-$RANDOM"; mkdir -p "$h/.local/share/scheduler-paced-runner" "$h/bin"
  printf '%s' "$issues_json" > "$h/issues-fixture.json"

  cat > "$h/bin/gh" <<EOF
#!/usr/bin/env bash
argv=("\$@")
case "\$*" in
  *milestones*) echo 1 ;;
  *issues*state=open*)
    filter=""
    for i in "\${!argv[@]}"; do
      [ "\${argv[\$i]}" = "--jq" ] && filter="\${argv[\$((i+1))]}"
    done
    jq -r "\$filter" "$h/issues-fixture.json"
    ;;
  *) echo "milestone-self-fed-witness: unexpected gh call: \$*" >&2; exit 64 ;;
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

  echo "$h/.local/share/scheduler-paced-runner/ledger.tsv"
}

has() { grep -q "$2" "$1" 2>/dev/null; }

# 1. Every actionable issue is agent-filed (account != zach) -> SELF-FED,
#    and dispatch still proceeds (a real ledger row for the run itself).
AGENT_ONLY='[{"number":1,"milestone":{"state":"open","open_issues":1},"body":"do the thing\n\n<!-- agent: ecosim@monkey 2026-09-06T00:00:00Z build x -->"}]'
LEDGER="$(tick "$AGENT_ONLY")"
has "$LEDGER" 'MILESTONE-SELF-FED' || fail "all-agent-filed: expected a MILESTONE-SELF-FED row ($LEDGER)"

# 2. One actionable issue carries zach's own stamp -> not self-fed, no notice.
ZACH_ONE='[{"number":2,"milestone":{"state":"open","open_issues":2},"body":"human call\n\n<!-- agent: zach@mandark 2026-09-06T00:00:00Z build x -->"},{"number":3,"milestone":{"state":"open","open_issues":2},"body":"followup\n\n<!-- agent: ecosim@monkey 2026-09-06T00:00:00Z build x -->"}]'
LEDGER="$(tick "$ZACH_ONE")"
has "$LEDGER" 'MILESTONE-SELF-FED' && fail "a zach-stamped issue is present: MILESTONE-SELF-FED must not fire ($LEDGER)"

# 3. One actionable issue is unstamped (raw human edit) -> not self-fed.
UNSTAMPED='[{"number":4,"milestone":{"state":"open","open_issues":1},"body":"typed by hand, no footer at all"}]'
LEDGER="$(tick "$UNSTAMPED")"
has "$LEDGER" 'MILESTONE-SELF-FED' && fail "an unstamped issue is present: MILESTONE-SELF-FED must not fire ($LEDGER)"

# 4. SELF-FED never blocks: a real dispatch outcome still lands in the ledger
#    on the same tick it fires.
LEDGER="$(tick "$AGENT_ONLY")"
[ "$(grep -c . "$LEDGER" 2>/dev/null || echo 0)" -ge 2 ] \
  || fail "SELF-FED should not consume the only ledger row for the tick -- expected the self-fed notice plus a dispatch outcome ($LEDGER)"

[ "$FAILED" -eq 0 ] && echo "PASS: milestone-self-fed-witness"
exit "$FAILED"
