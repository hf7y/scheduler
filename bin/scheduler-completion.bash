#!/usr/bin/env bash
# Bash tab-completion for bin/scheduler. Source this from your shell rc:
#   source "/home/zach/Documents/Projects/scheduler/bin/scheduler-completion.bash"
# Purely mechanical (FOCUS.md 2026-07-22 backlog item; #397 fixed the half
# that drifted) -- both lists below are read live off bin/scheduler and
# schedule/*.conf, so neither list can go stale again.

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

# Subcommand names, read live off bin/scheduler's own case arms (#397).
_scheduler_subcommands() {
  local sched_bin="${SCHEDULER_COMPLETION_BIN:-/home/zach/Documents/Projects/scheduler/bin/scheduler}"
  [ -r "$sched_bin" ] || return 0
  awk '
    /^case "\$\{1:-\}" in$/ { incase = 1; next }
    incase && /^esac$/ { exit }
    incase && /^  [^ ]/ && /\)/ {
      line = $0
      sub(/^  /, "", line)
      sub(/\).*/, "", line)
      n = split(line, arr, "|")
      for (i = 1; i <= n; i++) {
        tok = arr[i]
        gsub(/"/, "", tok)
        if (tok == "" || tok == "*" || tok ~ /^_/) continue
        print tok
      }
    }
  ' "$sched_bin"
}

_scheduler_completion() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$(_scheduler_subcommands)" -- "$cur"))
    return 0
  fi

  case "$prev" in
    focus|-f|questions|-q|report|-r|idea|-i|status|-c)
      COMPREPLY=($(compgen -W "$(_scheduler_projects)" -- "$cur"))
      ;;
  esac
}

complete -F _scheduler_completion scheduler
