#!/usr/bin/env bash
# Witness for the pull gate's escalation -- bin/usage-paced-runner.sh.
#
# THE BUG THIS EXISTS TO PREVENT is a guard that is safe and silent. Every
# non-advancing branch of the pull gate logged ONE line, at the same volume,
# every tick, forever. A network blip and a five-day deploy freeze produced
# identical output, so no observation distinguished them and nothing ever
# raised its voice: vim-arcade's clone sat behind origin/main from 2026-08-06
# to at least 2026-08-11 with ~1400 identical `PULL skip` lines while PR #59 --
# merged specifically to fix that account -- could not reach it (#61, #75).
#
# Four things must hold, and the last two are the ones that rot:
#   1. a repeat is COUNTED, and the count is in the log line
#   2. PACED_PULL_ESCALATE_AFTER ticks of the same cause is a FINDING: it logs
#      PULL FROZEN and files ONCE through realisateur's inbox -- once, not
#      every tick, or the channel becomes the thing nobody reads
#   3. a different cause RESTARTS the count rather than inheriting an older
#      escalation
#   4. RECOVERY is announced and the episode is closed. "It started working
#      again" is exactly as unobservable as the freeze was.
#
# A guard never seen firing is indistinguishable from one that cannot fire, so
# every case below drives the REAL block lifted out of the dispatcher, against
# a real clone of a real origin.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$RUNNER" ] || { echo "runner not found: $RUNNER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# --- lift the real block -----------------------------------------------------
BLOCK="$TMP/pull-gate.sh"
awk '/^# >>> pull gate/,/^# <<< pull gate/' "$RUNNER" > "$BLOCK"
grep -q 'PULL FROZEN' "$BLOCK" \
  || { echo "FAIL: the extracted gate has no escalation path -- it can still go silent forever"; exit 1; }
grep -q 'PULL RECOVERED' "$BLOCK" \
  || { echo "FAIL: the extracted gate never announces recovery"; exit 1; }
grep -q 'PACED_PULL_ESCALATE_AFTER' "$BLOCK" \
  || { echo "FAIL: the escalation threshold is not the documented knob"; exit 1; }

# A stub `scheduler` on PATH, so "filed to realisateur's inbox" is observable
# instead of assumed. Every call appends a line; the count IS the assertion.
mkdir -p "$TMP/bin"
FILED="$TMP/filed.log"
{ printf '#!/usr/bin/env bash\n'
  printf 'printf "%%s\\n" "$*" >> %s\n' "$FILED"; } > "$TMP/bin/scheduler"
chmod +x "$TMP/bin/scheduler"
export PATH="$TMP/bin:$PATH"

GATE="$TMP/bin/gate.sh"
{ printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'STATE_DIR="$1"; REPO_ROOT="$2"\n'
  printf 'JOB_NAME="scheduler-paced-runner"\nPACED_HOST="witnesshost"\n'
  printf 'LOG="$STATE_DIR/run.log"\nmkdir -p "$STATE_DIR"\n'
  printf 'log() { echo "$(date -Is) $*" >> "$LOG"; }\n'
  cat "$BLOCK"; } > "$GATE"
chmod +x "$GATE"

# --- fixture: a real origin the clone is genuinely behind --------------------
git_q() { git -c init.defaultBranch=main -c user.email=w@w -c user.name=w "$@"; }
ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; CLONE="$TMP/clone"
git_q init --bare -q "$ORIGIN"
git_q init -q "$SEED"
echo v1 > "$SEED/code.sh"
git_q -C "$SEED" add -A; git_q -C "$SEED" commit -qm seed
git_q -C "$SEED" remote add origin "$ORIGIN"; git_q -C "$SEED" push -q origin main
git_q clone -q "$ORIGIN" "$CLONE"
echo v2 > "$SEED/code.sh"
git_q -C "$SEED" commit -qam "the fix that must reach this host"
git_q -C "$SEED" push -q origin main
UPSTREAM="$(git -C "$SEED" rev-parse HEAD)"

STATE="$TMP/state"
PSTATE="$STATE/pull-block.state"
export PACED_PULL_ESCALATE_AFTER=3

tick() { "$GATE" "$STATE" "$CLONE" >/dev/null 2>&1; }
lastlog() { tail -n 6 "$STATE/run.log" 2>/dev/null; }
count_in_log() { grep -c "$1" "$STATE/run.log" 2>/dev/null || true; }

