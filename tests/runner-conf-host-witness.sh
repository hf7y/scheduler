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

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

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
# RUNNER_CRON RETIRED 2026-08-22 (hf7y/scheduler#81): this used to assert the
# literal */30 cadence dexter's pre-run-3 crontab ran. That premise expired
# on purpose -- the field is gone from every committed _runner*.conf now,
# rate lives in schedule/ROSTER instead -- so the assertion worth keeping is
# that dexter's conf really did drop it, not a specific value it can no
# longer state. tests/sync-crontab-runner-cron-retired-witness.sh covers the
# carry-forward mechanism that makes the retirement itself safe.
[ -z "$RUNNER_CRON" ] && ok "dexter's committed conf no longer sets RUNNER_CRON (retired to schedule/ROSTER)" || bad "dexter still resolves a RUNNER_CRON of '$RUNNER_CRON' -- was it supposed to be retired?"
case "$RUNNER_ENV" in *"PACED_MAX_PER_TICK=1"*) ok "dexter per-tick cap is 1" ;; *) bad "dexter per-tick cap is '$RUNNER_ENV'" ;; esac
case "$RUNNER_ENV" in *"USAGE_CEILING"*) bad "USAGE_CEILING baked onto dexter's cron line -- belongs in _usage.dexter.conf" ;; *) ok "no USAGE_CEILING on the cron line" ;; esac
[ -z "$SWEEP_TICK_CRON" ] && ok "dexter has no sweep tick (matches its actual crontab)" || bad "dexter would get a sweep tick it never ran"

echo "case 6 -- mandark OPTS OUT of BOTH ticks, each by its OWN host conf"
# HISTORY, because this assertion has now been wrong three times and every
# time it was the TEST that was stale, not the tree:
#   originally  it asserted mandark ran */5, which is what _runner.conf shipped
#               when this witness was written.
#   2026-08-02  the shipped cadence became `0 */6` (THE FLOOR's pacing
#               decision) and this line went red without anything being
#               broken. It stayed red.
#   2026-08-03  self-dev moved to `monkey` and mandark's runner was retired
#               deliberately, via _runner.mandark.conf blanking RUNNER_CRON --
#               Zach: "delete it via dog fooding if possible". The red then
#               changed from '0 */6 * * *' to '', i.e. it began failing ABOUT
#               the intended change. The line was rewritten to assert the
#               opt-out, and a SECOND assertion was added alongside it: that
#               the opt-out was runner-ONLY, mandark still keeping its */15
#               sweep tick.
#   2026-08-05  and two days later schedule/_sweep.mandark.conf landed (commit
#               421cca6, Zach-directed: "retire the scheduler sweep cron line
#               so the clone can go"), blanking SWEEP_TICK_CRON at the sweep
#               tier's OWN file. "mandark keeps its sweep tick" became false by
#               decision. The suite has been red on main ever since, which is
#               hf7y/scheduler#58.
#
# WHICH OF #58's TWO POSSIBILITIES THIS WAS -- the premise expired; the code
# did not regress. Told apart by a COUNTERFACTUAL rather than by reading the
# confs: hold the real _runner.conf + _runner.mandark.conf + _sweep.conf and
# withhold ONLY _sweep.mandark.conf, and mandark's sweep tick comes straight
# back at the shared cadence. The runner opt-out reaches nothing outside its
# own tier -- sync-crontab.sh re-initialises the SWEEP_TICK_* trio and captures
# its own shared-value baseline after the runner block has already finished.
# That counterfactual is asserted below rather than described, and case 10
# asserts the same property host-independently against the real script.
#
# So this case now asserts what is still true and still worth protecting: both
# ticks are off on mandark, and EACH IS ATTRIBUTABLE TO ITS OWN CONF. The
# attribution is the falsifiable part and the reason this is not a tautology --
# "SWEEP_TICK_CRON is blank" alone would merely restate the file. It fails if
# _runner.mandark.conf is dropped or misspelled (mandark silently dispatches
# again against a quota monkey is now spending), it fails if
# _sweep.mandark.conf is dropped (the sweep tick returns unannounced), and it
# fails if the sweep stays off with that file withheld -- which is exactly the
# tier leak #58's first branch describes.
resolve "$ROOT/schedule" mandark
[ -z "$RUNNER_CRON" ] && ok "mandark opts out of the runner tick (RUNNER_CRON blank)" \
  || bad "mandark would dispatch again -- RUNNER_CRON resolved to '$RUNNER_CRON'; is _runner.mandark.conf still there?"
[ -z "$SWEEP_TICK_CRON" ] && ok "mandark opts out of the sweep tick too (retired 2026-08-05)" \
  || bad "mandark's sweep tick is back -- SWEEP_TICK_CRON resolved to '$SWEEP_TICK_CRON'; is _sweep.mandark.conf still there?"

