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

set -uo pipefail
SCHED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="${REPORTS_DIR:-$HOME/reports}"
QUESTIONS_DIR="$SCHED_DIR/questions"
SCHEDULE_DIR="$SCHED_DIR/schedule"

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
    [ "$(basename "$conf")" = "_batch.conf" ] && continue
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
