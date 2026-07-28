#!/usr/bin/env bash
# check-witness-lint.sh -- "this check exists; nothing has run it since <date>."
#
# Built 2026-07-28 (paced cycle), FOCUS.md Backlog step 1b. The reader half
# of lib/check-witness.sh -- read that file first, it carries the WHY.
#
# For every check in bin/ (`*-check.sh`, `*-lint.sh`), compare its runtime
# witness under $CHECK_WITNESS_DIR against now:
#   OK        -- witness written within CHECK_WITNESS_STALE_DAYS
#   STALE     -- witness exists but is older than that: it WAS wired and
#                something silently unwired it (a deleted sweep pass)
#   NEVER RUN -- no witness at all: built and committed, never called
#
# Deliberately NOT static analysis: grep proves a check is mentioned, not
# that it runs. See lib/check-witness.sh.
#
# Run this LAST in a sweep, after the passes that invoke the other checks --
# they touch their witnesses on the way through, so a genuinely wired check
# is never reported stale by the same sweep that just ran it.
#
# Exit: 0 clean, 1 findings, 3 BLIND (no bin/ to scan, or an unreadable
# witness dir -- "could not look" is never reported as "nothing wrong",
# the lesson blockers-freshness-check.sh paid for).
set -uo pipefail

SCHED_ROOT="${SCHED_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# The lib is the ONE source for the witness dir and the touch semantics, so
# without it this reader has nothing to read and must say so -- half-running
# against a guessed path is how a checker comes back falsely clean.
if [ ! -r "$SCHED_ROOT/lib/check-witness.sh" ]; then
  echo "BLIND: cannot read $SCHED_ROOT/lib/check-witness.sh -- no witness dir to check"
  exit 3
fi
# shellcheck disable=SC1091
source "$SCHED_ROOT/lib/check-witness.sh"

# Grace period. Every check here is wired into `scheduler sweep`, which runs
# every 15 minutes, so anything past a day is not a scheduling wobble -- it
# means nothing is calling it. Generous enough to survive a machine being
# off over a weekend without crying wolf.
STALE_DAYS="${CHECK_WITNESS_STALE_DAYS:-2}"

# This check is itself a check: leave a witness, so an unwired
# check-witness-lint is caught by the next one to run. First act -- which
# also means it never reports ITSELF as stale, correctly: it is running.
check_witness "$(basename "${BASH_SOURCE[0]}")"

findings=0
blind=0
scanned=0
now="$(date +%s)"

if [ ! -d "$SCHED_ROOT/bin" ]; then
  echo "BLIND: no bin/ under $SCHED_ROOT -- cannot enumerate checks"
  exit 3
fi
if [ -e "$CHECK_WITNESS_DIR" ] && [ ! -r "$CHECK_WITNESS_DIR" ]; then
  echo "BLIND: witness dir exists but is not readable ($CHECK_WITNESS_DIR)"
  exit 3
fi

shopt -s nullglob
for script in "$SCHED_ROOT"/bin/*-check.sh "$SCHED_ROOT"/bin/*-lint.sh; do
  name="$(basename "$script")"
  scanned=$((scanned + 1))
  witness="$CHECK_WITNESS_DIR/$name.lastrun"

  if [ ! -f "$witness" ]; then
    echo "NEVER RUN: $name -- built, but no runtime witness has ever been written"
    echo "    nothing calls it, or its call site never executes (grep cannot tell those apart)"
    findings=$((findings + 1))
    continue
  fi

  # Belt and braces: a witness that passed `-f` above but whose mtime still
  # cannot be read isn't reachable in normal use (a dangling symlink already
  # falls out as NEVER RUN). It exists so an odd filesystem reports BLIND
  # rather than being silently treated as fresh.
  mtime="$(date -r "$witness" +%s 2>/dev/null)" || mtime=""
  if [ -z "$mtime" ]; then
    echo "BLIND: $name -- witness exists but its mtime is unreadable ($witness)"
    blind=1
    continue
  fi

  age_days=$(( (now - mtime) / 86400 ))
  if [ "$age_days" -ge "$STALE_DAYS" ]; then
    echo "STALE: $name -- last ran $(date -r "$witness" '+%Y-%m-%d %H:%M') (${age_days}d ago, limit ${STALE_DAYS}d)"
    echo "    it WAS wired and no longer is -- look for a deleted sweep pass"
    findings=$((findings + 1))
  fi
done
shopt -u nullglob

if [ "$scanned" -eq 0 ]; then
  echo "BLIND: matched no bin/*-check.sh or bin/*-lint.sh under $SCHED_ROOT"
  echo "  (that is a wiring/glob failure, NOT a clean result)"
  exit 3
fi

echo "== summary: $findings finding(s) across $scanned check(s), witnesses in $CHECK_WITNESS_DIR =="
[ "$blind" -eq 1 ] && exit 3
[ "$findings" -gt 0 ] && exit 1
exit 0
