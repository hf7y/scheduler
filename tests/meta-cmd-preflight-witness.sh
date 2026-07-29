#!/usr/bin/env bash
# Witness for "will bin/sync-crontab.sh install a META cron line whose command
# does not exist on this host?" -- i.e. a generated crontab that is DEAD ON
# ARRIVAL, failing with "command not found" on every tick into a mail spool
# nobody reads.
#
# THE GAP THIS RETIRES (found 2026-07-29 by re-probing dexter, not by reading):
# every PER-PROJECT line already goes through resolve_cmd(), which refuses a
# <TIER>_SCRIPT that is absent or non-executable and says which account could
# not run it. The two META tiers -- the RUNNER tick from schedule/_runner.conf
# and the SWEEP tick from schedule/_sweep.conf -- were the exception. They
# validated that the conf fields were non-empty and that the cron expression
# had five fields, and nothing else. So on dexter, where
# `/home/zach/.local/bin/scheduler` has never been installed (only
# usage-gate.sh and usage-paced-runner.sh are, symlinked 2026-07-24),
# `bin/sync-crontab.sh --apply` would have installed
#
#   */15 * * * * /home/zach/.local/bin/scheduler sweep # scheduler:...:SWEEP
#
# a tick guaranteed to fail every 15 minutes, silently, forever.
#
# What must hold:
#   1. RUNNER_CMD absent            -> ERROR, runner tick OMITTED, rc!=0
#   2. SWEEP_TICK_CMD absent        -> ERROR, sweep tick OMITTED, rc!=0
#   3. one tier dead                -> the OTHER tier still emits (a dead
#                                      sweep must not cost you dispatch)
#   4. both commands runnable       -> BOTH lines emitted, rc=0 (no
#                                      regression; without this case the
#                                      test would pass on a script that
#                                      refused every meta line)
#   5. DANGLING SYMLINK             -> refused (the failure mode a bare -e
#                                      on the link would sail straight past)
#   6. exists but NOT executable    -> refused
#   7. command word carries ARGS    -> only the word is checked, so a
#                                      runnable command with arguments is
#                                      not rejected for having them
#
# Runs the REAL script against a throwaway fixture repo built from the tree
# this witness ships in. Preview mode only: `--apply` appears nowhere in this
# file and no crontab is ever read or written.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/bin/sync-crontab.sh"
[ -f "$SYNC" ] || { echo "script under test not found: $SYNC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# --- fixture repo -----------------------------------------------------------
# bin/ and lib/ come from the tree under test; schedule/ is entirely
# synthetic, so no real project's conf can make this pass or fail.
REPO="$TMP/repo"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/schedule" "$REPO/wrappers"
cp -r "$ROOT/bin/." "$REPO/bin/"
cp -r "$ROOT/lib/." "$REPO/lib/"

# A real, runnable command for the "no regression" cases.
GOOD="$REPO/wrappers/good.sh"
printf '#!/bin/sh\n' > "$GOOD"; chmod +x "$GOOD"

# Exists, but not executable -- case 6.
NOEXEC="$REPO/wrappers/noexec.sh"
printf '#!/bin/sh\n' > "$NOEXEC"; chmod 0644 "$NOEXEC"

# A symlink pointing at nothing -- case 5. `[ -e ]` on the link is false and
# `[ -x ]` is false, but a check written as "is there a file here" against
# the LINK ITSELF (-h / -L) would call this present.
DANGLE="$REPO/wrappers/dangling.sh"
ln -s "$REPO/wrappers/deleted-target.sh" "$DANGLE"

# One ordinary project, purely so the script has something to sync -- it bails
# early with "no schedule/*.conf entries yet" otherwise. PACED_SUPPRESS_BATCH
# stays 0 and no rotation file exists, so this project is never suppressed and
# nothing under test here depends on rotation membership.
printf '#!/bin/sh\n' > "$REPO/wrappers/filler.sh"; chmod +x "$REPO/wrappers/filler.sh"
cat > "$REPO/schedule/filler.conf" <<EOF
PROJECT="filler"
SWEEP_JOB_NAME=""; SWEEP_SCRIPT=""; SWEEP_CRON=""
BATCH_JOB_NAME="filler-batch"
BATCH_SCRIPT="$REPO/wrappers/filler.sh"
BATCH_CRON="0 1 * * *"
EOF

write_runner() {
  cat > "$REPO/schedule/_runner.conf" <<EOF
RUNNER_JOB="fixture-paced-runner"
RUNNER_CMD="$1"
RUNNER_CRON="*/5 * * * *"
RUNNER_ENV=""
PACED_SUPPRESS_BATCH=0
EOF
}
write_sweep() {
  cat > "$REPO/schedule/_sweep.conf" <<EOF
SWEEP_TICK_JOB="fixture-sweep-tick"
SWEEP_TICK_CMD="$1"
SWEEP_TICK_CRON="*/15 * * * *"
EOF
}

OUT=""; RC=0
run_sync() {
  OUT="$( cd "$REPO" && "$REPO/bin/sync-crontab.sh" 2>&1 )"
  RC=$?
}
# The ARTIFACT, not the courtesy message: match the marker comment that ends
# the generated line, which is what would actually land in a crontab.
emits_runner() { printf '%s\n' "$OUT" | grep -q '# scheduler:fixture-paced-runner:RUNNER'; }
emits_sweep()  { printf '%s\n' "$OUT" | grep -q '# scheduler:fixture-sweep-tick:SWEEP'; }

echo "== a meta command that is not there is REFUSED, not installed"

write_runner "$REPO/wrappers/definitely-not-here.sh"
write_sweep "$GOOD"
run_sync
if emits_runner; then
  bad "RUNNER tick emitted for a command that does not exist -- dead line installed"
else
  ok "absent RUNNER_CMD omits the runner tick"
fi
if [ "$RC" -ne 0 ]; then
  ok "absent RUNNER_CMD exits non-zero (rc=$RC)"
else
  bad "rc=0 with a refused runner tick -- exit-0 no-op, the caller cannot tell"
fi
if printf '%s\n' "$OUT" | grep -q 'ERROR \[runner\]'; then
  ok "says WHICH tier failed, loudly"
else
  bad "no 'ERROR [runner]' line -- refused silently"
fi
if emits_sweep; then
  ok "a dead RUNNER does not take the SWEEP tick down with it"
else
  bad "SWEEP tick lost to an unrelated runner failure -- over-refusal"
fi

write_runner "$GOOD"
write_sweep "$REPO/wrappers/definitely-not-here.sh sweep"
run_sync
if emits_sweep; then
  bad "SWEEP tick emitted for a command that does not exist -- this is the dexter bug"
else
  ok "absent SWEEP_TICK_CMD omits the sweep tick"
fi
if printf '%s\n' "$OUT" | grep -q 'ERROR \[sweep\]'; then
  ok "says WHICH tier failed, loudly"
else
  bad "no 'ERROR [sweep]' line -- refused silently"
fi
if emits_runner; then
  ok "a dead SWEEP does not cost you paced dispatch"
else
  bad "RUNNER tick lost to an unrelated sweep failure -- over-refusal"
fi

echo "== the ways a command can be 'present' and still not run"

write_runner "$DANGLE"
write_sweep "$GOOD"
run_sync
if emits_runner; then
  bad "dangling symlink accepted -- the link exists, the command does not"
else
  ok "a dangling symlink is refused (-x follows the link, -h would not)"
fi

write_runner "$NOEXEC"
run_sync
if emits_runner; then
  bad "non-executable file accepted -- cron cannot run it"
else
  ok "an existing but non-executable file is refused"
fi

echo "== and it does NOT refuse what it has no business refusing"

write_runner "$GOOD"
write_sweep "$GOOD"
run_sync
if emits_runner && emits_sweep; then
  ok "both meta ticks emitted when both commands are runnable"
else
  bad "a runnable meta command was refused -- over-refusal; without this case"\
      "the test would pass on a script that emitted no meta line at all"
fi
if [ "$RC" -eq 0 ]; then
  ok "rc=0 when nothing is wrong"
else
  bad "rc=$RC with two runnable meta commands -- spurious failure. output: $OUT"
fi

write_sweep "$GOOD --with args and more"
run_sync
if emits_sweep; then
  ok "arguments after the command word do not make a runnable command unrunnable"
else
  bad "a runnable command was refused because it had arguments -- the check is"\
      "testing the whole line instead of the command word"
fi

echo "== the check is wired into the emitters, not merely defined"
if grep -q 'meta_cmd_unrunnable "\$RUNNER_CMD"' "$SYNC"; then
  ok "RUNNER emitter calls meta_cmd_unrunnable"
else
  bad "RUNNER emitter does not call meta_cmd_unrunnable -- not wired in"
fi
if grep -q 'meta_cmd_unrunnable "\$SWEEP_TICK_CMD"' "$SYNC"; then
  ok "SWEEP emitter calls meta_cmd_unrunnable"
else
  bad "SWEEP emitter does not call meta_cmd_unrunnable -- not wired in"
fi

echo
echo "meta-cmd preflight witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
