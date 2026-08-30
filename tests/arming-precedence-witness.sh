#!/usr/bin/env bash
# arming-precedence-witness.sh -- WHICH SURFACE DECIDES that a project
# dispatches, and IN WHAT ORDER. #79 (auto-closed by a negation in #180),
# #282 (the remainder), #364 (the deletion this order gates).
#
# Other witnesses cover the rungs one at a time -- paced-conf-witness.sh,
# paced-roster-authority-witness.sh, sync-crontab-paced-witness.sh. The LADDER
# is what rots, because it is spread over four files that each state only
# their own rung. It is not restated here: run this file and the assertions
# print it, which is the point of pinning an order rather than describing one.
#
# Case 5 pins a DEFECT deliberately -- read its own comment before "fixing".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
LIB="$ROOT/lib/paced-conf.sh"
[ -f "$RUNNER" ] && [ -f "$LIB" ] || { echo "code under test not found under $ROOT"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# with_lib <repo-root> <fn> <var> -- run one lib/paced-conf.sh entry point
# against a fixture and print the variable it set. Subshell per call: both
# entry points honour a PACED_CONF already in the environment, so a leak would
# put later cases through the "explicit" branch by accident.
with_lib() {
  (
    set +u
    # shellcheck disable=SC1090  # $LIB is $ROOT/lib/paced-conf.sh, resolved
    # above; a literal here would be a second definition of that path.
    source "$LIB"
    PACED_HOST=h; unset PACED_CONF
    "$2" "$1" >/dev/null
    printf '%s' "${!3}"
  )
}

# --- 1. the rotation-source ladder, IN ORDER --------------------------------
# Branch conditions read out of the runner's marked block in file order. A
# reordering changes what an armed host dispatches from and nothing else.
echo "== 1. which file supplies the rotation"
BLOCK="$TMP/block.sh"
awk '/^# >>> paced conf resolution/,/^# <<< paced conf resolution/' "$RUNNER" > "$BLOCK"
grep -q 'PACED_CONF_SRC' "$BLOCK" \
  || { bad "could not extract the paced-conf block from the runner -- nothing below tested the ladder"; echo; exit 1; }

mapfile -t RUNGS < <(grep -oE '^(el)?if \[ .*\]; then' "$BLOCK" | sed 's/^\(el\)\?if \[ //;s/ \]; then$//')
EXPECT=(
  '-n "${PACED_CONF:-}"'
  '"$PACED_HOST_MODE" = 1'
  '-f "$REPO_ROOT/schedule/_paced.$PACED_HOST.conf"'
  '-f "$REPO_ROOT/schedule/_paced.conf"'
)
if [ "${#RUNGS[@]}" -eq "${#EXPECT[@]}" ]; then
  ok "the ladder still has ${#EXPECT[@]} rungs before the refusal"
else
  bad "the ladder has ${#RUNGS[@]} rung(s), expected ${#EXPECT[@]}: ${RUNGS[*]}"
fi
for i in "${!EXPECT[@]}"; do
  if [ "${RUNGS[$i]:-}" = "${EXPECT[$i]}" ]; then
    ok "rung $((i+1)): ${EXPECT[$i]}"
  else
    bad "rung $((i+1)) is '${RUNGS[$i]:-<missing>}', expected '${EXPECT[$i]}'"
  fi
done
grep -qE '^\s*exit 2$' "$BLOCK" \
  && ok "the last rung is a refusal, not a default" \
  || bad "the block no longer refuses when no rotation file resolves -- a guessed default arms nothing or everything"

# --- 2. _paced.conf is UNREAD as a fallback here, and READ as membership ----
# "Not the fallback tier on this host" is not "unread". #364 gates the deletion
# on host mode; this pins the second read so it cannot be argued from the first.
echo "== 2. the shared schedule/_paced.conf on a host that has its own"
mkdir -p "$TMP/repo/schedule"
printf 'alpha|1|1|/bin/true\n' > "$TMP/repo/schedule/_paced.h.conf"
printf 'beta|0|1|/bin/true\n'  > "$TMP/repo/schedule/_paced.conf"
out="$(with_lib "$TMP/repo" resolve_paced_conf PACED_CONF)"
[ "$out" = "$TMP/repo/schedule/_paced.h.conf" ] \
  && ok "liveness resolves to the host-scoped file, never the shared one" \
  || bad "resolve_paced_conf gave '$out', expected the host-scoped file"
out="$(with_lib "$TMP/repo" paced_membership_set PACED_MEMBERS)"
case "$out" in
  *" beta "*) ok "membership STILL reads the shared file (union glob, lib/paced-conf.sh:133)" ;;
  *) bad "the shared file dropped out of the membership union -- got '$out'" ;;
esac

# --- 3. FREEZE is not a liveness surface ------------------------------------
# A global abort handle with two dispatch call sites; its file has not existed
# since 6487c9ec. Reintroducing it as a per-project arming decision is the
# fourth opinion #79 exists to prevent.
echo "== 3. schedule/FREEZE"
[ -e "$ROOT/schedule/FREEZE" ] \
  && bad "schedule/FREEZE is back -- it was deleted 2026-08-20; a liveness registry beside ROSTER is exactly #79's defect" \
  || ok "schedule/FREEZE does not exist in the tree"
