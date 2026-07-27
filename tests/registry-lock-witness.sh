#!/usr/bin/env bash
# Witness for lib/registry-lock.sh -- the two-half lockout shared by
# lib/sweep-loop-common.sh (every project's jobs) and
# bin/scheduler-dev-cycle.sh (the scheduler's own self-dev cycle).
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

CF="$TMP/count"

mk_marker() { printf 'pid=%s\nstarted_at=%s\ncwd=/x\n' "$1" "2026-07-27T10:00:00" > "$REGISTRY_DIR/p.interactive"; }
# A pid that is certainly dead: spawn and reap.
dead_pid() { local d; ( exit 0 ) & d=$!; wait $d 2>/dev/null; echo $d; }

echo "== 1. no marker at all -> proceed"
rm -f "$REGISTRY_DIR/p.interactive" "$CF"
registry_should_defer p "$CF" 3 && bad "deferred with no human" || ok "proceeds"
[ -z "$(registry_human_pid p)" ] && ok "no human pid reported" || bad "invented a human"

echo "== 2. LIVE marker -> defer, and count climbs"
mk_marker $$
registry_should_defer p "$CF" 3 && ok "deferred to the live session" || bad "did not defer"
[ "$REGISTRY_DEFER_COUNT" = "1" ] && ok "counted deferral 1" || bad "count=$REGISTRY_DEFER_COUNT"
[ "$REGISTRY_DEFER_PID" = "$$" ] && ok "named the right pid" || bad "pid=$REGISTRY_DEFER_PID"
registry_should_defer p "$CF" 3 >/dev/null
[ "$(cat "$CF")" = "2" ] && ok "count persists across calls" || bad "count=$(cat "$CF")"

echo "== 3. STALE marker (dead pid) -> proceed, and reset the count"
D="$(dead_pid)"; mk_marker "$D"
registry_should_defer p "$CF" 3 && bad "deferred to a dead session" || ok "ignores a dead pid"
[ ! -f "$CF" ] && ok "count file cleared" || bad "count survived: $(cat "$CF" 2>/dev/null)"
[ "${REGISTRY_DEFER_CAPPED:-x}" = "0" ] && ok "not flagged as capped" || bad "wrongly capped"

echo "== 4. STARVATION CAP -> proceeds, but flags that it overrode a human"
mk_marker $$; echo 3 > "$CF"
registry_should_defer p "$CF" 3 && bad "deferred past the cap (starvation)" || ok "proceeds at the cap"
[ "${REGISTRY_DEFER_CAPPED:-0}" = "1" ] && ok "CAPPED flag set -- caller must warn" || bad "capped case indistinguishable from 'nobody home'"
[ "$REGISTRY_DEFER_PID" = "$$" ] && ok "still names the human it overrode" || bad "lost the pid"

echo "== 5. job-vs-job: second claimant is refused while the first holds"
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

echo "== 6. sweep-loop-common still routes through the shared lib"
SLC="$(dirname "$LIB")/sweep-loop-common.sh"
grep -q 'registry-lock.sh' "$SLC" && ok "sweep-loop-common sources the lib" || bad "still carries its own copy"
grep -q 'REGISTRY_DEFER_CAPPED' "$SLC" && ok "handles the capped case explicitly" || bad "capped case dropped in refactor"
grep -q 'exit 4' "$SLC" && ok "exit-code contract (4=deferred) preserved" || bad "exit 4 lost"
c="$(grep -c 'kill -0' "$SLC")"
[ "$c" -eq 0 ] && ok "no leftover inline pid probe" || bad "$c inline pid probe(s) still in sweep-loop-common"

echo "== 7. dev-cycle participates in BOTH halves"
DC="$(dirname "$LIB")/../bin/scheduler-dev-cycle.sh"
grep -q 'registry_claim' "$DC" && ok "takes the project lock" || bad "no registry_claim"
grep -q 'registry_should_defer' "$DC" && ok "defers to a live human" || bad "no human deferral"
grep -q 'registry_release' "$DC" && ok "releases on exit" || bad "never releases"

echo
echo "==== registry-lock witness: $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
