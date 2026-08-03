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

echo "== a repo-relative meta command resolves against the repo (bare-host bootstrap)"
# THE BUG THESE RETIRE: both shipped meta confs named a path OUTSIDE the repo
# that nothing in the repo creates, so a fresh clone omitted the runner tick --
# and since it is the only agent-dispatching line, that is a TOTAL DISPATCH
# OUTAGE reported as one stderr line by a command that exits 0.
#
# The fixture repo has bin/ copied from the tree under test, so this path is
# real here for the same reason it is real on a bare host: the repo ships it.
write_runner "bin/usage-paced-runner.sh"
write_sweep "$GOOD"
run_sync
if emits_runner; then
  ok "a repo-relative RUNNER_CMD is accepted -- a fresh clone can dispatch"
else
  bad "a repo-relative RUNNER_CMD was refused -- a bare host still cannot bootstrap"
fi
# The emitted line must carry the RESOLVED absolute path: cron has no notion of
# "the repo", so a relative word reaching the crontab fails on every tick.
if printf '%s\n' "$OUT" | grep -q "$REPO/bin/usage-paced-runner.sh # scheduler:fixture-paced-runner:RUNNER"; then
  ok "the emitted crontab line carries the resolved absolute path"
else
  bad "the emitted line lacks the resolved path -- cron cannot run a repo-relative word"
fi

# Resolution must not become a way for anything at all to pass.
write_runner "bin/definitely-not-shipped.sh"
run_sync
if emits_runner; then
  bad "a repo-relative path that does not exist was still emitted -- resolve is masking the check"
else
  ok "a repo-relative path that does not exist is still refused"
fi

echo "== resolution must not silently change which binary runs"
# A BARE NAME is a deliberate PATH lookup, not a path. Rewriting `scheduler`
# into $REPO/scheduler would change which binary the tick invokes -- the
# opposite of the bug being fixed, and invisible until it ran.
write_runner "true"
run_sync
if emits_runner && ! printf '%s\n' "$OUT" | grep -q "$REPO/true"; then
  ok "a bare command name is left alone for cron's PATH to resolve"
else
  bad "a bare command name was rewritten into a repo path -- changes which binary runs"
fi
write_runner "$GOOD"
run_sync
if printf '%s\n' "$OUT" | grep -q "$GOOD # scheduler:fixture-paced-runner:RUNNER"; then
  ok "an absolute RUNNER_CMD is passed through unchanged"
else
  bad "an absolute RUNNER_CMD was rewritten -- absolute must mean absolute"
fi

echo "== the resolver is wired into the emitters, not merely defined"
if grep -q 'meta_cmd_resolve "\$RUNNER_CMD"' "$SYNC"; then
  ok "RUNNER emitter calls meta_cmd_resolve"
else
  bad "RUNNER emitter does not call meta_cmd_resolve -- not wired in"
fi
if grep -q 'meta_cmd_resolve "\$SWEEP_TICK_CMD"' "$SYNC"; then
  ok "SWEEP emitter calls meta_cmd_resolve"
else
  bad "SWEEP emitter does not call meta_cmd_resolve -- not wired in"
fi

echo "== the SHIPPED confs are themselves bare-host-clonable"
# The mechanism is worth nothing if the confs this repo actually ships still
# name a path outside it. Checked against the REAL schedule/, not the fixture.
for f in _runner.conf _sweep.conf; do
  v="$(grep -hE '^(RUNNER_CMD|SWEEP_TICK_CMD)=' "$ROOT/schedule/$f" | cut -d'"' -f2)"
  case "$v" in
    /*) bad "schedule/$f names an absolute path outside the repo: $v" ;;
    "") bad "schedule/$f has no command set" ;;
    *)  ok  "schedule/$f is repo-relative or a bare name: $v" ;;
  esac
done
# A SOURCED project conf may use $HOME; it must not hardcode one user's home.
# (schedule/_paced*.conf and _monitor.conf are READ, not sourced -- $HOME does
# not expand there, so their command column stays absolute by design and is
# deliberately not checked here.)
if grep -lE '^PROJECT_REPO_PATH="/home/' "$ROOT"/schedule/*.conf >/dev/null 2>&1; then
  bad "a project conf hardcodes an absolute home in PROJECT_REPO_PATH -- it cannot clone onto another host or user"
else
  ok "no project conf hardcodes an absolute home in PROJECT_REPO_PATH"
fi

# schedule/scheduler.conf is a SYMLINK to ../.scheduler/schedule.conf -- the
# self-contained-folder model every other project is migrating onto. It is
# also a trap: `sed -i` does not edit through a symlink, it REPLACES it with a
# regular file, silently detaching the conf from the folder that owns it and
# leaving two copies to drift. That happened while writing this very commit
# and was caught only by reading the diffstat (91 insertions for a one-line
# change). Cheap to assert, invisible when it breaks.
if [ -L "$ROOT/schedule/scheduler.conf" ]; then
  ok "schedule/scheduler.conf is still a symlink into .scheduler/"
else
  bad "schedule/scheduler.conf is no longer a symlink -- an in-place edit replaced it, and .scheduler/schedule.conf is now a second copy that will drift"
fi

echo
echo "meta-cmd preflight witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
