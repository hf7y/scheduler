#!/usr/bin/env bash
# freeze-noconfig-witness.sh -- freeze-check tells "released" from "no config".
#
# Found live 2026-08-11, the moment freeze-check.sh started travelling in the
# verb build: the build carries bin/, lib/, man/ and test/ but no schedule/, so
# `dose freeze-check ecosim` on a host with no checkout returned rc=0 (ALLOWED)
# and the emergency abort handle was inert on exactly the hosts it exists to
# stop. The script's own next branch already stated the rule it broke:
# "an abort handle that fails open is not an abort handle."
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/../bin/freeze-check.sh"
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }
echo "freeze-noconfig-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# --- 1. RELEASED: schedule/ exists, FREEZE does not -> allowed -------------
# `git rm` on FREEZE is the documented way to lift a freeze, so this must keep
# returning 0. A fix that made every absent file refuse would break the release
# path instead of the fail-open, which is the easy wrong answer here.
mkdir -p "$W/released/schedule"
SCHEDULER_FREEZE_FILE="$W/released/schedule/FREEZE" bash "$F" ecosim >/dev/null 2>&1
[ $? -eq 0 ] && ok "released (schedule/ present, FREEZE removed) is still ALLOWED" \
  || bad "a released freeze now refuses -- git rm is the documented release path"

# --- 2. NO LOCAL CONFIG, GITHUB REACHABLE -> a real verdict, not a refusal --
# hf7y/scheduler#124 changed this deliberately. Before it, no schedule/ meant
# exit 2 (refuse) because the copy could not tell released from missing. Now it
# falls through to schedule/FREEZE on GitHub and answers from the real file, so
# a build-resident freeze-check is USEFUL rather than merely safe.
#
# The assertion is on the SHAPE, not the value: whether the live FREEZE happens
# to freeze ecosim today depends on this host and on EXEMPT lines, and a test
# that pinned the value would go red the next time a human edits the roster.
# What must hold is that it produced a verdict at all rather than refusing for
# want of config.
out="$(SCHEDULER_FREEZE_FILE="$W/nothing/schedule/FREEZE" SCHEDULER_FREEZE_CACHE="$W/cache-live" \
       bash "$F" ecosim 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
  ok "no local config + reachable GitHub yields a real verdict (rc=$rc), not a want-of-config refusal"
elif [ "$rc" -eq 2 ]; then
  # Only legitimate if this box genuinely cannot reach GitHub right now.
  if gh auth status >/dev/null 2>&1; then
    bad "refused with 2 while gh is authenticated -- the remote fallback is not working"
  else
    echo "  SKIP: gh unauthenticated here, cannot exercise the reachable case"
  fi
else
  bad "unexpected rc=$rc from the remote fallback: $out"
fi

# --- 3. FROZEN still frozen ------------------------------------------------
mkdir -p "$W/frozen/schedule"
printf 'migration wave 1 rollback\n' > "$W/frozen/schedule/FREEZE"
SCHEDULER_FREEZE_FILE="$W/frozen/schedule/FREEZE" bash "$F" ecosim >/dev/null 2>&1
[ $? -eq 1 ] && ok "a real freeze still refuses (exit 1)" || bad "a populated FREEZE no longer freezes"

# --- 4. EXEMPT still exempts ----------------------------------------------
printf 'wave 1\nEXEMPT: ecosim@%s\n' "$(hostname -s)" > "$W/frozen/schedule/FREEZE"
SCHEDULER_FREEZE_FILE="$W/frozen/schedule/FREEZE" bash "$F" ecosim >/dev/null 2>&1
[ $? -eq 0 ] && ok "a host-scoped EXEMPT line still lets its project through" \
  || bad "exemptions broke -- the freeze is now all-or-nothing"

# --- 5. not vacuous --------------------------------------------------------
# Prove case 2 fails if the guard is removed: an existing dir with no FREEZE
# must NOT take the refuse path, or the guard is just refusing everything.
mkdir -p "$W/released2/schedule"
SCHEDULER_FREEZE_FILE="$W/released2/schedule/FREEZE" bash "$F" ecosim >/dev/null 2>&1
[ $? -eq 0 ] && ok "the new refusal is targeted, not blanket" || bad "the guard refuses even with schedule/ present"

# --- 6. NO LOCAL CONFIG, GITHUB UNREACHABLE -> still refuses, with the RIGHT
# code. hf7y/scheduler#124 lets freeze-check fall through to GitHub when there
# is no schedule/ at all. The fallback must not weaken the refusal, and it must
# refuse with freeze-check's own 2 rather than leaking the fetcher's 6 -- which
# it did until lib/dose-common.sh stopped exiting its caller.
out="$(SCHEDULER_FREEZE_FILE="$W/nothing/schedule/FREEZE" SCHEDULER_FREEZE_CACHE="$W/cache-unreach" \
       DOSE_GH_BIN=/nonexistent bash "$F" ecosim 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "no config + unreachable GitHub refuses with 2 (not the fetcher's 6)" \
  || bad "expected 2, got $rc -- a library exit code is leaking through the contract: $out"
grep -qi 'could not be read from GitHub' <<<"$out" \
  && ok "the refusal says the remote was tried too" || bad "does not mention the remote attempt: $out"

# --- 7. FILESYSTEM WINS OVER GITHUB ---------------------------------------
# The ordering is the safety property: an operator at the machine with no
# network must still be able to stop it. A local FREEZE must never be
# overridden by a remote read.
mkdir -p "$W/localwins/schedule"
printf 'local emergency stop\n' > "$W/localwins/schedule/FREEZE"
SCHEDULER_FREEZE_FILE="$W/localwins/schedule/FREEZE" SCHEDULER_FREEZE_CACHE="$W/cache-lw" \
  bash "$F" ecosim >/dev/null 2>&1
[ $? -eq 1 ] && ok "a local FREEZE still freezes, without consulting GitHub" \
  || bad "a local freeze was overridden -- the operator at the machine lost"

printf '\nfreeze-noconfig-witness: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
