#!/usr/bin/env bash
# Prints every project's most recent report in one place. Run by hand each
# morning, or wire the one line at the bottom into ~/.bashrc / ~/.profile
# to print automatically whenever a new shell starts (commented out below
# -- opt into that yourself, don't want a surprise wall of text on every
# terminal tab without asking for it first).
#
# Expects: ~/reports/<project>/LATEST.md per project (see
# nightly-batch-loop.sh / nightly-batch.md.template for how those get
# written). Silently no-ops if nothing exists yet -- this is meant to be
# safe to run before any project has ever produced a report.
#
# Also prints anything sitting in QUESTIONS.md across every registered
# project, via the ../questions/*.md symlinks bin/sync-crontab.sh --apply
# maintains -- so a flagged judgment call surfaces here too, not just in
# a report nobody thinks to check the day it's written.
#
# Finally, for any project that opts in with a DEPLOY_FRESH_CMD probe in its
# schedule/<project>.conf, prints a prominent "DEPLOY PENDING" line when the
# live build has fallen behind origin -- so a code-shipping night that
# committed + pushed but couldn't run the deploy (e.g. vkv-inventory's clasp
# step needs interactive auth) surfaces here even when it filed no question.
#
# Also prints a "Branches beyond main" section (FOCUS.md backlog item,
# decided 2026-07-19): every registered job's engine already maintains a
# dedicated clone under ~/.local/share/<JOB_NAME>/repo (see
# lib/sweep-loop-common.sh) that is never deleted between runs, so its local
# git state -- what branches exist locally and on origin as of the last run
# -- is read directly rather than adding a new marker file. Same idea for
# this repo itself (checked directly, no dedicated clone). Read-only: no
# fetch is performed, so this reflects branch state as of each project's
# last scheduled run / this repo's current state, not a live network check.

set -uo pipefail
SCHED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="${REPORTS_DIR:-$HOME/reports}"
QUESTIONS_DIR="$SCHED_DIR/questions"
SCHEDULE_DIR="$SCHED_DIR/schedule"
STATE_ROOT="${STATE_ROOT:-$HOME/.local/share}"

