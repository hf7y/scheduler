#!/usr/bin/env bash
# run-ledger.sh -- one append-only line per dispatch. Never consumed, never
# rewritten.
#
# WHY IT HAS TO EXIST BEFORE ANY BRAKE. bin/verdict.sh CONSUMES the verdict at
# dispatch (`verdict.sh clear`, usage-paced-runner.sh:604), so no verdict
# outlives its own run. That makes "the same blocker twice" not merely
# unimplemented but STRUCTURALLY UNOBSERVABLE -- you cannot detect repetition
# when each observation is deleted before the next arrives. hf7y/scheduler#54:
# "the missing piece is not another sensor. It is an append-only ledger."
#
# WHAT IT IS FOR. On 2026-08-06 DONE was recorded nine times across four
# accounts in one day and never once stopped a dispatch; bibliothecaire
# recorded DONE on six consecutive runs and was re-dispatched every time. Every
# project's brief tells the agent DONE means "the bar in my brief is met; stop
# dispatching". That was false, which is worse than not asking -- the agents
# spend turns producing a signal the system discards.
#
# APPEND-ONLY IS THE WHOLE CONTRACT. There is no update, no delete, no rotate.
# A single printf of one line under PIPE_BUF (4096 on Linux) is atomic, so
# concurrent dispatchers cannot interleave a row. Size is bounded by reality
# rather than by policy: at 60 dispatches/day a year is ~22k lines.
#
# Sourced, never executed. No top-level statement runs anything -- the same
# rule bin/lib/dose-common.sh learned the hard way when it exited its callers.
set -uo pipefail

# Follows the dispatcher: $HOME-scoped per account today, /var/lib under host
# mode, so the ledger lives wherever the decision is made rather than in a
# third place that has to be kept in sync.
LEDGER_FILE="${RUN_LEDGER_FILE:-${STATE_DIR:-$HOME/.local/share/scheduler-paced-runner}/ledger.tsv}"

# ledger_append <project> <tier> <rc> <outcome> <reason>
# Row: iso8601 <TAB> host <TAB> account <TAB> project <TAB> tier <TAB> rc <TAB> outcome <TAB> reason
ledger_append() {
  local proj="${1:-?}" tier="${2:-?}" rc="${3:-?}" outcome="${4:-}" reason="${5:-}"
  local dir; dir="$(dirname "$LEDGER_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 1
  # ONE ROW IS ONE LINE, always. A reason carrying a tab or newline would
  # silently split a row in two and every later reader would mis-parse the
  # file from that point on -- the kind of corruption that is invisible until
  # something counts wrong.
  outcome="$(printf '%s' "$outcome" | tr -d '\t\n' | cut -c1-32)"
  reason="$(printf '%s' "$reason" | tr '\t\n' '  ' | cut -c1-200)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Is)" "$(hostname -s 2>/dev/null || echo '?')" "$(id -un)" \
    "$proj" "$tier" "$rc" "${outcome:-NONE}" "$reason" >> "$LEDGER_FILE"
}

# ledger_streak <project> <outcome> -- how many of the MOST RECENT consecutive
# rows for <project> carry <outcome>. 0 if the last row is something else, or
# if the project has no rows at all.
#
# ABSENCE READS AS ZERO, DELIBERATELY. No history means no evidence of
# repetition, and the safe direction is to keep dispatching -- the same
# polarity as bin/verdict.sh, where absence of a verdict is never GAVE-UP.
ledger_streak() {
  local proj="${1:?}" want="${2:?}" n=0 line
  [ -r "$LEDGER_FILE" ] || { printf '0'; return 0; }
  while IFS=$'\t' read -r _ts _host _acct p _tier _rc outcome _reason; do
    [ "$p" = "$proj" ] || continue
    if [ "$outcome" = "$want" ]; then n=$((n+1)); else n=0; fi
  done < "$LEDGER_FILE"
  printf '%s' "$n"
}

# ledger_last <project> -- the most recent outcome for <project>, or empty.
ledger_last() {
  local proj="${1:?}"
  [ -r "$LEDGER_FILE" ] || return 0
  awk -F'\t' -v p="$proj" '$4==p {o=$7} END{if(o!="") print o}' "$LEDGER_FILE"
}

# ledger_since <project> <outcome> -- how many rows for <project> have been
# appended SINCE its most recent <outcome> row. Empty/absent history prints a
# number large enough to mean "no reason to hold back" rather than 0, because
# 0 here would read as "the outcome just happened".
#
# THIS IS WHAT MAKES A COOLDOWN ELAPSE. A streak count cannot: skipping a
# dispatch appends nothing, so a streak-based hold would never see its own
# condition change and would stop the project permanently. Counting rows since
# the event only works if the SKIP is itself recorded -- which is why the
# cooldown writes a COOLDOWN row every time it holds.
ledger_since() {
  local proj="${1:?}" want="${2:?}"
  [ -r "$LEDGER_FILE" ] || { printf '999999'; return 0; }
  awk -F'\t' -v p="$proj" -v w="$want" '
    $4==p { if ($7==w) n=0; else if (n!="") n++ }
    END { if (n=="") print 999999; else print n }' "$LEDGER_FILE"
}
