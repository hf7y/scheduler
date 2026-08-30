#!/usr/bin/env bash
# Witness for "which rotation file does this host run?" -- lib/paced-conf.sh.
#
# The bug this exists to prevent is a front door that ANSWERS ABOUT THE WRONG
# MACHINE. Until 2026-07-29 bin/scheduler hardcoded schedule/_paced.conf while
# bin/usage-paced-runner.sh beside it resolved schedule/_paced.<host>.conf, so
# on dexter `scheduler weight scheduler` said "not a participant" about the one
# project dexter's rotation has enabled, and `scheduler weight <p> <n>` wrote
# and COMMITTED into mandark's rotation file -- a cross-host write, which is
# precisely what the per-host split exists to make impossible.
#
# Three things must hold, and the third is the one that rots:
#   1. the host-scoped file wins when it exists, the shared file when it does not
#   2. neither file present => REFUSE (empty PACED_CONF + nonzero), never a
#      plausible-looking default
#   3. the runner's INLINE copy of the rule still agrees with the library --
#      because a second implementation nobody rechecks is how (1) got broken
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/paced-conf.sh"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$LIB" ]    || { echo "library under test not found: $LIB"; exit 1; }
[ -f "$RUNNER" ] || { echo "runner not found: $RUNNER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# --- fixtures ---------------------------------------------------------------
# BOTH: a repo with a host-scoped file for "alpha" and a shared file.
# SHARED_ONLY: no host-scoped file at all.
# NEITHER: a schedule/ dir with no rotation file in it.
mkdir -p "$TMP/both/schedule" "$TMP/shared-only/schedule" "$TMP/neither/schedule"
echo 'a|1|1|/bin/true' > "$TMP/both/schedule/_paced.alpha.conf"
echo 'b|1|1|/bin/true' > "$TMP/both/schedule/_paced.conf"
echo 'b|1|1|/bin/true' > "$TMP/shared-only/schedule/_paced.conf"
echo 'x|1|1|/bin/true' > "$TMP/explicit.conf"

# --- the library ------------------------------------------------------------
# Run each case in its own subshell: resolve_paced_conf honours a PACED_CONF
# already in the environment, so leaking one case's result into the next would
# make every later case pass through the "explicit" branch by accident.
lib_resolve() {  # $1=repo root  $2=PACED_HOST  $3=explicit PACED_CONF ("" for none)
  (
    set +u
    # shellcheck disable=SC1090
    source "$LIB"
    PACED_HOST="$2"
    if [ -n "$3" ]; then PACED_CONF="$3"; else unset PACED_CONF; fi
    resolve_paced_conf "$1"; rc=$?
    echo "rc=$rc conf=${PACED_CONF:-} src=${PACED_CONF_SRC:-}"
  )
}

echo "== lib/paced-conf.sh"
out="$(lib_resolve "$TMP/both" alpha "")"
case "$out" in
  *"rc=0"*"conf=$TMP/both/schedule/_paced.alpha.conf"*"src=host-scoped for alpha"*)
    ok "host-scoped file wins when it exists" ;;
  *) bad "host-scoped file should win -- got: $out" ;;
esac

# The regression itself: a host with no file of its own must NOT be handed
# another host's, and a host WITH one must not be handed the shared one.
out="$(lib_resolve "$TMP/both" beta "")"
case "$out" in
  *"rc=0"*"conf=$TMP/both/schedule/_paced.conf"*"src=shared (no _paced.beta.conf)"*)
    ok "unregistered host falls back to the shared file, and says so" ;;
  *) bad "unregistered host should get the shared file -- got: $out" ;;
esac

out="$(lib_resolve "$TMP/shared-only" alpha "")"
case "$out" in
  *"rc=0"*"conf=$TMP/shared-only/schedule/_paced.conf"*)
    ok "no host-scoped file anywhere -> shared file" ;;
  *) bad "should have used the shared file -- got: $out" ;;
esac

out="$(lib_resolve "$TMP/both" alpha "$TMP/explicit.conf")"
case "$out" in
  *"rc=0"*"conf=$TMP/explicit.conf"*"src=explicit PACED_CONF"*)
    ok "explicit PACED_CONF overrides host resolution" ;;
  *) bad "explicit PACED_CONF should win -- got: $out" ;;
esac

