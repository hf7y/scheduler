#!/usr/bin/env bash
# paced-dry-run-witness.sh -- PACED_DRY_RUN, the rehearsal flag for the
# host-mode cutover (hf7y/scheduler#358).
#
# THE RISK THIS GUARDS AGAINST. The whole point of a dry run is "exercise
# every part of the plane that can be wrong with zero blast radius". A dry
# run that still execs the participant, or still writes a ledger row, is not
# a rehearsal -- it is the real thing with a reassuring log line bolted on,
# and the diff it is meant to produce (WOULD-DISPATCH vs what actually ran)
# would compare a real dispatch against itself.
#
# Drives the REAL runner (not a reimplementation), the same technique
# tests/verdict-witness.sh uses: a fake participant that proves whether it
# ran by writing a sentinel file, under a fake HOME.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -x "$RUNNER" ] || { echo "runner not executable: $RUNNER"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# $1 = PACED_DRY_RUN value to run with. Returns the run log on stdout.
run_tick() {
  local dry="$1"
  mkdir -p "$TMP/.local/share"

  # The fake participant: proves it ran by writing a sentinel, nothing else.
  cat > "$TMP/agent.sh" <<AGENT
#!/usr/bin/env bash
echo ran >> "$TMP/EXECUTED"
exit 0
AGENT
  chmod +x "$TMP/agent.sh"
  echo "alpha|1|1|$TMP/agent.sh" > "$TMP/rot.conf"
  # ROSTER is the only arming surface (#364); PACED_HOST is pinned so the row matches.
  echo 'alpha | alpha@testhost | 20m | live' > "$TMP/ROSTER"

  HOME="$TMP" \
  PACED_CONF="$TMP/rot.conf" \
  PACED_HOST=testhost \
  SCHEDULER_ROSTER_FILE="$TMP/ROSTER" \
  PACED_FORCE=1 \
  PACED_MAX_PER_TICK=1 \
  PACED_DRY_RUN="$dry" \
  SCHEDULER_FREEZE_FILE="$TMP/no-such-freeze" \
    bash "$RUNNER" >/dev/null 2>&1
  cat "$TMP/.local/share/scheduler-paced-runner/run.log" 2>/dev/null
}

ledger_rows() {
  local f="$TMP/.local/share/scheduler-paced-runner/ledger.tsv"
  [ -f "$f" ] && wc -l < "$f" || echo 0
}

echo "case 1 -- PACED_DRY_RUN=1 suppresses the exec"
TMP="$(mktemp -d)"; log="$(run_tick 1)"
[ -f "$TMP/EXECUTED" ] && bad "the participant ran under PACED_DRY_RUN=1 -- rehearsal has real blast radius" \
  || ok "the participant was never exec'd"
grep -q 'WOULD-DISPATCH \[' <<<"$log" && ok "logged WOULD-DISPATCH" || { bad "no WOULD-DISPATCH line"; echo "$log" | tail -5; }
grep -q 'WOULD-DISPATCH \[.*alpha' <<<"$log" && ok "names the participant" || bad "WOULD-DISPATCH line does not name alpha: $log"
grep -qE ' DISPATCH \[' <<<"$log" && bad "a real DISPATCH line was logged alongside the dry run" || ok "no real DISPATCH line"
[ "$(ledger_rows)" -eq 0 ] && ok "no ledger row written" || bad "dry run wrote $(ledger_rows) ledger row(s) -- it must write none"
rm -rf "$TMP"

echo "case 2 -- PACED_DRY_RUN=0 (default) is unchanged: the exec still happens"
TMP="$(mktemp -d)"; log="$(run_tick 0)"
[ -f "$TMP/EXECUTED" ] && ok "the participant ran (default behaviour preserved)" \
  || { bad "the participant never ran with PACED_DRY_RUN=0 -- default behaviour changed"; echo "$log" | tail -5; }
grep -qE ' DISPATCH \[' <<<"$log" && ok "logged a real DISPATCH line" || bad "no DISPATCH line: $log"
grep -q 'WOULD-DISPATCH' <<<"$log" && bad "WOULD-DISPATCH logged when PACED_DRY_RUN=0" || ok "no WOULD-DISPATCH line"
[ "$(ledger_rows)" -eq 1 ] && ok "exactly one ledger row written" || bad "expected 1 ledger row, got $(ledger_rows)"
rm -rf "$TMP"

echo "case 3 -- unset PACED_DRY_RUN behaves the same as 0 (default-off)"
TMP="$(mktemp -d)"
unset PACED_DRY_RUN
mkdir -p "$TMP/.local/share"
cat > "$TMP/agent.sh" <<AGENT
#!/usr/bin/env bash
echo ran >> "$TMP/EXECUTED"
exit 0
AGENT
chmod +x "$TMP/agent.sh"
echo "alpha|1|1|$TMP/agent.sh" > "$TMP/rot.conf"
echo 'alpha | alpha@testhost | 20m | live' > "$TMP/ROSTER"
HOME="$TMP" PACED_CONF="$TMP/rot.conf" PACED_HOST=testhost \
  SCHEDULER_ROSTER_FILE="$TMP/ROSTER" PACED_FORCE=1 PACED_MAX_PER_TICK=1 \
  SCHEDULER_FREEZE_FILE="$TMP/no-such-freeze" \
  bash "$RUNNER" >/dev/null 2>&1
[ -f "$TMP/EXECUTED" ] && ok "unset PACED_DRY_RUN still dispatches for real" \
  || bad "unset PACED_DRY_RUN changed behaviour -- it must default to off"
rm -rf "$TMP"

printf '\npaced-dry-run-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