# ATTRIBUTION. Same real confs, same host, that ONE file withheld. Symlinks, so
# this reads whatever is committed today rather than a copy that goes stale.
ATTR="$TMP/attr"; mkdir -p "$ATTR"
for f in _runner.conf _runner.mandark.conf _sweep.conf; do ln -sf "$ROOT/schedule/$f" "$ATTR/$f"; done
# The shared cadence is read from _sweep.conf itself, not hardcoded here: a
# literal '*/15' is precisely the assertion that rotted twice above. Requiring
# it non-empty first keeps the comparison from passing vacuously if _sweep.conf
# ever stops arming a sweep at all.
resolve "$ATTR" nosuchhost; SHARED_SWEEP="$SWEEP_TICK_CRON"
resolve "$ATTR" mandark
[ -z "$RUNNER_CRON" ] && ok "withholding _sweep.mandark.conf leaves the RUNNER opt-out standing" \
  || bad "the runner opt-out vanished when a SWEEP file was withheld -- the tiers are coupled"
if [ -z "$SHARED_SWEEP" ]; then
  bad "_sweep.conf arms no sweep tick at all, so this case can prove nothing about mandark's"
elif [ "$SWEEP_TICK_CRON" = "$SHARED_SWEEP" ]; then
  ok "and the sweep tick returns to _sweep.conf's shared '$SHARED_SWEEP' -- the opt-out is _sweep.mandark.conf's own, not a leak from the runner tier"
else
  bad "withholding _sweep.mandark.conf did NOT restore the shared sweep tick (got '$SWEEP_TICK_CRON', shared is '$SHARED_SWEEP') -- the runner opt-out is leaking into the sweep tier"
fi

echo "case 7 -- the real script agrees (not just this witness's local model)"
# SYNC_HOST is the script's own override hook; preview mode writes nothing.
# RUNNER_CRON is retired, so the real script's runner-tier output for
# LOCAL_ACCOUNT now depends on whatever tick is already installed there
# (the carry-forward mechanism -- see
# tests/sync-crontab-runner-cron-retired-witness.sh for that in full), not
# on anything SYNC_HOST=dexter can pin. A stubbed, empty crontab keeps THIS
# case hermetic: with nothing to carry forward, the runner tier should emit
# nothing and no ERROR, so what's left to check here is dexter's own
# tiers -- no stale */30 literal, no sweep tick, no mandark cap.
STUB7="$TMP/stub7"; mkdir -p "$STUB7"
cat > "$STUB7/crontab" <<'EOF'
#!/bin/sh
[ "$1" = "-l" ] && { echo "no crontab for fake account" >&2; exit 1; }
exit 9
EOF
chmod +x "$STUB7/crontab"
got="$(PATH="$STUB7:$PATH" SYNC_HOST=dexter timeout 60 "$SYNC" 2>/dev/null | grep -E "usage-paced-runner|scheduler sweep" || true)"
err="$(PATH="$STUB7:$PATH" SYNC_HOST=dexter timeout 60 "$SYNC" 2>&1 >/dev/null)"
case "$err" in
  *"ERROR [runner]"*) bad "dexter's retired RUNNER_CRON is refused as an ERROR: $err" ;;
  *)                  ok "dexter's retired RUNNER_CRON produces no ERROR" ;;
esac
case "$got" in
  *"*/30 * * * *"*) bad "script preview for dexter still emits the retired */30 cadence -- did RUNNER_CRON come back?" ;;
  *)                ok "script preview for dexter does not resurrect the retired */30 cadence" ;;
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
STUB8="$TMP/stub8"; mkdir -p "$STUB8"
cat > "$STUB8/sudo" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -n) shift ;;
    -u) shift; shift ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec "$@"
STUB
chmod +x "$STUB8/sudo"
err="$(PATH="$STUB8:$PATH" SYNC_HOST=dexter timeout 60 "$SYNC" 2>&1 >/dev/null)"; rc=$?
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
# read_crontab_for(), for this account, shells out to a bare `crontab -l` --
# there is no synthetic-account hook the way there is for schedule/. Without
# a stub, sync-crontab.sh merges THIS ACCOUNT'S REAL crontab into the preview
# it emits for every synthetic host below, and on a live self-dev account
# that crontab already has a line tagged "...:RUNNER" (its own dispatch tick)
# -- which then satisfies any later "*:RUNNER*" substring check regardless of
# what the fake host actually resolved. A fake `crontab` ahead on PATH keeps
# the preview scoped to what these tests actually configured.
cat > "$FAKE/bin/crontab" <<'EOF'
#!/usr/bin/env bash
echo "no crontab for fake account" >&2
exit 1
EOF
chmod +x "$FAKE/bin/crontab"
# One project conf is required or the script exits 0 at "no schedule/*.conf
# entries yet" before it ever reaches the tick blocks. CRON_HOST pins it to a
# host that is never used below, so it is skipped and contributes no lines and
# no errors of its own -- the tick tiers are the only thing under test here.
printf 'CRON_HOST="nosuchhost"\n' > "$FAKE/schedule/dummy.conf"
run_fake() { PATH="$FAKE/bin:$PATH" SYNC_HOST="$1" timeout 60 bash "$FAKE/bin/sync-crontab.sh" 2>&1 >/dev/null; }

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

