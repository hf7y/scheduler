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

# --- 2. NO CONFIG: no schedule/ directory at all -> refuse -----------------
out="$(SCHEDULER_FREEZE_FILE="$W/nothing/schedule/FREEZE" bash "$F" ecosim 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "no schedule/ directory REFUSES (exit 2), it does not guess" \
  || bad "absent config returned $rc, want 2 -- the abort handle is inert"
grep -qi 'no config' <<<"$out" && ok "the refusal names the cause" || bad "refused without saying why: $out"
grep -qi 'cannot tell a released freeze from a missing one' <<<"$out" \
  && ok "it states the distinction it could not make" || bad "no explanation of the ambiguity: $out"

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

printf '\nfreeze-noconfig-witness: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
