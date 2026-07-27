#!/usr/bin/env bash
# registry-lock.sh -- "is anything else writing to this project right now?"
#
# ONE implementation of the two-half lockout, sourced by every caller:
#   half 1, job vs job    -- flock on $REGISTRY_DIR/<key>.lock + a .active marker
#   half 2, job vs HUMAN  -- $REGISTRY_DIR/<key>.interactive, pid-probed
#
# WHAT THIS RETIRES: the inline copy of both halves that lived only in
# lib/sweep-loop-common.sh. That placement is why the lockout covered every
# PROJECT's jobs but not the scheduler's own self-development cycle --
# bin/scheduler-dev-cycle.sh does not source sweep-loop-common.sh (it has no
# clone, no secrets, no `claude -p` wrapper to inherit), so it had NO registry
# participation at all and substituted `git status --porcelain` as a proxy for
# "is a person here". That proxy is what stranded 14 commits on 2026-07-25/26:
# a dirty tree is not a human, it has no starvation cap, and nothing retried.
#
# Callers RETURN on these, they do not exit -- each has its own exit-code
# vocabulary (sweep-loop-common uses 4 for deferred; the dev cycle just skips
# the merge and lets the cycle continue), so the policy lives here and the
# consequence stays with the caller.
#
# LIVENESS IS ALWAYS A PID PROBE, never a file's existence: neither the
# session hook nor a job can guarantee a clean release (SessionEnd is not
# guaranteed on crash), so trusting the file would wedge a project silently.
# See realisateur/bin/session-marker.sh, whose recorded pid was itself wrong
# until 2026-07-27 (c49c70d) -- it stored a PPID that died with the hook, so
# this probe read "nobody home" while a human was actively editing.

: "${REGISTRY_DIR:=$HOME/.local/share/scheduler-registry}"

# registry_claim <project_key> <job_name> <tier>
#   0 = claimed (caller must arrange release; sets REGISTRY_MARKER)
#   1 = another job already holds this project
# The flock is taken on fd 201 with `exec`, so it persists for the life of the
# calling process -- a function-local fd would close on return and release the
# lock while the job kept running.
registry_claim() {
  local key="$1" job="$2" tier="${3:-unspecified}"
  mkdir -p "$REGISTRY_DIR" || return 1
  REGISTRY_LOCK="$REGISTRY_DIR/${key}.lock"
  REGISTRY_MARKER="$REGISTRY_DIR/${key}.active"
  exec 201>"$REGISTRY_LOCK"
  if ! flock -n 201; then
    REGISTRY_HOLDER="$(cat "$REGISTRY_MARKER" 2>/dev/null || echo 'unknown job')"
    return 1
  fi
  printf '{"job":"%s","tier":"%s","started_at":"%s","pid":%s}\n' \
    "$job" "$tier" "$(date -Is)" "$$" > "$REGISTRY_MARKER"
  return 0
}

registry_release() { [ -n "${REGISTRY_MARKER:-}" ] && rm -f "$REGISTRY_MARKER"; return 0; }

# registry_human_pid <project_key>
# Echoes the pid of a LIVE interactive session, or nothing. A marker whose pid
# is gone is not a human -- it is litter from a crashed session.
registry_human_pid() {
  local marker="$REGISTRY_DIR/${1}.interactive" pid
  pid="$(awk -F= '$1=="pid"{print $2}' "$marker" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && printf '%s\n' "$pid"
  return 0
}

registry_human_since() {
  awk -F= '$1=="started_at"{print $2}' "$REGISTRY_DIR/${1}.interactive" 2>/dev/null || true
}

# registry_should_defer <project_key> <count_file> [max]
#   0 = defer to the human (caller stands down and comes back)
#   1 = proceed (nobody there, OR the starvation cap was reached)
# Sets REGISTRY_DEFER_PID / _SINCE / _COUNT / _MAX for the caller's message,
# and REGISTRY_DEFER_CAPPED=1 when it is returning 1 *despite* a live human.
#
# STARVATION CAP, non-negotiable: "defer whenever a human is present" means a
# long session starves the job forever. After <max> consecutive deferrals,
# proceed anyway and say so LOUDLY. Silent indefinite deferral is a worse
# failure than a warned-and-continued one, and this way both are visible.
registry_should_defer() {
  local key="$1" count_file="$2" max="${3:-3}" n
  REGISTRY_DEFER_CAPPED=0
  REGISTRY_DEFER_PID="$(registry_human_pid "$key")"
  REGISTRY_DEFER_MAX="$max"
  if [ -z "$REGISTRY_DEFER_PID" ]; then
    rm -f "$count_file"
    return 1
  fi
  REGISTRY_DEFER_SINCE="$(registry_human_since "$key")"
  n="$(cat "$count_file" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  REGISTRY_DEFER_COUNT="$n"
  if [ "$n" -le "$max" ]; then
    echo "$n" > "$count_file"
    return 0
  fi
  REGISTRY_DEFER_CAPPED=1
  return 1
}
