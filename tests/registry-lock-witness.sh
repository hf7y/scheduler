#!/usr/bin/env bash
# Witness for lib/registry-lock.sh -- the two-half lockout shared by
# lib/sweep-loop-common.sh (every project's jobs) and, formerly,
# bin/scheduler-dev-cycle.sh (retired, hf7y/scheduler#190).
#
# The bug this exists to prevent is a lockout that reports "free" while
# someone is working -- failing OPEN. Cases 3/4 are that direction.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/registry-lock.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

export REGISTRY_DIR="$TMP/registry"; mkdir -p "$REGISTRY_DIR"
# shellcheck source=../lib/registry-lock.sh
. "$LIB"
type registry_claim registry_should_defer >/dev/null 2>&1 \
  || { echo "lib did not define its functions"; exit 1; }

CF="$TMP/streak"
# Two checkouts: one being worked in, one whose files are all old.
WORK="$TMP/work"; IDLE="$TMP/idle"; mkdir -p "$WORK" "$IDLE"
touch "$IDLE/old.txt"; touch -d '3 days ago' "$IDLE/old.txt"

mk_marker() { printf 'pid=%s\nstarted_at=%s\ncwd=%s\n' "$1" "2026-07-27T10:00:00" "${2:-/x}" > "$REGISTRY_DIR/p.interactive"; }
# A pid that is certainly dead: spawn and reap.
dead_pid() { local d; ( exit 0 ) & d=$!; wait $d 2>/dev/null; echo $d; }

echo "== 1. no marker at all -> proceed"
rm -f "$REGISTRY_DIR/p.interactive" "$CF"
registry_should_defer p "$CF" && bad "deferred with no human" || ok "proceeds"
[ -z "$(registry_human_pid p)" ] && ok "no human pid reported" || bad "invented a human"

echo "== 2. live session + RECENTLY EDITED repo -> defer"
mk_marker $$ "$WORK"; touch "$WORK/file.txt"
registry_should_defer p "$CF" && ok "deferred while the repo is being worked in" || bad "did not defer"
[ "$REGISTRY_DEFER_PID" = "$$" ] && ok "named the right pid" || bad "pid=$REGISTRY_DEFER_PID"
[ -f "$CF" ] && ok "streak start recorded" || bad "no streak file"
S1="$(cat "$CF")"; registry_should_defer p "$CF" >/dev/null
[ "$(cat "$CF")" = "$S1" ] && ok "streak START is stable across calls (not a counter)" || bad "streak start moved"

echo "== 3. THE REGRESSION: live session + IDLE repo -> proceed, quietly"
# A file left open in a background terminal is not a person working. This is
# the case the retired attempt-counter could not see at all.
rm -f "$CF"; mk_marker $$ "$IDLE"
registry_should_defer p "$CF" && bad "deferred to a background editor" || ok "proceeds when the repo is quiet"
[ "${REGISTRY_DEFER_CAPPED:-x}" = "0" ] \
  && ok "NOT flagged capped -- this is the normal path, must not notify" \
  || bad "idle-repo proceed wrongly flagged as a backstop override"
grep -qi 'background editor' <<<"$REGISTRY_DEFER_REASON" && ok "reason names it" || bad "reason=$REGISTRY_DEFER_REASON"

echo "== 4. attempt count is NOT the trigger (the actual 2026-07-27 failure)"
# Four rapid attempts used to exhaust INTERACTIVE_DEFER_MAX=3 in ten seconds.
rm -f "$CF"; mk_marker $$ "$WORK"; touch "$WORK/file.txt"
for _ in 1 2 3 4 5 6; do registry_should_defer p "$CF" >/dev/null || break; done
registry_should_defer p "$CF" && ok "still deferring after 6 rapid attempts" || bad "attempts alone forced a start"
[ "${REGISTRY_DEFER_CAPPED:-0}" = "0" ] && ok "no backstop fired on attempt count" || bad "backstop fired on attempts"

echo "== 5. STALE marker (dead pid) -> proceed, clear the streak"
D="$(dead_pid)"; mk_marker "$D" "$WORK"
registry_should_defer p "$CF" && bad "deferred to a dead session" || ok "ignores a dead pid"
[ ! -f "$CF" ] && ok "streak file cleared" || bad "streak survived"
[ "${REGISTRY_DEFER_CAPPED:-x}" = "0" ] && ok "not flagged as capped" || bad "wrongly capped"

echo "== 6. TIME backstop -> proceeds over an active repo, and says so loudly"
mk_marker $$ "$WORK"; touch "$WORK/file.txt"
echo "$(( $(date +%s) - 25*3600 ))" > "$CF"     # streak began 25h ago
registry_should_defer p "$CF" && bad "deferred past the 24h backstop (starvation)" || ok "proceeds at the backstop"
[ "${REGISTRY_DEFER_CAPPED:-0}" = "1" ] && ok "CAPPED set -- caller must warn" || bad "backstop indistinguishable from normal proceed"
[ "$REGISTRY_DEFER_PID" = "$$" ] && ok "still names the human it overrode" || bad "lost the pid"

echo "== 7. unreadable cwd -> defers conservatively (never fails open)"
rm -f "$CF"; mk_marker $$ "/nonexistent/path/xyz"
registry_should_defer p "$CF" && ok "defers when activity is unknowable" || bad "FAILED OPEN on an unreadable cwd"
grep -qi 'UNKNOWN' <<<"$REGISTRY_DEFER_REASON" && ok "reason says it could not tell" || bad "reason=$REGISTRY_DEFER_REASON"

echo "== 8. .git churn alone must not read as human activity"
rm -f "$CF"; mk_marker $$ "$IDLE"
mkdir -p "$IDLE/.git"; touch "$IDLE/.git/FETCH_HEAD"   # git housekeeping, not a person
registry_should_defer p "$CF" && bad "git internals counted as editing" || ok ".git is pruned from the activity probe"

echo "== 9. job-vs-job: second claimant is refused while the first holds"
rm -f "$REGISTRY_DIR/p.interactive"
registry_claim p job-a bug-sweep && ok "first claim granted" || bad "first claim refused"
[ -f "$REGISTRY_DIR/p.active" ] && ok ".active marker written" || bad "no .active marker"
grep -q '"job":"job-a"' "$REGISTRY_DIR/p.active" && ok ".active names the holder" || bad "marker content wrong"
# A separate process must be refused (the flock is per-process).
if bash -c ". '$LIB'; REGISTRY_DIR='$REGISTRY_DIR' registry_claim p job-b nightly" 2>/dev/null; then
  bad "second process claimed a held project"
else
  ok "second process refused while held"
fi
registry_release
[ ! -f "$REGISTRY_DIR/p.active" ] && ok "release removes .active" || bad ".active survived release"

echo "== 10. sweep-loop-common still routes through the shared lib"
SLC="$(dirname "$LIB")/sweep-loop-common.sh"
grep -q 'registry-lock.sh' "$SLC" && ok "sweep-loop-common sources the lib" || bad "still carries its own copy"
grep -q 'REGISTRY_DEFER_CAPPED' "$SLC" && ok "handles the capped case explicitly" || bad "capped case dropped in refactor"
grep -q 'exit 4' "$SLC" && ok "exit-code contract (4=deferred) preserved" || bad "exit 4 lost"
c="$(grep -c 'kill -0' "$SLC")"
[ "$c" -eq 0 ] && ok "no leftover inline pid probe" || bad "$c inline pid probe(s) still in sweep-loop-common"

echo
echo "==== registry-lock witness: $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
