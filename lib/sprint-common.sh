#!/usr/bin/env bash
# sprint-common.sh -- shared state for `dose <project> --sprint` (#292) and
# usage-paced-runner.sh's tempo bypass.
#
# WHERE STATE LIVES: a project's own dispatcher STATE_DIR -- the same
# $HOME/.local/share/scheduler-paced-runner (account mode) usage-paced-
# runner.sh already reads. `dose <project> --sprint` writes AS that account
# (sudo -n -u), so the runner needs no new wiring to see a sprint the moment
# it lands.
#
# WHAT A SPRINT BYPASSES, AND WHAT IT DOES NOT (hf7y/scheduler#292): tempo
# only. It never touches usage-gate.sh / USAGE_CEILING -- see this repo's
# CLAUDE.md-adjacent decision recorded on #292 itself ("Bypasses PACING only,
# never USAGE_CEILING"). usage-paced-runner.sh's dispatch loop is the one
# place that distinction is enforced; this file only stores and reads the
# deadline.
#
# Sourced, never executed -- same purity rule as dose-common.sh (no network
# call, no top-level side effect; see tests/dose-common-purity-witness.sh for
# the shape that rule is checked in). All timestamps are UTC, second
# precision, Z suffix (date -u +%Y-%m-%dT%H:%M:%SZ) so plain lexical string
# comparison IS chronological comparison -- no date-diffing tool required to
# ask "is this sprint still active".
#
# RUNNER: tests/sprint-common-witness.sh
set -uo pipefail

SPRINT_JOB_NAME="scheduler-paced-runner"

# sprint_dir <state-root> -- the sprints/ subdir under a dispatcher's own
# STATE_DIR. A function, not a literal, so callers never hand-splice the path.
sprint_dir() { printf '%s/sprints' "${1:?sprint_dir needs a state root}"; }

# sprint_parse_duration <spec> -- "<N>h" or "<N>m" -> seconds on stdout.
# Returns 1 on anything else, same contract shape as dose-common.sh's
# cron_fields_for_rate (a bad spec is a caller error, not a usage-error exit
# baked into a library function).
sprint_parse_duration() {
  local spec="${1:-}"
  if [[ "$spec" =~ ^([0-9]+)h$ ]]; then
    printf '%d' "$(( 10#${BASH_REMATCH[1]} * 3600 ))"; return 0
  fi
  if [[ "$spec" =~ ^([0-9]+)m$ ]]; then
    printf '%d' "$(( 10#${BASH_REMATCH[1]} * 60 ))"; return 0
  fi
  return 1
}

# sprint_expires_at <seconds> [now-epoch] -- the absolute wall-clock T, UTC.
# now-epoch is a parameter (not always `date -u +%s`) purely for witnessing --
# a hermetic test picks a fixed epoch so its expected output is deterministic.
sprint_expires_at() {
  local secs="${1:?sprint_expires_at needs a seconds count}" now="${2:-$(date -u +%s)}"
  date -u -d "@$(( now + secs ))" +%Y-%m-%dT%H:%M:%SZ
}

# sprint_now -- current wall clock, same format as sprint_expires_at, so a
# lexical comparison against a stored expiry is valid.
sprint_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# sprint_set <state-root> <project> <expires-at> -- record it. Write-then-
# rename so a reader never sees a half-written file. The caller is
# responsible for being the right uid to write under state-root --
# dose-project.sh sudo's to the row's own account first, same as it already
# does for crontab_write.
sprint_set() {
  local root="${1:?sprint_set needs a state root}" proj="${2:?sprint_set needs a project}" \
        exp="${3:?sprint_set needs an expires-at}" dir
  dir="$(sprint_dir "$root")"
  mkdir -p "$dir" || return 1
  printf '%s\n' "$exp" > "$dir/$proj.expiry.tmp" || return 1
  mv -f "$dir/$proj.expiry.tmp" "$dir/$proj.expiry"
}

# sprint_clear <state-root> <project> -- remove any sprint on record. Not an
# error if there was none.
sprint_clear() { rm -f "$(sprint_dir "${1:?sprint_clear needs a state root}")/${2:?sprint_clear needs a project}.expiry"; }

# sprint_expiry <state-root> <project> -- print the recorded expiry, whether
# or not it has passed. Empty output + return 1 if there is no sprint on
# record at all -- distinct from an EXPIRED sprint, which sprint_active below
# reports by clearing it, not by this function refusing to say what it saw.
sprint_expiry() {
  local f; f="$(sprint_dir "${1:?sprint_expiry needs a state root}")/${2:?sprint_expiry needs a project}.expiry"
  [ -r "$f" ] || return 1
  cat "$f"
}

# sprint_active <state-root> <project> [now] -- 0 if a sprint is on record
# and has not yet reached its deadline, 1 otherwise.
#
# SELF-CLEANING: a sprint already past its deadline is deleted right here, on
# the read that discovers it -- so "expired" and "never sprinted" converge to
# the same state on their own, with no separate reaper process and no window
# where `dose <project> --sprint-status` reports a phantom active sprint that
# the dispatch loop has already stopped honouring. This is also the "hard
# stop" #292 asks for: a sprint never decays into a soft bypass, it just
# stops being found the instant `now` crosses `exp`, and an in-flight
# dispatch that started before the deadline is untouched because this check
# only ever runs BEFORE a dispatch begins.
sprint_active() {
  local root="${1:?sprint_active needs a state root}" proj="${2:?sprint_active needs a project}" \
        now="${3:-$(sprint_now)}" exp
  exp="$(sprint_expiry "$root" "$proj" 2>/dev/null)" || return 1
  if [[ "$now" < "$exp" ]]; then
    return 0
  fi
  sprint_clear "$root" "$proj"
  return 1
}
