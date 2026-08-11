#!/usr/bin/env bash
# notify-scratch-repo-witness.sh -- notify_human() drops the POPUP for a repo
# under a temp root, and never drops the FINDING.
#
# The incident: 2026-08-11, Zach paged every ~2 minutes by
# `notify-send -u critical test-job "paced/... conflicts with main ..."` fired
# from a throwaway /tmp/tmp.XXXX/tN/repo clone by some harness exercising
# reconcile_prior_cycles for real. Two sessions spent effort arguing whose
# harness it was; the popup was wrong regardless of the answer.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DC="$HERE/../bin/scheduler-dev-cycle.sh"
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }
echo "notify-scratch-repo-witness"

# Read the function out rather than sourcing the script, which would run it.
eval "$(sed -n '/^notify_human() {/,/^}/p' "$DC")"
declare -F notify_human >/dev/null \
  && ok "notify_human extracted from the dev-cycle" \
  || { bad "could not extract notify_human -- nothing below tested anything"; echo; exit 1; }

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
# A fake notify-send that RECORDS being called, so "did the popup fire" is a
# fact on disk rather than an absence we hope means something.
printf '#!/usr/bin/env bash\necho "FIRED $*" >> "%s/fired"\n' "$TMPD" > "$TMPD/bin/notify-send"
chmod +x "$TMPD/bin/notify-send"
export PATH="$TMPD/bin:$PATH"

# --- 1. a scratch clone under /tmp: no popup, but the finding is said ------
: > "$TMPD/fired"
SCHED_REPO="/tmp/tmp.XXXXXX/t7/repo"
out="$(notify_human "test-job" "paced/2026-07-25 conflicts with main -- 1 commit(s) stranded" 2>&1)"
[ ! -s "$TMPD/fired" ] && ok "no popup fired for a /tmp scratch clone" \
  || bad "popup fired anyway: $(cat "$TMPD/fired")"
grep -qi 'suppress' <<<"$out" && ok "it says the popup was suppressed" \
  || bad "suppressed silently, which is the no-op this guard must not be: $out"
grep -q 'stranded' <<<"$out" && ok "the finding itself still reaches the log" \
  || bad "the message was lost, not just the interruption: $out"

# --- 2. the real checkout: the popup MUST still fire -----------------------
# Without this the guard is indistinguishable from deleting the notification.
: > "$TMPD/fired"
SCHED_REPO="/home/zach/Documents/Projects/scheduler"
notify_human "scheduler" "reconcile could not push main (2 ahead)" >/dev/null 2>&1
grep -q 'FIRED' "$TMPD/fired" && ok "a real checkout still pages the human" \
  || bad "the guard suppressed a REAL notification -- worse than the bug"

# --- 3. /var/tmp and \$TMPDIR are temp roots too ---------------------------
: > "$TMPD/fired"
SCHED_REPO="/var/tmp/scratch/repo"
notify_human "test-job" "x" >/dev/null 2>&1
[ ! -s "$TMPD/fired" ] && ok "/var/tmp is treated as a temp root" || bad "/var/tmp fired a popup"

# --- 4. not fooled by a real path that merely CONTAINS the word tmp --------
: > "$TMPD/fired"
SCHED_REPO="/home/zach/Documents/Projects/tmpfile-tools"
notify_human "tmpfile-tools" "y" >/dev/null 2>&1
grep -q 'FIRED' "$TMPD/fired" \
  && ok "a real repo whose name contains 'tmp' still notifies" \
  || bad "suppressed on a substring match -- the guard is matching names, not roots"

printf '\nnotify-scratch-repo-witness: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