echo "case 10 -- an opt-out in ONE tier leaves the OTHER tier armed"
# ADDED 2026-08-11 with hf7y/scheduler#58. This is the durable half of what
# case 6 used to assert. Case 6 protected "the runner opt-out is runner-only"
# by pointing at mandark, a real host -- so the assertion lived or died on a
# POLICY DECISION about one machine, and on 2026-08-05 that decision changed
# and took the assertion with it. The property itself never changed and is
# worth keeping: it is about the resolution code, not about any host.
#
# So it is re-asserted here on synthetic hosts nobody administers, where no
# future retirement can expire it, and against the REAL script rather than
# this file's local resolve() -- cases 8-9's whole lesson being that the local
# model agreed with the script while the script was refusing dexter's opt-out.
#
# WHY THE EXISTING CASES DID NOT COVER THIS: 9d exercises a runner-tier
# opt-out, but by then _sweep.charlie.conf has been blanking the sweep tier
# since 9c, so a leak from runner into sweep would be invisible -- the sweep
# tick is already gone for its own reasons. `delta` below has exactly one host
# file at a time, which is the only arrangement that can see a leak.
#
# The FAKE checkout, its shared _runner.conf and _sweep.conf, and run_fake are
# case 9's; `delta` has no host file there, so it starts with both ticks armed.
run_fake_out() { PATH="$FAKE/bin:$PATH" SYNC_HOST="$1" timeout 60 bash "$FAKE/bin/sync-crontab.sh" 2>/dev/null; }

out="$(run_fake_out delta)"
case "$out" in *":RUNNER"*) ok "10 baseline: delta starts with the runner tick armed" ;;
               *)           bad "10 baseline: delta has no runner tick to lose; got: ${out:-<nothing>}" ;; esac
case "$out" in *":SWEEP"*)  ok "10 baseline: delta starts with the sweep tick armed" ;;
               *)           bad "10 baseline: delta has no sweep tick to lose; got: ${out:-<nothing>}" ;; esac

# 10a: runner opts out, NO sweep host file -> the sweep tick must SURVIVE.
printf 'RUNNER_CRON=""\n' > "$FAKE/schedule/_runner.delta.conf"
out="$(run_fake_out delta)"; err="$(run_fake delta)"
case "$err" in *"note [runner]"*"opts OUT"*) ok "10a: the runner opt-out is taken" ;;
               *)                            bad "10a: runner opt-out not announced: ${err:-<nothing>}" ;; esac
case "$out" in *":RUNNER"*) bad "10a: runner tick emitted despite the opt-out" ;;
               *)           ok "10a: the runner tick is gone" ;; esac
case "$out" in *":SWEEP"*)  ok "10a: and the SWEEP tick survives it -- the tiers are independent" ;;
               *)           bad "10a: opting out of the RUNNER tick also removed the SWEEP tick -- the opt-out is leaking tiers" ;; esac
case "$err" in *"ERROR [sweep]"*) bad "10a: the sweep tier errored on a conf that never changed" ;;
               *)                 ok "10a: and the sweep tier reports no error of its own" ;; esac

# 10b: the mirror, so neither tier can quietly become the one that leaks.
rm -f "$FAKE/schedule/_runner.delta.conf"
printf 'SWEEP_TICK_CRON=""\n' > "$FAKE/schedule/_sweep.delta.conf"
out="$(run_fake_out delta)"; err="$(run_fake delta)"
case "$err" in *"note [sweep]"*"opts OUT"*) ok "10b: the sweep opt-out is taken" ;;
               *)                           bad "10b: sweep opt-out not announced: ${err:-<nothing>}" ;; esac
case "$out" in *":SWEEP"*)  bad "10b: sweep tick emitted despite the opt-out" ;;
               *)           ok "10b: the sweep tick is gone" ;; esac
case "$out" in *":RUNNER"*) ok "10b: and the RUNNER tick survives it -- independent in both directions" ;;
               *)           bad "10b: opting out of the SWEEP tick also removed the RUNNER tick -- the opt-out is leaking tiers" ;; esac
case "$err" in *"ERROR [runner]"*) bad "10b: the runner tier errored on a conf that never changed" ;;
               *)                  ok "10b: and the runner tier reports no error of its own" ;; esac

echo
echo "runner-conf-host-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
