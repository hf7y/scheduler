#!/usr/bin/env bash
# Bash tab-completion for bin/scheduler. Source this from your shell rc:
#   source "/home/zach/Documents/Projects/scheduler/bin/scheduler-completion.bash"
# Purely mechanical (FOCUS.md 2026-07-22 backlog item, flagged "no design
# work needed, just didn't fit this pass") -- reuses the same
# schedule/*.conf glob `projects()` in bin/scheduler already uses, so the
# completion list can never drift out of sync with the real registry.

_scheduler_projects() {
  local sched_root="/home/zach/Documents/Projects/scheduler"
  local conf b
  for conf in "$sched_root"/schedule/*.conf; do
    [ -e "$conf" ] || continue
    b="$(basename "$conf" .conf)"
    [[ "$b" == _* ]] && continue
    printf '%s\n' "$b"
  done
}

_scheduler_completion() {
  local cur prev subcommands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  subcommands="blockers -b focus -f questions -q report -r idea -i sweep -s explain -e man -m status -c"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$subcommands" -- "$cur"))
    return 0
  fi

  case "$prev" in
    focus|-f|questions|-q|report|-r|idea|-i|status|-c)
      COMPREPLY=($(compgen -W "$(_scheduler_projects)" -- "$cur"))
      ;;
  esac
}

complete -F _scheduler_completion scheduler
