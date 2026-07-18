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

set -uo pipefail
SCHED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="${REPORTS_DIR:-$HOME/reports}"
QUESTIONS_DIR="$SCHED_DIR/questions"

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
