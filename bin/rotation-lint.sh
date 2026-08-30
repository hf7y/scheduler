#!/usr/bin/env bash
# rotation-lint.sh -- one project, one dispatcher, ACROSS the host split.
#
# Built 2026-07-29 (paced cycle, dexter). RETIRES a PROSE CONVENTION, not a
# mechanism -- there was no mechanism. `schedule/_paced.conf` and
# `schedule/_paced.<host>.conf` both carry the rule in capitals, four times
# between them:
#
#   "DO NOT LAND THIS ALONE"                     (_paced.conf, crt block)
#   "in the SAME change"                         (dexter wtul block, step 5)
#   "PAIRED, NOT LANDED ALONE"                   (dexter realisateur block)
#   "Both halves, or the double-dispatch comes back."
#
# Every host move is a two-file edit -- enable here, disable there -- and
# until now the ONLY thing holding the two halves together was whoever was
# editing remembering to do both. This repo's own doctrine says a convention
# nobody can enforce is a latent bug; two participants were moved by hand on
# 2026-07-29 alone (`c369c05`, `58d6495`), so the exposure is current, not
# historical.
#
# WHAT SPLIT INTENT COSTS, so this reads as a defect and not as tidiness:
# each host runs bin/usage-paced-runner.sh out of the same git-tracked repo
# but reads its OWN rotation file. Until #364 the `enabled` column armed the
# dispatch, so a project enabled in two of them was dispatched by two machines
# into one git history with no shared lock (decided 2026-07-24: full local
# peer, no cross-host rotation). It arms nothing now -- participant_enabled
# takes <name> <host> and asks schedule/ROSTER, full stop -- so finding 1 is
# two files stating opposite INTENT, caught before anyone copies the
# disagreement into ROSTER; the dispatching kind is two `live` ROSTER rows for
# one project, which is ROSTER's own shape and not visible here. Finding 2
# survives intact, because pooling is still per LINE. The same hazard on the
# FIXED-CRON side is confirmed live rather than theoretical -- see the
# aedile/vkv-inventory notes in `_paced.conf` -- and bin/sync-crontab.sh
# asserts it there. These files go in #364, and this lint goes with them.
#
# Checks (both are zero-false-positive -- there is no legitimate reason for
# either, which is what makes them safe to run every sweep):
#   1. a project enabled=1 in MORE THAN ONE rotation file
#      -- two files stating opposite intent about one project;
#   2. a project listed MORE THAN ONCE in the SAME rotation file
#      -- if several are live in ROSTER, that is same-host double dispatch (the
#      runner has no dedup: it pools every line ROSTER calls live); if only
#      one is, the other is a shadowed line that will bite the next edit,
#      because "flip the wtul line" is then ambiguous.
#
# WHAT IS DELIBERATELY *NOT* CHECKED: "enabled in NO rotation file", the
# other way a paired edit can go wrong (`_paced.dexter.conf`'s wtul block
# calls it the "runs NOWHERE" hazard and says it has been live since
# 2026-07-25). It is not mechanizable without noise: parked-on-purpose and
# lost-in-a-move are the same bytes, and ~10 projects sit deliberately at
# `|0|` in `_paced.conf` today. A check that FLAGs ten intentional parks to
# catch one accident trains the reader to skip it -- the exact failure
# bin/questions-lint.sh's header describes and that `7d3ba04` had to undo.
# Parked-vs-lost stays a judgment call, recorded in the conf blocks.
#
# NOT affected by an explicit PACED_CONF in the environment, unlike
# resolve_paced_conf / paced_membership_set. The question here is inherently
# "across every rotation file"; honoring an override that pins one file
# would make the check pass vacuously in exactly the setup it exists for.
# Point it at a different tree with SCHED_ROOT instead.
#
# Exit: 0 clean, 1 findings, 3 BLIND (no rotation file to read at all --
# "could not look" is never reported as "nothing wrong", the lesson
# bin/blockers-freshness-check.sh paid for).
set -uo pipefail