# --- 1/2. a dirty tracked file, tick after tick ------------------------------
echo "== 1. the same cause, repeated, is counted"
echo "a human edit nothing else has a copy of" >> "$CLONE/code.sh"
tick
if lastlog | grep -q 'consecutive blocked ticks: 1'; then ok "tick 1 counted as 1"
else bad "tick 1 not counted: $(lastlog)"; fi
if lastlog | grep -q 'PULL FROZEN'; then bad "escalated on the FIRST tick -- a blip is not a finding"
else ok "tick 1 did not escalate"; fi

tick
if lastlog | grep -q 'consecutive blocked ticks: 2'; then ok "tick 2 counted as 2"
else bad "tick 2 not counted: $(lastlog)"; fi
if lastlog | grep -q 'PULL FROZEN'; then bad "escalated below the threshold"
else ok "tick 2 still below the threshold of 3"; fi

echo "== 2. crossing the threshold is a finding, filed once"
tick
if lastlog | grep -q 'consecutive blocked ticks: 3'; then ok "tick 3 counted as 3"
else bad "tick 3 not counted: $(lastlog)"; fi
if lastlog | grep -q 'PULL FROZEN'; then ok "tick 3 logged PULL FROZEN"
else bad "threshold reached and nothing escalated: $(lastlog)"; fi
if lastlog | grep -q "FILED the pull freeze"; then ok "logged that it filed"
else bad "no FILED line: $(lastlog)"; fi
if [ "$(wc -l < "$FILED" 2>/dev/null || echo 0)" -eq 1 ]; then ok "filed to realisateur exactly once"
else bad "expected 1 filing, got $(wc -l < "$FILED" 2>/dev/null || echo 0)"; fi
if grep -q 'realisateur' "$FILED" && grep -q 'PULL FROZEN' "$FILED"; then
  ok "the filing names the inbox and the condition"
else bad "filing does not carry the finding: $(cat "$FILED")"; fi

tick; tick
if [ "$(count_in_log 'PULL FROZEN')" -ge 3 ]; then ok "keeps saying FROZEN every tick (the log stays loud)"
else bad "went quiet again after escalating"; fi
if [ "$(wc -l < "$FILED")" -eq 1 ]; then ok "still exactly one filing -- the inbox is not spammed"
else bad "re-filed on every tick: $(wc -l < "$FILED") filings"; fi
if [ "$(git -C "$CLONE" rev-parse HEAD)" != "$UPSTREAM" ]; then
  ok "the clone is still pinned -- escalation reports, it does not resolve the tree"
else bad "the gate resolved a dirty tree on its own; that diff can be the only copy of a record"; fi
if git -C "$CLONE" status --porcelain --untracked-files=no | grep -q 'code.sh'; then
  ok "the human's uncommitted change was left exactly as found"
else bad "the human's uncommitted change was destroyed"; fi

# --- 3. a different cause restarts the count ---------------------------------
echo "== 3. a different cause does not inherit an older escalation"
printf '9 some-other-cause 1\n' > "$PSTATE"
tick
if lastlog | grep -q 'consecutive blocked ticks: 1'; then ok "count restarted at 1 on a new cause"
else bad "a new cause inherited the old count: $(lastlog)"; fi

# --- 4. recovery closes the episode ------------------------------------------
echo "== 4. recovery is announced, once, and the episode is closed"
git -C "$CLONE" checkout -q -- code.sh
tick
if lastlog | grep -q 'PULL RECOVERED'; then ok "logged PULL RECOVERED"
else bad "recovered silently: $(lastlog)"; fi
if [ "$(git -C "$CLONE" rev-parse HEAD)" = "$UPSTREAM" ]; then ok "and actually pulled to ${UPSTREAM:0:7}"
else bad "did not pull after the tree went clean"; fi
if [ ! -f "$PSTATE" ]; then ok "episode state cleared"
else bad "state file survived recovery: $(cat "$PSTATE")"; fi
before="$(count_in_log 'PULL RECOVERED')"
tick
if [ "$(count_in_log 'PULL RECOVERED')" -eq "$before" ]; then
  ok "a healthy tick stays silent (this runs every 5 minutes)"
else bad "logs RECOVERED on every healthy tick"; fi

echo
echo "pull-escalation-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