# Refusal, not a comfortable default. rc must be nonzero AND the path empty:
# a caller that ignores rc has to fail on a missing file, not read a guess.
out="$(lib_resolve "$TMP/neither" alpha "")"
case "$out" in
  *"rc=1"*"conf= "*|*"rc=1"*"conf="*"src=NONE"*)
    if [[ "$out" == *"conf= src=NONE"* ]]; then
      ok "no rotation file at all -> refuses loudly, PACED_CONF left empty"
    else
      bad "refusal must leave PACED_CONF empty -- got: $out"
    fi ;;
  *) bad "no rotation file should refuse -- got: $out" ;;
esac

out="$(lib_resolve "" alpha "")"
case "$out" in
  *"rc=1"*) ok "empty repo root refuses" ;;
  *) bad "empty repo root should refuse -- got: $out" ;;
esac

# --- the runner's inline copy -----------------------------------------------
# Lift the runner's block out by its markers and run it as a REAL script, the
# same technique tests/sched-root-witness.sh uses. Extraction failing is a
# FAILURE, never a pass by absence.
echo "== bin/usage-paced-runner.sh inline copy agrees"
BLOCK="$TMP/runner-block.sh"
awk '/^# >>> paced conf resolution/,/^# <<< paced conf resolution/' "$RUNNER" > "$BLOCK"
if ! grep -q 'PACED_CONF_SRC' "$BLOCK"; then
  echo "  FAIL: could not extract the paced-conf block from $RUNNER"
  echo "        (markers '# >>> paced conf resolution' / '# <<<' moved or renamed)"
  exit 1
fi
grep -q '_paced\.\$PACED_HOST\.conf' "$BLOCK" \
  || { echo "  FAIL: extracted block does not mention the host-scoped file"; exit 1; }

runner_resolve() {  # $1=repo root  $2=PACED_HOST  $3=explicit PACED_CONF
  (
    set +u
    REPO_ROOT="$1"; SELF_DIR="$1/bin"; PACED_HOST="$2"
    if [ -n "$3" ]; then PACED_CONF="$3"; else unset PACED_CONF; fi
    # shellcheck disable=SC1090
    source "$BLOCK"
    echo "conf=${PACED_CONF:-} src=${PACED_CONF_SRC:-}"
  )
}

# Compare only the branches BOTH implementations have. The runner carries one
# extra branch the library deliberately does not: PACED_HOST_MODE=1, which
# takes the rotation from schedule/ROSTER over `gh` with no checkout at all
# (bin/usage-paced-runner.sh:328-345). bin/scheduler has no host mode, so
# there is nothing on the library side to compare it against.
#
# CORRECTED 2026-08-29. This used to call that branch "a legacy absolute path
# into mandark's old checkout" -- deleted 2026-08-16 by de1f01c (#230), with
# host mode in its place, so the comment named the wrong rung. The rungs in
# order are asserted in tests/arming-precedence-witness.sh.
for case_spec in "both alpha" "both beta" "shared-only alpha"; do
  set -- $case_spec
  repo="$TMP/$1"; host="$2"
  l="$(lib_resolve    "$repo" "$host" "" | sed 's/^rc=[0-9]* //')"
  r="$(runner_resolve "$repo" "$host" "")"
  if [ "$l" = "$r" ]; then
    ok "runner and library agree for host=$host in $1"
  else
    bad "DRIFT for host=$host in $1: lib[$l] != runner[$r]"
  fi
done

l="$(lib_resolve    "$TMP/both" alpha "$TMP/explicit.conf" | sed 's/^rc=[0-9]* //')"
r="$(runner_resolve "$TMP/both" alpha "$TMP/explicit.conf")"
if [ "$l" = "$r" ]; then ok "runner and library agree on explicit PACED_CONF"
else bad "DRIFT on explicit PACED_CONF: lib[$l] != runner[$r]"; fi

# --- the front door actually uses it ----------------------------------------
# The library could be perfect and bin/scheduler could still hold its old
# hardcoded path. Assert the wiring, not just the part under test.
echo "== bin/scheduler is wired to it"
if grep -q 'source "\$SCHED_ROOT/lib/paced-conf.sh"' "$ROOT/bin/scheduler" \
   && grep -q 'resolve_paced_conf "\$SCHED_ROOT"' "$ROOT/bin/scheduler"; then
  ok "bin/scheduler sources the library and calls the resolver"
else
  bad "bin/scheduler does not use lib/paced-conf.sh -- the fix is not wired in"
fi
if grep -qE '^PACED_CONF="\$SCHED_ROOT/schedule/_paced\.conf"' "$ROOT/bin/scheduler"; then
  bad "bin/scheduler still hardcodes the shared _paced.conf -- the original bug"
else
  ok "bin/scheduler no longer hardcodes the shared rotation file"
fi

echo
echo "paced-conf witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
