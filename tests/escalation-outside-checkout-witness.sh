#!/usr/bin/env bash
# Witness for bin/usage-paced-runner.sh's escalation resolving its filing tool
# from OUTSIDE the checkout it reports on. The incident and the resolution
# order are recorded once, at file_to_realisateur in that file; this drives
# them: the outside copy must win even when the checkout has its own, a host
# with NO `scheduler` (the real deployed shape -- only `dose` is in the verb
# build) must still get the finding off the host, and the give-up escalation
# must share the one resolver rather than keep its own copy of the defect.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$RUNNER" ] || { echo "runner not found: $RUNNER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# --- lift the real block, same markers tests/pull-escalation-witness.sh uses --
BLOCK="$TMP/pull-gate.sh"
awk '/^# >>> pull gate/,/^# <<< pull gate/' "$RUNNER" > "$BLOCK"
grep -q 'file_to_realisateur()' "$BLOCK" \
  || { echo "FAIL: the extracted gate carries no file_to_realisateur -- either the resolver moved outside the pull-gate markers (where the give-up path can no longer share it) or it is gone"; exit 1; }

GATE="$TMP/gate.sh"
{ printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'STATE_DIR="$1"; REPO_ROOT="$2"\n'
  printf 'JOB_NAME="scheduler-paced-runner"\nPACED_HOST="witnesshost"\n'
  printf 'LOG="$STATE_DIR/run.log"\nmkdir -p "$STATE_DIR"\n'
  printf 'log() { echo "$(date -Is) $*" >> "$LOG"; }\n'
  cat "$BLOCK"; } > "$GATE"
chmod +x "$GATE"

# A `gh` that RECORDS, and must shadow the real authenticated one: unstubbed,
# every run of this suite would file real issues on hf7y/realisateur.
mkdir -p "$TMP/bin"
GHLOG="$TMP/gh.log"; : > "$GHLOG"
GHBODY="$TMP/gh-body.txt"; : > "$GHBODY"
{ printf '#!/usr/bin/env bash\n'
  printf 'printf "%%s\\n" "$*" >> %s\n' "$GHLOG"
  printf 'while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && cat "$2" >> %s; shift; done\n' "$GHBODY"
  printf 'exit 0\n'; } > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# The host-wide install: on PATH, outside every checkout -- that property, not
