#!/usr/bin/env bash
# Witness for a DOUBLE-DISPATCH shape distinct from
# tests/sync-crontab-paced-witness.sh's BATCH-line collision: this one is
# about the RUNNER line itself (schedule/_runner.conf's own tick), and the
# duplicate-detection guard meant to catch exactly this (bin/sync-crontab.sh
# ~line 990-1008).
#
# THE BUG (found 2026-08-14, hf7y/scheduler#79/#81 investigation): the guard
# compares "the command a KEPT unmanaged line runs" (kcmd) against "the
# command the managed block is about to run" (mcmd). mcmd strips the
# line's trailing tag comment ("# scheduler:<job>:RUNNER (usage-paced
# dispatch)") before comparing; kcmd does not. bin/dose-project.sh's own
# converged crontab lines carry that EXACT tag (it derives TAG from the same
# schedule/_runner.conf RUNNER_JOB), and it writes them WITHOUT the
# MARK_BEGIN/MARK_END markers sync-crontab.sh owns -- so a dose-converged
# line is exactly the "unmanaged" shape this guard exists to flag. Because
# kcmd retains the tag suffix and mcmd does not, the two never compare
# equal even when the command they run is byte-identical, so the guard is
# silently blind to its own tag format. Re-running `sync-crontab.sh --apply`
# against an account already converged by `dose <project> --apply` would
# install a SECOND runner line at a different (stale, conf-derived) cadence
# instead of warning -- concurrent agent dispatch from one account, twice.
#
# What must hold:
#   1. An unmanaged line whose command matches the managed RUNNER line,
#      differing ONLY by its own trailing "# scheduler:...:RUNNER (...)" tag
#      -> WARNING, not a silent double-install.
#   2. An unmanaged line with a genuinely different command -> no warning
#      (keeps the guard from crying wolf on unrelated lines).
#
# Runs the REAL script against a throwaway fixture repo, preview-only:
# --apply is never passed, so nothing is ever written to a real crontab.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/bin/sync-crontab.sh"
[ -f "$SYNC" ] || { echo "script under test not found: $SYNC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

REPO="$TMP/repo"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/schedule" "$REPO/wrappers"
cp -r "$ROOT/bin/." "$REPO/bin/"
cp -r "$ROOT/lib/." "$REPO/lib/"

printf '#!/bin/sh\n' > "$REPO/wrappers/w-runner.sh"; chmod +x "$REPO/wrappers/w-runner.sh"

cat > "$REPO/schedule/_runner.conf" <<EOF
RUNNER_JOB="fixture-paced-runner"
RUNNER_CMD="$REPO/wrappers/w-runner.sh"
RUNNER_CRON="0 */6 * * *"
RUNNER_ENV="PACED_MAX_PER_TICK=1"
PACED_SUPPRESS_BATCH=1
EOF
# No paced participants -- irrelevant to the runner-line collision this
# witness is about, and keeping the fixture minimal keeps the assertions
# honest about what triggered them. One inert project conf is still required:
# bin/sync-crontab.sh ~line 381 bails out early ("no schedule/*.conf entries
# yet -- nothing to sync") before it ever reaches RUNNER emission when the
# glob finds zero non-meta confs.
: > "$REPO/schedule/_paced.conf"
printf '#!/bin/sh\n' > "$REPO/wrappers/w-inert.sh"; chmod +x "$REPO/wrappers/w-inert.sh"
cat > "$REPO/schedule/w-inert.conf" <<EOF
PROJECT="w-inert"
SWEEP_JOB_NAME=""; SWEEP_SCRIPT=""; SWEEP_CRON=""
BATCH_JOB_NAME=""; BATCH_SCRIPT=""; BATCH_CRON=""
EOF

# Hermetic sudo, same stub as tests/sync-crontab-paced-witness.sh (scheduler#94):
# resolve_cmd's foreign-account executability check shells out to `sudo -n -u
# ...`, whose answer depends on the invoking account's ambient sudo rights.
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

# Hermetic crontab: read_crontab_for() calls the real `crontab -l` for the
# local account (bin/sync-crontab.sh ~line 104), which would otherwise read
# THIS witness's own invoking account's actual crontab -- a real crontab on
# a real host, not fixture state. Stubbed to answer `-l` from a plain fixture
# file and refuse anything else, so a bug that reaches for `crontab <file>`
# (an --apply write) fails loud rather than silently touching a real crontab.
CURRENT_CRONTAB_FILE="$STUBBIN/current-crontab.txt"
cat > "$STUBBIN/crontab" <<STUB
#!/bin/sh
if [ "\$1" = "-l" ]; then
  cat "$CURRENT_CRONTAB_FILE"
  exit 0
fi
echo "crontab stub: refusing non -l invocation (args: \$*) -- this witness is preview-only" >&2
exit 9
STUB
chmod +x "$STUBBIN/crontab"
crontab_stub() { printf '%s\n' "$1" > "$CURRENT_CRONTAB_FILE"; }

run_sync() { ( cd "$REPO" && PATH="$STUBBIN:$PATH" "$REPO/bin/sync-crontab.sh" 2>&1 ); }

echo "== an unmanaged line differing ONLY by its own RUNNER tag comment"
crontab_stub "21 */2 * * * PACED_MAX_PER_TICK=1 $REPO/wrappers/w-runner.sh # scheduler:fixture-paced-runner:RUNNER (usage-paced dispatch)"
OUT="$(run_sync)"
if printf '%s\n' "$OUT" | grep -q 'WARNING \['"$(id -un)"'\]:.*RUNNER (usage-paced dispatch)\|WARNING \['"$(id -un)"'\]:.*'"$REPO/wrappers/w-runner.sh"; then
  ok "tag-only difference is still flagged as a collision"
else
  bad "a dose-converged RUNNER line (same command, different cadence, its own tag) was NOT flagged -- sync-crontab.sh --apply would silently install a second runner line"
  echo "$OUT"
fi

echo "== an unmanaged line whose command genuinely differs"
crontab_stub "0 3 * * * $REPO/wrappers/w-runner.sh --unrelated-flag"
OUT="$(run_sync)"
if printf '%s\n' "$OUT" | grep -q 'WARNING'; then
  bad "an unrelated unmanaged line raised a collision warning -- guard is over-firing"
  echo "$OUT"
else
  ok "an unrelated unmanaged line raises no warning"
fi

echo
echo "sync-crontab-runner-tag-collision-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
