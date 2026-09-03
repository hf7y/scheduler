#!/usr/bin/env bash
# roster-participants-witness.sh -- host mode takes its participants from
# schedule/ROSTER, not from a checkout's _paced.<host>.conf.
#
# This is the last coupling that forced a scheduler clone to exist on a
# dispatch host. Zach, 2026-08-11: "scheduler should not need to exist as a
# check out on monkey for the verbs to work."
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "roster-participants-witness"

# roster_rows is a function so it can be tested; pull it out rather than run
# the whole dispatcher.
eval "$(sed -n '/^roster_rows() {/,/^}/p' "$R")"
declare -F roster_rows >/dev/null && ok "roster_rows extracted" \
  || { bad "could not extract roster_rows -- nothing below tested anything"; echo; exit 1; }

PACED_HOST=testhost
ROSTER='# a comment
alpha   | alpha@testhost   | 6h | live
beta    | beta@testhost    | 1h | parked
gamma   | gamma@otherhost  | 6h | live

delta   | delta@testhost   | 6h | live'

out="$(printf '%s\n' "$ROSTER" | roster_rows)"

grep -q '^alpha|1|/home/alpha/Documents/Projects/scheduler/bin/scheduler-run alpha batch$' <<<"$out" \
  && ok "a live row becomes enabled=1 with the account's own command" || bad "live row wrong: $out"
grep -q '^beta|0|' <<<"$out" && ok "a parked row becomes enabled=0, not omitted" \
  || bad "parked row missing or wrong -- omitting it would ARM it (_paced.conf TRAP 1)"
grep -q 'gamma' <<<"$out" && bad "a row for another host leaked in" \
  || ok "a row naming another host is excluded"
grep -q '^delta|1|' <<<"$out" && ok "a row after a blank line still parses" || bad "blank line ate a row"
[ "$(grep -c . <<<"$out")" -eq 3 ] && ok "exactly 3 rows for this host" \
  || bad "got $(grep -c . <<<"$out") rows, want 3"

# NOT VACUOUS: the parked case is the one that matters. _paced.conf's TRAP 1 is
# that DELETING a row arms a fixed nightly cron, so a translation that dropped
# parked projects would arm every paused one. Prove the row is present AND off.
printf '%s\n' "$out" | awk -F'|' '$1=="beta" && $2=="0"{f=1} END{exit !f}' \
  && ok "beta is present and disabled, not silently dropped" || bad "beta not represented as disabled"

# --- the refusals, read from source (they need root+gh to fire) ------------
grep -q 'Refusing to dispatch rather than fall back to a checkout' "$R" \
  && ok "an unreadable roster refuses instead of falling back to a clone" \
  || bad "the fall-back-to-checkout refusal is GONE -- host mode could silently re-acquire the clone dependency"
grep -q 'an empty rotation is indistinguishable from a parse failure' "$R" \
  && ok "an empty roster is a refusal, not a quiet no-op" || bad "empty-roster refusal missing"

printf '\nroster-participants-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
