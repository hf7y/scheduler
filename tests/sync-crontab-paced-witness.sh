#!/usr/bin/env bash
# Witness for "does bin/sync-crontab.sh install a fixed nightly cron line for
# a project the paced runner already dispatches?" -- i.e. DOUBLE DISPATCH,
# armed by the crontab writer itself.
#
# THE BUG THIS RETIRES (found 2026-07-29, reproduced before it was fixed):
# the suppression set was read from a hardcoded schedule/_paced.conf while
# bin/usage-paced-runner.sh -- and, since a7066ff, bin/scheduler -- resolve
# schedule/_paced.<host>.conf. So membership in a HOST-SCOPED rotation was
# invisible here. Commenting out mandark's `scheduler|1|3` line to make its
# self-dev dark (58d6495) dropped `scheduler` out of the suppression set, and
# the next `--apply` would have installed
#
#   0 1 * * * .../scheduler-dev-cycle.sh # scheduler:scheduler:BATCH (auto-batched)
#
# on the host that had just stopped being a writer of scheduler's own git
# history -- and on dexter, whose rotation dispatches it already. The decision
# to stop and the mechanism that re-armed it were the SAME edit.
#
# What must hold, and note that cases 3-5 are the ones that keep this test
# honest -- a suppress-everything bug would pass 1 and 2 and nothing else:
#   1. member of ANOTHER host's rotation      -> suppressed (the bug)
#   2. member of the shared rotation          -> suppressed (no regression)
#   3. member of NO rotation                  -> fixed line still emitted
#   4. commented out in every rotation        -> fixed line emitted (rollback)
#   5. listed but PARKED (enabled=0)          -> suppressed (2026-07-25 rule)
#   6. PACED_SUPPRESS_BATCH=1, no rotation at all -> REFUSE, never "suppress
#      nothing", which would arm a nightly line for every project at once
#
# Runs the REAL script against a throwaway fixture repo built from the tree
# this witness ships in (same rule as reconcile-witness.sh -- never a
# hardcoded checkout). Preview mode only: nothing is ever written to a
# crontab, and `--apply` is not passed anywhere in this file.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/bin/sync-crontab.sh"
[ -f "$SYNC" ] || { echo "script under test not found: $SYNC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# --- fixture repo -----------------------------------------------------------
# bin/ and lib/ are copied from the tree under test; schedule/ is entirely
# synthetic, so no real project's conf can make this pass or fail.
REPO="$TMP/repo"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/schedule" "$REPO/wrappers"
cp -r "$ROOT/bin/." "$REPO/bin/"
cp -r "$ROOT/lib/." "$REPO/lib/"

for p in w-otherhost w-shared w-nowhere w-commented w-parked; do
  printf '#!/bin/sh\n' > "$REPO/wrappers/$p.sh"; chmod +x "$REPO/wrappers/$p.sh"
  cat > "$REPO/schedule/$p.conf" <<EOF
PROJECT="$p"
SWEEP_JOB_NAME=""; SWEEP_SCRIPT=""; SWEEP_CRON=""
BATCH_JOB_NAME="$p-batch"
BATCH_SCRIPT="$REPO/wrappers/$p.sh"
BATCH_CRON=""
EOF
done

cat > "$REPO/schedule/_runner.conf" <<EOF
RUNNER_JOB="fixture-paced-runner"
RUNNER_CMD="$REPO/wrappers/w-shared.sh"
RUNNER_CRON="*/5 * * * *"
RUNNER_ENV=""
PACED_SUPPRESS_BATCH=1
EOF

# w-stateowner: an enabled rotation member that ALSO sets CRON_ACCOUNT.
#
# CRON_ACCOUNT is a STATE-ownership field, not a dispatch-targeting one: it is
# what bin/scheduler's state_account()/state_home() read to answer "whose
# ~/.local/share holds this job's run log" (scheduler#33 -- four monkey jobs
# read as 7-12d idle and dead-man expired while running daily, because no conf
# set it). Every project account on monkey therefore sets CRON_ACCOUNT=<itself>
# and is an enabled participant in _paced.monkey.conf. Both at once is the
# NORMAL, CORRECT configuration on that host -- not a misconfiguration.
#
# `root` is used only because it is a real account on every host, which is what
# sync-crontab.sh's `home_of` check requires. Nothing is ever written to it:
# this witness is preview-only and never passes --apply.
printf '#!/bin/sh\n' > "$REPO/wrappers/w-stateowner.sh"
chmod +x "$REPO/wrappers/w-stateowner.sh"
cat > "$REPO/schedule/w-stateowner.conf" <<EOF
PROJECT="w-stateowner"
CRON_ACCOUNT="root"
SWEEP_JOB_NAME=""; SWEEP_SCRIPT=""; SWEEP_CRON=""
BATCH_JOB_NAME="w-stateowner-batch"
BATCH_SCRIPT="$REPO/wrappers/w-stateowner.sh"
BATCH_CRON=""
EOF

# The shared rotation: mandark's file, in the real repo's terms.
{
  echo 'w-shared|1|1|/bin/true'
  echo 'w-parked|0|1|/bin/true'
  echo '#w-commented|1|1|/bin/true'
  echo 'w-stateowner|1|1|/bin/true'
} > "$REPO/schedule/_paced.conf"
# Another host's rotation. Deliberately NOT this machine's hostname: the
# point is that membership in a rotation this host does not run still means
# "somebody's runner owns this project's Tier 2".
echo 'w-otherhost|1|1|/bin/true' > "$REPO/schedule/_paced.someotherhost.conf"

# Hermetic sudo (scheduler#94): resolve_cmd's foreign-account executability
# check (bin/sync-crontab.sh ~line 541) runs `sudo -n -u "$acct" test -x
# "$script"`, and real sudo's answer depends on the INVOKING ACCOUNT's
# passwordless-sudo rights -- an ambient property of the host this witness
# happens to run on, not of the code under test. That let a real
# double-dispatch regression go undetected here for six days: with no
# passwordless sudo the check fails for want of a password before the code
# under test is even reached, and with it the check passes as root
# regardless. Either way "no BATCH line, no error we recognise" looks the
# same as correct suppression. Stubbing sudo to just drop `-n`/`-u ACCT` and
# exec the remaining command makes the check answer `test -x "$script"`
# directly -- deterministic, and independent of who is running this test.
STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/sudo" <<'STUB'
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
chmod +x "$STUBBIN/sudo"

run_sync() { ( cd "$REPO" && PATH="$STUBBIN:$PATH" "$REPO/bin/sync-crontab.sh" 2>&1 ); }
OUT="$(run_sync)"

# A project is SUPPRESSED when no crontab line is generated for it. Match the
# generated line's own marker comment (# scheduler:<project>:BATCH), not the
# "note:" text -- the note is a courtesy message, the line is the artifact
# that would actually be installed.
emits_line() { printf '%s\n' "$OUT" | grep -q "# scheduler:$1:BATCH"; }

echo "== membership decides suppression, across every host's rotation"
if emits_line w-otherhost; then
  bad "w-otherhost got a fixed BATCH line -- member of another host's rotation, DOUBLE DISPATCH"
else
  ok "member of another host's rotation is suppressed"
fi
if emits_line w-shared; then
  bad "w-shared got a fixed BATCH line -- member of the shared rotation"
else
  ok "member of the shared rotation is suppressed"
fi
if emits_line w-parked; then
  bad "w-parked got a fixed BATCH line -- parking must not re-arm fixed cron"
else
  ok "parked-but-listed is suppressed (membership, not the enabled flag)"
fi

echo "== CRON_ACCOUNT (state ownership) must not be read as double dispatch"
# Found 2026-08-05 while arming crt and baudin: every sync on monkey printed
#   ERROR [ecosim]: CRON_ACCOUNT=ecosim, but 'ecosim' is also an ENABLED
#   participant in <account>'s _paced.monkey.conf -- that is double dispatch.
# four times, once per already-armed account, and reported "the affected
# tier(s) were left OUT of the generated crontab".
#
# The guard's stated premise is that the project "would run twice -- once from
# the runner here, once from that account's crontab". That premise is FALSE for
# an enabled rotation member, because membership is exactly what suppresses the
# fixed line: there is no second dispatch path to collide with. The guard
# duplicates the suppression it is standing in front of.
#
# It also `continue`d, which skipped the rest of the loop body for that conf --
# so the questions/<project>.md and focus/<project>.md symlinks were silently
# never created either. That is a functional loss, not just noise, and it also
# destroyed the "zero ERROR [" clean-preview witness that MONKEY.md 8.3 used as
# an arming criterion.
if emits_line w-stateowner; then
  bad "w-stateowner got a fixed BATCH line -- an enabled rotation member must stay suppressed"\
      "even when CRON_ACCOUNT names another account"
else
  ok "CRON_ACCOUNT + enabled rotation member is suppressed, not double-dispatched"
fi

# scheduler#94: this used to be the exact bracket form 'ERROR \[w-stateowner\]',
# which cannot match this script's own error format -- every ERROR line here
# is tagged with its tier ("ERROR [w-stateowner/BATCH]: ..."), never a bare
# "[w-stateowner]". The exact-bracket grep therefore never matched anything,
# on any host, and this assertion had silently never been evaluated. Matching
# the open bracket plus name, unanchored on the right, catches an ERROR for
# this project regardless of which tier or wording raised it.
if printf '%s\n' "$OUT" | grep -q 'ERROR \[w-stateowner'; then
  bad "w-stateowner raised an ERROR -- CRON_ACCOUNT is a STATE field (scheduler#33);"\
      "setting it on a paced participant is the normal configuration on monkey"
else
  ok "no ERROR raised for a paced participant that also owns its own state"
fi

echo "== and it does NOT suppress what it has no business suppressing"
if emits_line w-nowhere; then
  ok "a project in no rotation still gets its fixed BATCH line"
else
  bad "w-nowhere lost its fixed BATCH line -- over-suppression; this test would"\
      "otherwise pass on a script that suppressed everything"
fi
if emits_line w-commented; then
  ok "commented out of every rotation restores the fixed line (rollback path)"
else
  bad "w-commented stayed suppressed -- a commented-out participant is not a participant"
fi

echo "== PACED_SUPPRESS_BATCH=1 with no rotation file at all is a REFUSAL"
mv "$REPO/schedule/_paced.conf" "$TMP/_paced.conf.off"
mv "$REPO/schedule/_paced.someotherhost.conf" "$TMP/_paced.other.off"
NOROT="$(run_sync)"; NOROT_RC=$?
if [ "$NOROT_RC" -ne 0 ] && printf '%s\n' "$NOROT" | grep -q 'PACED_SUPPRESS_BATCH=1'; then
  ok "refuses loudly (rc=$NOROT_RC) rather than suppressing nothing"
else
  bad "rc=$NOROT_RC and no refusal -- 'no rotation file' silently arms a nightly line for every project"
fi
mv "$TMP/_paced.conf.off" "$REPO/schedule/_paced.conf"
mv "$TMP/_paced.other.off" "$REPO/schedule/_paced.someotherhost.conf"

echo "== the fix is wired in, not merely present in the library"
if grep -q 'paced_membership_set "\$SCHED_DIR"' "$SYNC"; then
  ok "bin/sync-crontab.sh calls paced_membership_set"
else
  bad "bin/sync-crontab.sh does not call paced_membership_set -- the fix is not wired in"
fi
if grep -qE 'done < "\$SCHEDULE_DIR/_paced\.conf"' "$SYNC"; then
  bad "bin/sync-crontab.sh still reads the shared _paced.conf directly -- the original bug"
else
  ok "bin/sync-crontab.sh no longer hardcodes the shared rotation file"
fi

echo
echo "sync-crontab paced witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
