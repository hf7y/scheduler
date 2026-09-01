#!/usr/bin/env bash
# sprint-witness.sh -- a sprint bypasses the PACE hold and NOTHING else (#292).
# One outliving its expiry, or releasing USAGE_CEILING, is the override #292
# exists to kill. The expiry and ceiling cases are the load-bearing ones.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
D="$HERE/../bin/dose-project.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "sprint-witness"

eval "$(sed -n '/^sprint_active() {/,/^}/p' "$R")"
eval "$(sed -n '/^gate_hold_is_pace_only() {/,/^}/p' "$R")"
declare -F sprint_active >/dev/null && ok "sprint_active extracted" \
  || { bad "could not extract sprint_active -- nothing below tested anything"; echo; exit 1; }
declare -F gate_hold_is_pace_only >/dev/null && ok "gate_hold_is_pace_only extracted" \
  || { bad "could not extract gate_hold_is_pace_only -- nothing below tested anything"; echo; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STATE_DIR="$TMP"; SPRINT_FILE="$TMP/sprint"; SPRINT_UNTIL=""

sprint_active && bad "no marker at all read as a live sprint" \
  || ok "no marker is not a sprint"

date -d '+1 hour' -Is > "$SPRINT_FILE"
sprint_active && [ -n "$SPRINT_UNTIL" ] && ok "a future expiry is a live sprint, and it reports the wall time" \
  || bad "a future expiry did not register as a sprint"

date -d '-1 minute' -Is > "$SPRINT_FILE"
sprint_active && bad "an EXPIRED sprint still bypasses -- 'temporary' just became permanent" \
  || ok "an expired marker is not a sprint"

: > "$SPRINT_FILE"
sprint_active && bad "an empty marker read as a sprint" || ok "an empty marker is not a sprint"

echo 'not a date' > "$SPRINT_FILE"
sprint_active && bad "an unparseable marker read as a sprint" \
  || ok "an unparseable marker is not a sprint (fails closed)"

gate_hold_is_pace_only 'verdict=HOLD
hold_reasons=7d:on-pace' \
  && ok "a pure on-pace hold is sprintable" \
  || bad "an on-pace hold was not recognised -- a sprint would never release anything"

gate_hold_is_pace_only 'verdict=HOLD
hold_reasons=5h:ceiling' \
  && bad "A CEILING HOLD WAS SPRINTABLE -- #292 says pacing only, never USAGE_CEILING" \
  || ok "a ceiling hold is NOT sprintable"

gate_hold_is_pace_only 'verdict=HOLD
hold_reasons=7d:on-pace;5h:ceiling' \
  && bad "a mixed hold was sprintable because ONE window was merely on-pace" \
  || ok "on-pace + ceiling together is NOT sprintable -- every window must be pace-only"

gate_hold_is_pace_only 'verdict=HOLD
hold_reasons=7d:rejected' \
  && bad "a 'rejected' window was sprintable" || ok "a rejected window is NOT sprintable"

gate_hold_is_pace_only 'verdict=HOLD' \
  && bad "a verdict naming no hold_reasons was sprintable" \
  || ok "a verdict with no hold_reasons at all is NOT sprintable (fails closed)"

grep -q 'rc" -eq 1 \] && sprint_active && gate_hold_is_pace_only' "$R" \
  && ok "the gate branch requires rc=1 AND a live sprint AND a pace-only hold" \
  || bad "the gate branch no longer conjoins all three -- re-derive this witness"
grep -q 'elif sprint_active; then' "$R" \
  && ok "tempo is bypassed by a sprint too (pace is one decision with two brakes)" \
  || bad "a sprint releases the gate but still stops at tempo -- it buys nothing"
grep -q 'SPRINT (expires' "$R" \
  && ok "every sprinting tick says so in the log, with its expiry" \
  || bad "a sprint is silent -- #292 requires it loud on every tick"

grep -q 'SPRINT_FILE="\$STATE_DIR/sprint"' "$R" \
  && ok "the marker lives in STATE_DIR, not schedule/ (which would REFUSE the tick it meant to release)" \
  || bad "the sprint marker moved -- check it is not under schedule/"

out="$(bash "$D" --sprint-status extra-project 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "--sprint-status with a project is a usage error" \
  || bad "--sprint-status accepted a project (rc=$rc): $out"

out="$(bash "$D" someproj --sprint 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "--sprint with no duration is a usage error, not a silent forever" \
  || bad "--sprint accepted a missing duration (rc=$rc): $out"

bash "$D" --help 2>&1 | grep -q -- '--sprint <dur>' \
  && ok "--help documents --sprint" || bad "--sprint is undocumented in --help"
bash "$D" --help 2>&1 | grep -qi 'CEILING is never bypassed' \
  && ok "--help says the ceiling is never bypassed" \
  || bad "--help does not say the ceiling still holds -- that is the one thing a user must know"

printf '\nsprint-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