SCHED_ROOT="${SCHED_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Runtime witness -- record that this check actually RAN, so a
# built-but-unwired check fails loud in `scheduler sweep` instead of looking
# clean (lib/check-witness.sh + bin/check-witness-lint.sh). First act, before
# any early exit: a check that came back BLIND still ran. Never fatal.
if [ -r "$SCHED_ROOT/lib/check-witness.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCHED_ROOT/lib/check-witness.sh"
  check_witness "$(basename "${BASH_SOURCE[0]}")"
fi

SCHEDULE_DIR="$SCHED_ROOT/schedule"

shopt -s nullglob
FILES=()
[ -f "$SCHEDULE_DIR/_paced.conf" ] && FILES+=("$SCHEDULE_DIR/_paced.conf")
for f in "$SCHEDULE_DIR"/_paced.*.conf; do
  [ -f "$f" ] && FILES+=("$f")
done
shopt -u nullglob

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "BLIND: no schedule/_paced*.conf under $SCHEDULE_DIR -- nothing to compare"
  echo "  (that is a wiring/path failure, NOT a clean result)"
  exit 3
fi

# host_label <path> -- how a finding names the file. `_paced.conf` is the
# shared default: it is live on EVERY host that has no file of its own
# (mandark, today), so it is treated as a real rotation rather than as a
# fallback that might be read by nobody. That direction is the safe one --
# it can over-report a collision, never miss one.
host_label() {
  local base; base="$(basename "$1")"
  case "$base" in
    _paced.conf) echo "shared/default" ;;
    _paced.*.conf) base="${base#_paced.}"; echo "${base%.conf}" ;;
    *) echo "$base" ;;
  esac
}

findings=0
lines_scanned=0

# name -> "label:line label:line ..." for enabled entries, across all files.
declare -A ENABLED_AT=()
# "file<TAB>name" -> occurrence count, within one file.
declare -A SEEN_IN_FILE=()
declare -A DUP_REPORTED=()

for f in "${FILES[@]}"; do
  label="$(host_label "$f")"
  lineno=0
  # `|| [ -n "$name" ]` so a final line with no trailing newline is still read
  # -- `read` returns non-zero on EOF even when it filled the variables, and a
  # lint that silently skips the last line of a file is worse than no lint.
  while IFS='|' read -r name enabled _rest || [ -n "$name" ]; do
    lineno=$((lineno + 1))
    # Mirror bin/usage-paced-runner.sh's own parse EXACTLY, in both order and
    # form -- the comment test runs BEFORE whitespace is stripped, so a line
    # indented with a space is a live participant while `# name|1|...` is not.
    # tests/rotation-lint-witness.sh asserts this predicate still matches the
    # dispatcher's; the shared `enabled` test it also mirrored was cut with
    # the arming surface it mirrored (#364).
    case "$name" in ''|\#*) continue ;; esac
    name="${name// /}"
    [ -n "$name" ] || continue
    lines_scanned=$((lines_scanned + 1))

    key="$f	$name"
    SEEN_IN_FILE["$key"]=$(( ${SEEN_IN_FILE["$key"]:-0} + 1 ))
    if [ "${SEEN_IN_FILE[$key]}" -gt 1 ] && [ -z "${DUP_REPORTED[$key]:-}" ]; then
      DUP_REPORTED["$key"]=1
      echo "$(basename "$f"):$lineno: DUPLICATE '$name' is listed more than once in this file"
      echo "    Every copy is pooled separately by bin/usage-paced-runner.sh (it does not"
      echo "    dedup), so if schedule/ROSTER calls '$name' live both copies dispatch on this"
      echo "    host alone. The next 'flip the $name line' is ambiguous either way."
      echo "    Delete the stale copy."
      findings=$((findings + 1))
    fi

    [ "${enabled// /}" = "1" ] || continue
    ENABLED_AT["$name"]="${ENABLED_AT[$name]:-}${ENABLED_AT[$name]:+ }$label:$lineno"
  done < "$f"
done

# Sorted: bash iterates an associative array in hash order, and a check whose
# output reshuffles between identical runs is one a reader cannot diff.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  # shellcheck disable=SC2206
  where=(${ENABLED_AT[$name]})
  [ "${#where[@]}" -gt 1 ] || continue
  echo "SPLIT INTENT: '$name' is enabled=1 in ${#where[@]} rotations -- ${where[*]}"
  echo "    That column stopped arming anything (#364): schedule/ROSTER's state decides."
  echo "    So this dispatches nothing today -- it is two files claiming one project, and"
  echo "    the next reader will believe whichever they open. Set enabled 0 everywhere but"
  echo "    the host that owns it, in ONE change ('PAIRED, NOT LANDED ALONE'), and check"
  echo "    schedule/ROSTER has no second live row for '$name' -- that is the dispatching kind."
  findings=$((findings + 1))
done < <(printf '%s\n' "${!ENABLED_AT[@]}" | sort)

echo "== summary: $findings finding(s) across $lines_scanned participant line(s) in ${#FILES[@]} rotation file(s) =="
[ "$findings" -gt 0 ] && exit 1
exit 0
