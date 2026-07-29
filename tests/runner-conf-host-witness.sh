#!/usr/bin/env bash
# Witness for host-scoped TICK meta -- _runner.<host>.conf / _sweep.<host>.conf.
#
# THE DEFECT THIS RETIRES, found live on 2026-07-29: the ROTATION had been
# per-host since 2026-07-24 (schedule/_paced.<host>.conf) but the TICK that
# drives it was read from one shared file. `sync-crontab.sh --apply` on dexter
# would therefore have installed mandark's cadence -- */5 with
# PACED_MAX_PER_TICK=16 -- over the */30 with MAX_PER_TICK=1 that dexter was
# deliberately running, a 6x rate increase on a host sharing ONE account budget.
# It would also have armed a */15 `scheduler sweep` tick dexter has never run.
#
# That gap is why dexter's crontab was hand-written and never regenerated for
# five days: a config surface a host cannot express is a surface that host
# routes around.
#
# Asserts, and the last two are the ones that rot:
#   1. host file overrides the shared one
#   2. it overrides PER FIELD -- unstated fields keep the shared value
#   3. a host file can BLANK a field to opt out of a tick (SWEEP_TICK_CRON="")
#   4. with no host file, behaviour is EXACTLY the old shared-only behaviour
#      (so adding this mechanism cannot have changed any other host)
#   5. the real committed dexter files reproduce dexter's actual pre-run-3
#      crontab, rather than quietly changing it
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/bin/sync-crontab.sh"
[ -x "$SYNC" ] || { echo "sync-crontab.sh not executable: $SYNC"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Extract the resolution behaviour by sourcing the same shared-then-host order
# sync-crontab.sh uses. Kept as a small local model AND cross-checked against
# the real script's output below, so this witness cannot pass while the script
# it describes has diverged.
resolve() {
  local dir="$1" host="$2"
  RUNNER_JOB=""; RUNNER_CMD=""; RUNNER_CRON=""; RUNNER_ENV=""; PACED_SUPPRESS_BATCH=0
  SWEEP_TICK_CRON=""
  [ -f "$dir/_runner.conf" ]        && . "$dir/_runner.conf"
  [ -f "$dir/_runner.$host.conf" ]  && . "$dir/_runner.$host.conf"
  [ -f "$dir/_sweep.conf" ]         && . "$dir/_sweep.conf"
  [ -f "$dir/_sweep.$host.conf" ]   && . "$dir/_sweep.$host.conf"
  return 0
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/s"
cat > "$TMP/s/_runner.conf" <<'EOF'
RUNNER_JOB="shared-job"
RUNNER_CMD="/bin/shared-cmd"
RUNNER_CRON="*/5 * * * *"
RUNNER_ENV="PACED_MAX_PER_TICK=16"
PACED_SUPPRESS_BATCH=1
EOF
cat > "$TMP/s/_sweep.conf" <<'EOF'
SWEEP_TICK_CRON="*/15 * * * *"
EOF

echo "case 1+2 -- host file overrides, PER FIELD"
cat > "$TMP/s/_runner.alpha.conf" <<'EOF'
RUNNER_CRON="*/30 * * * *"
RUNNER_ENV="PACED_MAX_PER_TICK=1"
EOF
resolve "$TMP/s" alpha
[ "$RUNNER_CRON" = "*/30 * * * *" ] && ok "host RUNNER_CRON won" || bad "host RUNNER_CRON lost (got '$RUNNER_CRON')"
[ "$RUNNER_ENV" = "PACED_MAX_PER_TICK=1" ] && ok "host RUNNER_ENV won" || bad "host RUNNER_ENV lost (got '$RUNNER_ENV')"
[ "$RUNNER_JOB" = "shared-job" ] && ok "unstated RUNNER_JOB kept shared value" || bad "unstated field was clobbered (got '$RUNNER_JOB')"
[ "$RUNNER_CMD" = "/bin/shared-cmd" ] && ok "unstated RUNNER_CMD kept shared value" || bad "unstated RUNNER_CMD clobbered"
[ "$PACED_SUPPRESS_BATCH" = "1" ] && ok "unstated PACED_SUPPRESS_BATCH kept shared value" || bad "suppression flag clobbered -- would re-arm every fixed nightly"

echo "case 3 -- a host file can BLANK a field to opt out of a tick"
printf 'SWEEP_TICK_CRON=""\n' > "$TMP/s/_sweep.alpha.conf"
resolve "$TMP/s" alpha
[ -z "$SWEEP_TICK_CRON" ] && ok "sweep tick opted out" || bad "blanking did not suppress the tick (got '$SWEEP_TICK_CRON')"

echo "case 4 -- a host with NO host file is unchanged (shared-only behaviour)"
resolve "$TMP/s" bravo
[ "$RUNNER_CRON" = "*/5 * * * *" ] && ok "shared cadence intact for other hosts" || bad "other host's cadence changed (got '$RUNNER_CRON')"
[ "$SWEEP_TICK_CRON" = "*/15 * * * *" ] && ok "shared sweep tick intact for other hosts" || bad "other host's sweep tick changed"

echo "case 5 -- the REAL committed dexter files reproduce dexter's actual crontab"
resolve "$ROOT/schedule" dexter
[ "$RUNNER_CRON" = "*/30 * * * *" ] && ok "dexter cadence is */30 (matches its pre-run-3 crontab)" || bad "dexter cadence is '$RUNNER_CRON', not the */30 it actually ran"
case "$RUNNER_ENV" in *"PACED_MAX_PER_TICK=1"*) ok "dexter per-tick cap is 1" ;; *) bad "dexter per-tick cap is '$RUNNER_ENV'" ;; esac
case "$RUNNER_ENV" in *"USAGE_CEILING"*) bad "USAGE_CEILING baked onto dexter's cron line -- belongs in _usage.dexter.conf" ;; *) ok "no USAGE_CEILING on the cron line" ;; esac
[ -z "$SWEEP_TICK_CRON" ] && ok "dexter has no sweep tick (matches its actual crontab)" || bad "dexter would get a sweep tick it never ran"

echo "case 6 -- mandark is genuinely unaffected by all of the above"
resolve "$ROOT/schedule" mandark
[ "$RUNNER_CRON" = "*/5 * * * *" ] && ok "mandark still */5" || bad "mandark cadence changed to '$RUNNER_CRON'"

echo "case 7 -- the real script agrees (not just this witness's local model)"
# SYNC_HOST is the script's own override hook; preview mode writes nothing.
got="$(SYNC_HOST=dexter timeout 60 "$SYNC" 2>/dev/null | grep -E "usage-paced-runner|scheduler sweep" || true)"
case "$got" in
  *"*/30 * * * *"*) ok "script preview for dexter emits the */30 tick" ;;
  *)                bad "script preview for dexter did not emit */30; got: ${got:-<nothing>}" ;;
esac
case "$got" in
  *"scheduler sweep"*) bad "script preview for dexter still emits a sweep tick" ;;
  *)                   ok "script preview for dexter emits no sweep tick" ;;
esac
case "$got" in
  *"PACED_MAX_PER_TICK=16"*) bad "script preview for dexter carries mandark's MAX_PER_TICK=16" ;;
  *)                         ok "script preview for dexter does not carry mandark's cap" ;;
esac

echo
echo "runner-conf-host-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
