#!/usr/bin/env bash
# answer-registry.sh -- a typed row for every answer Zach relays, and the
# read that makes it reach the next run.
#
# THE GAP (hf7y/scheduler#149, build item 2). `scheduler questions <proj>`
# already posts Zach's typed answer as a GitHub comment and labels the issue
# `answered` -- but posting is not reading. The evidence in #149: one
# question re-posed 100 minutes after its answer, the same question answered
# three separate times, and 12 `needs-human` issues sitting open with no
# dispatch path for the answer that would clear them. A comment on a tracker
# is exactly as unread as `<!-- DEFERRED -->` was before route-deliveries.sh
# (#299) -- a claim the write side enforces and the read side never checks.
#
# THE FIX IS A REGISTRY, NOT A SMARTER SCAN. Recording the answer AT THE
# MOMENT IT IS RELAYED (bin/scheduler's cmd_questions_issues, the one place a
# human's typed answer enters this system) is strictly more reliable than
# re-deriving "was this answered" later from comment heuristics -- it is
# already known-trusted, human-typed content, not a guess. So this file has
# two halves: RECORD (called once, at relay time) and READ (called once, at
# the next dispatch, by whoever owns that project's PROMPT).
#
# "MUST READ ROWS NEWER THAN ITS LAST LEDGER ENTRY" (#149's own wording). The
# cutoff is the project's own run ledger (lib/run-ledger.sh) rather than a
# second piece of consumed state, because the ledger already timestamps every
# past dispatch per project and an answer posted since the last one is
# exactly what a fresh dispatch needs to see. No era filters: unlike the
# retired ANSWERED_STAMP_ERA class, there is no fixed epoch baked in anywhere
# in this file -- "since" is always a caller-supplied timestamp.
#
# APPEND-ONLY, same contract as run-ledger.sh: no update, no delete, no
# rotate, one small atomic printf per row (under PIPE_BUF).
#
# CONTRACT
#   answer_registry_record <project> <issue> <marker> <text>
#     Appends one row. <marker> names how the answer reached this file --
#     "relay" for scheduler questions' own $EDITOR path today, and the
#     default when empty; left open for a future writer to say otherwise
#     rather than assert relay for content it didn't relay.
#   answer_registry_unread <project> <since-iso8601>
#     Prints rows for <project> strictly newer than <since-iso8601> (all rows
#     if <since-iso8601> is empty), one per line, tab-separated:
#     iso8601 <TAB> issue <TAB> marker <TAB> text. <text> is still \t/\n-
#     encoded exactly as recorded -- same convention cmd_questions_issues
#     already uses for a multi-line answer (bin/scheduler's `printf '%b'`) --
#     so a caller renders it with `printf '%b'`, not by printing it raw.
#     Prints nothing, exits 0, if there are none -- absence is not an error.
set -uo pipefail

# Resolved per call, not at source time -- same trap as run-ledger.sh's
# _ledger_file: a caller exporting ANSWER_REGISTRY_FILE after sourcing must
# not silently get the default.
_answer_registry_file() {
  printf '%s' "${ANSWER_REGISTRY_FILE:-${STATE_ROOT:-$HOME/.local/share}/scheduler-answers/registry.tsv}"
}

# answer_registry_record <project> <issue> <marker> <text>
# Row: iso8601 <TAB> project <TAB> issue <TAB> marker <TAB> text
answer_registry_record() {
  local proj="${1:?answer_registry_record: project required}" \
        issue="${2:?answer_registry_record: issue required}" \
        marker="${3:-relay}" \
        text="${4:-}"
  local f; f="$(_answer_registry_file)"
  local dir; dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null || return 1
  # ONE ROW IS ONE LINE (run-ledger.sh's #54 lesson, reapplied here): a tab
  # or newline in the text would split the row, so both are escaped rather
  # than stripped -- the text is exactly what "read this before anything
  # else" hands the next run, and stripping it would silently truncate the
  # decision itself.
  marker="$(printf '%s' "$marker" | tr -d '\t\n')"
  text="$(printf '%s' "$text" | sed ':a;N;$!ba;s/\\/\\\\/g; s/\t/\\t/g; s/\n/\\n/g')"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Is)" "$proj" "$issue" "${marker:-relay}" "$text" >> "$f" || return 1
}

# answer_registry_unread <project> <since-iso8601>
answer_registry_unread() {
  local proj="${1:?answer_registry_unread: project required}" since="${2:-}"
  local f; f="$(_answer_registry_file)"
  [ -r "$f" ] || return 0
  local since_epoch=0
  if [ -n "$since" ]; then
    since_epoch="$(date -d "$since" +%s 2>/dev/null)" || since_epoch=0
  fi
  local ts p issue marker text row_epoch
  while IFS=$'\t' read -r ts p issue marker text; do
    [ "$p" = "$proj" ] || continue
    row_epoch="$(date -d "$ts" +%s 2>/dev/null)" || continue
    [ "$row_epoch" -gt "$since_epoch" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$ts" "$issue" "$marker" "$text"
  done < "$f"
}
