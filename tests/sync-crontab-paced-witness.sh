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

# The shared rotation: mandark's file, in the real repo's terms.
{
  echo 'w-shared|1|1|/bin/true'
  echo 'w-parked|0|1|/bin/true'
  echo '#w-commented|1|1|/bin/true'
} > "$REPO/schedule/_paced.conf"
# Another host's rotation. Deliberately NOT this machine's hostname: the
# point is that membership in a rotation this host does not run still means
# "somebody's runner owns this project's Tier 2".
echo 'w-otherhost|1|1|/bin/true' > "$REPO/schedule/_paced.someotherhost.conf"

run_sync() { ( cd "$REPO" && "$REPO/bin/sync-crontab.sh" 2>&1 ); }
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
