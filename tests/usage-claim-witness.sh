#!/usr/bin/env bash
set -uo pipefail  # witness for lib/usage-claim.sh, hf7y/scheduler#339 -- section D is the row that matters: a crashed holder's claim releases itself
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/usage-claim.sh"
[ -r "$LIB" ] || { echo "not found: $LIB"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "usage-claim-witness"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
CLAIMDIR="$WORK/claim"

status() { ( export USAGE_CLAIM_DIR="$CLAIMDIR"; . "$ROOT/lib/usage-claim.sh"; usage_claim_status ); }

echo
echo "== A. an unclaimed window is free"
out="$(status)"; rc=$?
[ "$rc" -eq 1 ] && ok "A1 status is 1 (free) before anyone claims" || bad "A1 rc=$rc: $out"
[ "$out" = "free" ] && ok "A2 prints 'free'" || bad "A2: $out"

echo
echo "== B. a held claim reports held, with its label"
(  # reads "$$" here since that's what usage_claim_acquire writes; $$ in (...) names the INVOKING shell, a bash quirk
  export USAGE_CLAIM_DIR="$CLAIMDIR"
  . "$ROOT/lib/usage-claim.sh"
  echo "$$" > "$WORK/holder-pid"
  usage_claim_acquire "b-label"
  sleep 5
) &
HP=$!
sleep 1
HOLDER_MARKER_PID="$(cat "$WORK/holder-pid")"
out="$(status)"; rc=$?
[ "$rc" -eq 0 ] && ok "B1 status is 0 (held) while the holder is alive" || bad "B1 rc=$rc: $out"
case "$out" in *"label=b-label"*"pid=$HOLDER_MARKER_PID"*) ok "B2 names the label and pid" ;; *) bad "B2: $out" ;; esac

echo
echo "== C. a SECOND acquire is refused while the first is alive"
out2="$( ( export USAGE_CLAIM_DIR="$CLAIMDIR"; . "$ROOT/lib/usage-claim.sh"; usage_claim_acquire "c-label"; echo "rc=$?" ) )"
case "$out2" in *"rc=3"*) ok "C1 usage_claim_acquire returns 3 (already held)" ;; *) bad "C1: $out2" ;; esac

echo
echo "== D. THE crash case: kill -9 the holder, the claim releases itself"
kill -9 "$HP" 2>/dev/null
wait "$HP" 2>/dev/null
out="$(status)"; rc=$?
[ "$rc" -eq 1 ] && ok "D1 status flips to free the instant the holder is gone -- no cleanup call ran" || bad "D1 rc=$rc: $out"
[ "$out" = "free" ] && ok "D2 and the stale marker is swept away, not just the lock" || bad "D2: $out"

echo
echo "== E. usage_claim_hold releases on a normal exit and propagates the exit code"
( export USAGE_CLAIM_DIR="$CLAIMDIR"; . "$ROOT/lib/usage-claim.sh"; usage_claim_hold e-label -- bash -c 'exit 7' )
rc=$?
[ "$rc" -eq 7 ] && ok "E1 propagates the wrapped command's exit code" || bad "E1 rc=$rc"
out="$(status)"; rc=$?
[ "$rc" -eq 1 ] && ok "E2 free again after the command returns" || bad "E2 rc=$rc: $out"

echo
echo "== F. usage_claim_hold refuses (3) without running the command, if held"
(
  export USAGE_CLAIM_DIR="$CLAIMDIR"
  . "$ROOT/lib/usage-claim.sh"
  usage_claim_acquire "f-label"
  sleep 5
) &
HP=$!
sleep 1
MARK="$WORK/ran"
( export USAGE_CLAIM_DIR="$CLAIMDIR"; . "$ROOT/lib/usage-claim.sh"; usage_claim_hold f2 -- touch "$MARK" )
rc=$?
[ "$rc" -eq 3 ] && ok "F1 usage_claim_hold returns 3" || bad "F1 rc=$rc"
[ ! -e "$MARK" ] && ok "F2 the wrapped command never ran" || bad "F2 it ran anyway"
kill -9 "$HP" 2>/dev/null; wait "$HP" 2>/dev/null

echo
echo "usage-claim-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