for fn in roster_state_for participant_enabled roster_rows; do
  if sed -n "/^$fn() {/,/^}/p" "$RUNNER" | grep -q FREEZE; then
    bad "$fn() reads FREEZE -- liveness must come from ROSTER and the rotation row, nothing else"
  else
    ok "$fn() does not consult FREEZE"
  fi
done
n=0
for f in "$RUNNER" "$ROOT/bin/scheduler-run"; do
  n=$(( n + $(grep -c 'freeze-check\.sh"' "$f" 2>/dev/null || echo 0) ))
done
[ "$n" -eq 2 ] \
  && ok "freeze-check is called at exactly the 2 dispatch sites, as an abort handle" \
  || bad "freeze-check has ${n:-0} dispatch call site(s), expected 2 -- the abort handle's blast radius changed"

# --- 4. membership is not arming, which is why dose writes two files --------
# `dose <p> --arm/--park` (bin/dose-project.sh:158-170) writes ROSTER AND
# _paced.<host>.conf on one branch. ROSTER alone cannot do it: a fixed nightly
# line is suppressed by the ROW existing, and ROSTER is not in that glob.
echo "== 4. membership (fixed-line suppression) vs arming (dispatch)"
grep -qE '^\s*for f in "\$repo_root"/schedule/_paced\.conf "\$repo_root"/schedule/_paced\.\*\.conf; do' "$LIB" \
  && ok "the membership glob names _paced*.conf only -- ROSTER cannot suppress a fixed line" \
  || bad "the membership glob changed; if ROSTER is now in it, dose's two-file write is the thing to collapse next"
printf 'alpha | alpha@h | 20m | parked\n' > "$TMP/repo/schedule/ROSTER"
out="$(with_lib "$TMP/repo" paced_membership_set PACED_MEMBERS)"
case "$out" in
  *" alpha "*) ok "a row ROSTER calls parked is still a member -- parking does not re-arm a fixed cron line" ;;
  *) bad "parking in ROSTER dropped 'alpha' from membership, which ARMS its fixed nightly line (the #79 trap)" ;;
esac
grep -q 'write_repo_file "\$PACED_REL"' "$ROOT/bin/dose-project.sh" \
  && ok "dose --arm/--park still writes both files, matching the split above" \
  || bad "dose no longer writes the paced conf -- either the split collapsed (good, update this witness) or arming is now half-applied"

# --- 5. DEFECT, PINNED: host mode re-reads the checkout it exists to avoid --
# Host mode fetches ROSTER over gh and refuses to "fall back to a checkout"
# (bin/usage-paced-runner.sh:334-341) -- then participant_enabled calls
# roster_state_for, which reads $REPO_ROOT/schedule/ROSTER (:280), REPO_ROOT
# being the script's own tree (:55), fetch or no fetch. A local `live` beats a
# fetched `parked`: the stale-clone dependency the mode exists to remove.
#
# One-line fix, for whoever owns the runner: host mode should set
# SCHEDULER_ROSTER_FILE at the fetch (:280 honours it; nothing sets it today)
# so both reads come from the same bytes. IF YOU FIXED IT, invert these cases.
echo "== 5. host mode vs a local checkout's ROSTER (defect, pinned as observed)"
eval "$(sed -n '/^roster_rows() {/,/^}/p'        "$RUNNER")"
eval "$(sed -n '/^roster_state_for() {/,/^}/p'   "$RUNNER")"
eval "$(sed -n '/^participant_enabled() {/,/^}/p' "$RUNNER")"
declare -F roster_rows >/dev/null && declare -F participant_enabled >/dev/null \
  || { bad "could not extract the roster functions -- case 5 tested nothing"; echo; exit 1; }

mkdir -p "$TMP/stale/schedule"
printf 'p | p@h | 20m | live\n' > "$TMP/stale/schedule/ROSTER"   # the checkout: stale
PACED_HOST=h
row="$(printf 'p | p@h | 20m | parked\n' | roster_rows)"          # the fetch: parked
enabled="$(printf '%s' "$row" | cut -d'|' -f2)"
[ "$enabled" = 0 ] \
  && ok "the gh fetch materialises a parked row as enabled=0" \
  || bad "roster_rows gave enabled='$enabled' for a parked row, expected 0"

REPO_ROOT="$TMP/stale"
participant_enabled p "$enabled" h \
  && ok "OBSERVED: a stale local ROSTER saying live overrides the fetched parked row (the defect)" \
  || bad "the local ROSTER no longer wins -- if you fixed this, invert this case and case 5b"
REPO_ROOT="$TMP/stale/no-checkout-here"
participant_enabled p "$enabled" h \
  && bad "with no local ROSTER the fetched parked row must decide, and it did not" \
  || ok "with no checkout at all, the fetched parked row decides correctly"

printf '\narming-precedence-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
