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
#      -- and, since 2026-07-29, that the REAL SCRIPT accepts that opt-out
#      cleanly instead of refusing it (cases 8-9; see case 8's own note for
#      why asserting the missing line was not enough)
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

echo "case 6 -- mandark OPTS OUT of the runner tick (self-dev has left it)"
# HISTORY, because this assertion has now been wrong twice and each time it
# was the TEST that was stale, not the tree:
#   originally  it asserted mandark ran */5, which is what _runner.conf shipped
#               when this witness was written.
#   2026-08-02  the shipped cadence became `0 */6` (THE FLOOR's pacing
#               decision) and this line went red without anything being
#               broken. It stayed red.
#   2026-08-03  self-dev moved to `monkey` and mandark's runner was retired
#               deliberately, via _runner.mandark.conf blanking RUNNER_CRON --
#               Zach: "delete it via dog fooding if possible". The red then
#               changed from '0 */6 * * *' to '', i.e. it began failing ABOUT
#               the intended change.
# A test asserting a cadence this host no longer has is not protecting
# anything; it is a red that misdescribes the tree. What is worth protecting
# is that the OPT-OUT resolves -- because if _runner.mandark.conf is ever
# dropped or misspelled, mandark silently starts dispatching again against a
# quota monkey is now spending.
resolve "$ROOT/schedule" mandark
[ -z "$RUNNER_CRON" ] && ok "mandark opts out of the runner tick (RUNNER_CRON blank)" \
  || bad "mandark would dispatch again -- RUNNER_CRON resolved to '$RUNNER_CRON'; is _runner.mandark.conf still there?"
[ -n "$SWEEP_TICK_CRON" ] && ok "mandark keeps its sweep tick (only agent dispatch left)" \
  || bad "mandark lost its sweep tick too -- the opt-out was meant to be runner-only"

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

echo "case 8 -- the opt-out is a NOTE, not an ERROR (the defect case 3 missed)"
# WHY THIS EXISTS, 2026-07-29. Case 3 above asserted opt-out against this
# file's LOCAL `resolve()` model, and case 7 asserted only that no sweep line
# appears in the script's stdout. Both passed while the real script was
# REFUSING dexter's opt-out: `_sweep.conf` sets JOB and CMD, the host file
# blanks only CRON, and the emit block's "all three or none" guard read that
# as an incomplete conf -- `ERROR [sweep]: ... sweep tick omitted`, ERRORS+1,
# `exit 1`. The tick was absent for the wrong reason, and step one of
# .scheduler/FOCUS.md's bootstrap bar (`sync-crontab.sh --apply` on dexter)
# reported failure while doing exactly the right thing.
#
# So: assert the MANNER, not just the outcome. An assertion that only checks
# a line is missing cannot tell a clean opt-out from a refusal.
err="$(SYNC_HOST=dexter timeout 60 "$SYNC" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "script preview for dexter exits 0" || bad "script preview for dexter exits $rc -- an opt-out is not an error"
case "$err" in
  *"ERROR [sweep]"*) bad "opt-out still reported as ERROR [sweep]" ;;
  *)                 ok "no ERROR [sweep] for an opted-out host" ;;
esac
case "$err" in
  *"note [sweep]"*"opts OUT"*) ok "opt-out is announced, not silently dropped" ;;
  *)                           bad "opt-out is silent -- nothing says why this host has no sweep tick" ;;
esac

echo "case 9 -- an INCOMPLETE shared conf still ERRORS (the fix must not fail open)"
# The whole risk of accepting an empty CRON is that "this host opted out" and
# "somebody forgot to set the cron" look identical. They are told apart by the
# SHARED value: only non-empty -> empty counts as an opt-out. These two cases
# pin that down, against the real script in a synthetic checkout.
#
# The checkout is symlinks into this repo's bin/ and lib/, with its own
# schedule/ -- sync-crontab.sh derives SCHED_DIR from `dirname $BASH_SOURCE`,
# which is the LINK's directory, so this runs the real script against fake
# config without copying it (a copy is the version that silently goes stale).
FAKE="$TMP/fake"
mkdir -p "$FAKE/bin" "$FAKE/schedule"
ln -s "$SYNC" "$FAKE/bin/sync-crontab.sh"
ln -s "$ROOT/lib" "$FAKE/lib"
# One project conf is required or the script exits 0 at "no schedule/*.conf
# entries yet" before it ever reaches the tick blocks. CRON_HOST pins it to a
# host that is never used below, so it is skipped and contributes no lines and
# no errors of its own -- the tick tiers are the only thing under test here.
printf 'CRON_HOST="nosuchhost"\n' > "$FAKE/schedule/dummy.conf"
run_fake() { SYNC_HOST="$1" timeout 60 bash "$FAKE/bin/sync-crontab.sh" 2>&1 >/dev/null; }

# 9a: JOB+CMD set, CRON never set anywhere, NO host file -> incomplete.
cat > "$FAKE/schedule/_sweep.conf" <<'EOF'
SWEEP_TICK_JOB="fake-sweep"
SWEEP_TICK_CMD="/bin/true"
EOF
out="$(run_fake charlie)"
case "$out" in
  *"ERROR [sweep]"*) ok "9a: shared conf missing CRON still errors" ;;
  *)                 bad "9a: incomplete shared conf accepted silently -- fail-open" ;;
esac

# 9b: same incomplete shared conf, but a host file that touches something
# ELSE. The host file's mere existence must not launder the missing CRON.
printf 'SWEEP_TICK_JOB="fake-sweep-charlie"\n' > "$FAKE/schedule/_sweep.charlie.conf"
out="$(run_fake charlie)"
case "$out" in
  *"ERROR [sweep]"*) ok "9b: a host file does not launder a missing shared CRON" ;;
  *)                 bad "9b: host file's existence suppressed the incomplete-conf error -- fail-open" ;;
esac

# 9c: shared conf ARMS the tick, host file blanks it -> the real opt-out.
cat > "$FAKE/schedule/_sweep.conf" <<'EOF'
SWEEP_TICK_JOB="fake-sweep"
SWEEP_TICK_CMD="/bin/true"
SWEEP_TICK_CRON="*/15 * * * *"
EOF
printf 'SWEEP_TICK_CRON=""\n' > "$FAKE/schedule/_sweep.charlie.conf"
out="$(run_fake charlie)"
case "$out" in
  *"ERROR [sweep]"*)           bad "9c: a genuine opt-out is still refused" ;;
  *"note [sweep]"*"opts OUT"*) ok "9c: armed-then-blanked is an opt-out" ;;
  *)                           bad "9c: opt-out neither errored nor announced: ${out:-<nothing>}" ;;
esac

# 9d: the same rule for the RUNNER tier, so the two ticks cannot drift into
# one accepting an opt-out the other refuses. No host does this today; that
# is precisely why it needs a test rather than a reader.
cat > "$FAKE/schedule/_runner.conf" <<'EOF'
RUNNER_JOB="fake-runner"
RUNNER_CMD="/bin/true"
RUNNER_CRON="*/5 * * * *"
EOF
printf 'RUNNER_CRON=""\n' > "$FAKE/schedule/_runner.charlie.conf"
out="$(run_fake charlie)"
case "$out" in
  *"ERROR [runner]"*)           bad "9d: runner tier refuses an opt-out the sweep tier accepts" ;;
  *"note [runner]"*"opts OUT"*) ok "9d: runner tier honours the same opt-out rule" ;;
  *)                            bad "9d: runner opt-out neither errored nor announced: ${out:-<nothing>}" ;;
esac

echo
echo "runner-conf-host-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