# Print $2's branches beyond its default (main/master), one per line, or
# nothing if there are none / it isn't a git repo. $1 is a label for the
# caller to print if this produces any output.
extra_branches() {
  local repo="$1"
  # .git is a FILE (not a directory) inside a git worktree -- use -e, not -d,
  # so this also covers this repo's own paced/<date> worktree.
  [ -e "$repo/.git" ] || return 0
  local default
  default="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  default="${default#origin/}"
  [ -n "$default" ] || default="main"
  # refs/remotes/origin/HEAD's short name is bare "origin" (not "origin/HEAD"),
  # so it needs its own exclusion alongside "HEAD" for a plain branch ref.
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null \
    | sed 's#^origin/##' \
    | sort -u \
    | grep -vx -e "$default" -e "HEAD" -e "origin" -e "main" -e "master" || true
}

if [ -d "$REPORTS_DIR" ]; then
  found=0
  for latest in "$REPORTS_DIR"/*/LATEST.md; do
    [ -e "$latest" ] || continue
    found=1
    project=$(basename "$(dirname "$latest")")
    echo "════════════════════════════════════════"
    echo "  $project"
    echo "════════════════════════════════════════"
    cat "$latest"
    echo
  done
  if [ "$found" -eq 0 ]; then
    echo "No reports found under $REPORTS_DIR/*/LATEST.md yet."
  fi
else
  echo "No reports directory yet at $REPORTS_DIR"
fi

# Deploy freshness -- opt-in per project. A project's schedule/<project>.conf
# may set DEPLOY_FRESH_CMD: a cheap probe run here that exits 0 when the live
# build is up to date and NON-ZERO when a deploy is pending (the nightly
# committed + pushed, but a deploy step a human has to run hasn't happened).
# For any project whose probe reports stale, print a prominent line with the
# exact command to run (DEPLOY_CMD) and, if set, the live URL. Projects that
# set no DEPLOY_FRESH_CMD are untouched -- the output stays byte-identical for
# them, so this section is silent on a morning with nothing pending.
if [ -d "$SCHEDULE_DIR" ]; then
  any_deploy=0
  for conf in "$SCHEDULE_DIR"/*.conf; do
    [ -e "$conf" ] || continue
    # Underscore-prefixed files are meta-config (_batch.conf, _paced.conf,
    # _runner.conf, ...), not projects -- skip all of them uniformly, same
    # convention bin/sync-crontab.sh and bin/build-services-view.sh already
    # follow. This used to only exclude _batch.conf by name: sourcing
    # _paced.conf's "name|enabled|cmd" lines as shell parses each as a
    # pipeline, and the last stage is a real wrapper path -- e.g.
    # `scheduler|1|/home/zach/.local/bin/scheduler-dev-cycle.sh` actually
    # EXECUTES that wrapper as a side effect of this read-only report
    # script (same bug independently hit and fixed in
    # build-services-view.sh on 2026-07-19; this loop was missed then).
    case "$(basename "$conf")" in _*) continue ;; esac
    # Source in a subshell (same idiom as build-services-view.sh) so a conf's
    # vars never leak; emit a tab-separated line on stdout only when stale.
    result="$(
      unset PROJECT DEPLOY_FRESH_CMD DEPLOY_CMD LIVE_URL
      # shellcheck disable=SC1090
      . "$conf" 2>/dev/null || exit 0
      [ -n "${DEPLOY_FRESH_CMD:-}" ] || exit 0
      # Run the probe in its own subshell so a probe written as a bare
      # `exit N` can't escape and terminate this capture before the printf.
      ( eval "$DEPLOY_FRESH_CMD" ) >/dev/null 2>&1 && exit 0   # 0 == fresh, nothing to say
      printf '%s\t%s\t%s' "${PROJECT:-$(basename "$conf" .conf)}" \
        "${DEPLOY_CMD:-<set DEPLOY_CMD in this conf>}" "${LIVE_URL:-}"
    )"
    [ -n "$result" ] || continue
    IFS=$'\t' read -r dp_project dp_cmd dp_url <<<"$result"
    if [ "$any_deploy" -eq 0 ]; then
      echo "════════════════════════════════════════"
      echo "  DEPLOY PENDING"
      echo "════════════════════════════════════════"
      any_deploy=1
    fi
    echo "-- $dp_project --"
    echo "  live build is BEHIND origin — a deploy is pending."
    [ -n "$dp_url" ] && echo "  live: $dp_url"
    echo "  run:  $dp_cmd"
    echo
  done
fi

# Branches beyond main -- this repo (scheduler) first, since its own
# paced/nightly self-dev branches are the ones most likely to pile up
# unmerged (see FOCUS.md item 6), then every other registered project's
# dedicated clone.
any_branches=0
sched_extra="$(extra_branches "$SCHED_DIR")"
if [ -n "$sched_extra" ]; then
  echo "════════════════════════════════════════"
  echo "  Branches beyond main"
  echo "════════════════════════════════════════"
  any_branches=1
  echo "-- scheduler (this repo) --"
  echo "$sched_extra" | sed 's/^/  /'
  echo
fi
if [ -d "$STATE_ROOT" ]; then
  for repo in "$STATE_ROOT"/*/repo; do
    [ -d "$repo/.git" ] || continue
    job="$(basename "$(dirname "$repo")")"
    extra="$(extra_branches "$repo")"
    [ -n "$extra" ] || continue
    if [ "$any_branches" -eq 0 ]; then
      echo "════════════════════════════════════════"
      echo "  Branches beyond main"
      echo "════════════════════════════════════════"
      any_branches=1
    fi
    echo "-- $job (as of its last run) --"
    echo "$extra" | sed 's/^/  /'
    echo
  done
fi

# Open questions -- only print a project's file if it has at least one
# real entry (the documented "- **YYYY-MM-DD (...):" format), not just
# the template header every project starts with. Keeps a quiet morning
# quiet instead of re-printing four empty headers forever.
if [ -d "$QUESTIONS_DIR" ]; then
  any_questions=0
  for q in "$QUESTIONS_DIR"/*.md; do
    [ -e "$q" ] || continue
    grep -q '^- \*\*' "$q" 2>/dev/null || continue
    if [ "$any_questions" -eq 0 ]; then
      echo "════════════════════════════════════════"
      echo "  Open questions"
      echo "════════════════════════════════════════"
      any_questions=1
    fi
    project=$(basename "$q" .md)
    echo "-- $project --"
    awk '/^- \*\*/{p=1} p' "$q"
    echo
  done
fi

# To print automatically on every new shell, add this line to ~/.bashrc:
#   bash "/home/zach/Documents/Project Archive/scheduler/bin/morning-report.sh"