# the directory it sits in, is what is under test.
HOSTFILED="$TMP/host-filed.log"; : > "$HOSTFILED"
host_scheduler() {
  { printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %s\n' "$HOSTFILED"; } > "$TMP/bin/scheduler"
  chmod +x "$TMP/bin/scheduler"
}

git_q() { git -c init.defaultBranch=main -c user.email=w@w -c user.name=w "$@"; }
ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; CLONE="$TMP/clone"
git_q init --bare -q "$ORIGIN"
git_q init -q "$SEED"
echo v1 > "$SEED/code.sh"
git_q -C "$SEED" add -A; git_q -C "$SEED" commit -qm seed
git_q -C "$SEED" remote add origin "$ORIGIN"; git_q -C "$SEED" push -q origin main
git_q clone -q "$ORIGIN" "$CLONE"
echo v2 > "$SEED/code.sh"
git_q -C "$SEED" commit -qam "the fix that cannot reach this host"
git_q -C "$SEED" push -q origin main
echo "a human edit nothing else has a copy of" >> "$CLONE/code.sh"

export PACED_PULL_ESCALATE_AFTER=3
STATE_N=0   # a fresh state dir per case: an episode deliberately files once
escalate() {
  STATE_N=$((STATE_N + 1))
  STATE="$TMP/state$STATE_N"
  for _ in 1 2 3; do "$GATE" "$STATE" "$CLONE" >/dev/null 2>&1; done
  grep -q 'PULL FROZEN' "$STATE/run.log"
}

echo "== 1. no bin/scheduler in the frozen checkout -> the host-wide one still files"
host_scheduler
[ -e "$CLONE/bin/scheduler" ] && rm -f "$CLONE/bin/scheduler"
if escalate; then ok "escalated to PULL FROZEN"
else bad "never reached PULL FROZEN: $(tail -n 4 "$STATE/run.log")"; fi
if [ "$(wc -l < "$HOSTFILED")" -eq 1 ]; then ok "filed through the host-wide scheduler, exactly once"
else bad "expected 1 filing through the host-wide tool, got $(wc -l < "$HOSTFILED")"; fi
if grep -q 'PULL FROZEN' "$HOSTFILED" && grep -q 'realisateur' "$HOSTFILED"; then
  ok "the filing names the inbox and the condition"
else bad "filing does not carry the finding: $(cat "$HOSTFILED")"; fi
if grep -q "FILED the pull freeze to realisateur's inbox" "$STATE/run.log"; then
  ok "and the log says it filed"
else bad "no FILED line: $(tail -n 4 "$STATE/run.log")"; fi

# The whole fix: a checkout 261 commits behind can still carry an executable
# bin/scheduler, and preferring it is preferring the suspect.
echo "== 2. both resolvable -> the copy OUTSIDE the checkout is preferred"
host_scheduler
: > "$HOSTFILED"
CHECKOUTFILED="$TMP/checkout-filed.log"; : > "$CHECKOUTFILED"
mkdir -p "$CLONE/bin"
{ printf '#!/usr/bin/env bash\n'
  printf 'printf "%%s\\n" "$*" >> %s\n' "$CHECKOUTFILED"; } > "$CLONE/bin/scheduler"
chmod +x "$CLONE/bin/scheduler"
escalate >/dev/null
if [ "$(wc -l < "$HOSTFILED")" -eq 1 ]; then ok "the host-wide copy was called"
else bad "the host-wide copy was not called"; fi
if [ "$(wc -l < "$CHECKOUTFILED")" -eq 0 ]; then
  ok "the frozen checkout's own copy was NOT called -- the escalation no longer depends on what it reports on"
else bad "still resolved the checkout first: that is the double blind"; fi
rm -f "$CLONE/bin/scheduler"

# The case that fired on monkey. It must not end in the log.
echo "== 3. no scheduler at all -> the finding still leaves the host, via gh"
rm -f "$TMP/bin/scheduler"
: > "$GHLOG"; : > "$GHBODY"
if escalate; then ok "escalated to PULL FROZEN with no scheduler resolvable"
else bad "never reached PULL FROZEN: $(tail -n 4 "$STATE/run.log")"; fi
if [ "$(wc -l < "$GHLOG")" -eq 1 ]; then ok "called gh exactly once -- reported, not spammed"
else bad "expected 1 gh call, got $(wc -l < "$GHLOG"): $(cat "$GHLOG")"; fi
if grep -q 'issue create' "$GHLOG" && grep -q -- '--repo hf7y/realisateur' "$GHLOG"; then
  ok "filed an issue on hf7y/realisateur -- the same channel \`scheduler -i\` uses, reached without the checkout"
else bad "gh was called with the wrong shape: $(cat "$GHLOG")"; fi
if grep -q 'PULL FROZEN' "$GHBODY" && grep -q 'has not pulled for' "$GHBODY"; then
  ok "the issue BODY carries the finding, not just a title"
else bad "the body does not carry the finding: $(cat "$GHBODY")"; fi
if grep -q 'FILED the pull freeze to realisateur as a GitHub issue' "$STATE/run.log"; then
  ok "the log records WHICH channel carried it"
else bad "the log does not distinguish the gh fallback: $(tail -n 4 "$STATE/run.log")"; fi
if ! grep -q 'exists in this log only' "$STATE/run.log"; then
  ok "did not settle for a log-only report"
else bad "gave up into the log even though gh was reachable"; fi

# Reached only from inside the dispatch loop, so asserted against the source:
# the defect WAS a second private copy, which is what must not come back.
echo "== 4. the give-up escalation shares one resolver -- no private second copy"
if grep -q 'file_to_realisateur "\$name.s give-up"' "$RUNNER"; then
  ok "the GAVE-UP path files through the shared resolver"
else bad "the GAVE-UP path does not call file_to_realisateur -- it kept its own resolution"; fi
if [ "$(grep -c '_sched_bin' "$RUNNER")" -eq 0 ]; then
  ok "no checkout-first _sched_bin resolution survives anywhere in the runner"
else bad "a checkout-first resolver is still present: $(grep -n '_sched_bin' "$RUNNER")"; fi
if [ "$(grep -c 'command -v scheduler' "$RUNNER")" -eq 1 ]; then
  ok "exactly one place resolves \`scheduler\`"
else bad "$(grep -c 'command -v scheduler' "$RUNNER") places resolve \`scheduler\`; they will diverge"; fi

echo
echo "escalation-outside-checkout-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
