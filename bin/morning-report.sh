#!/usr/bin/env bash
# DEPRECATED (2026-07-20) -- superseded by `bin/scheduler` (installed at
# ~/.local/bin/scheduler), a real interactive CLI covering the same ground
# (glance view, per-project questions/focus/report drill-down, blockers)
# more usably, without this script's known unresolved hang bug. Confirmed
# nothing besides this script itself reads DIGEST.md. Left working and
# in-repo (not deleted) since it's harmless and low-risk to keep, but
# `bin/scheduler` is the thing to actually use and build against now --
# see .scheduler/FOCUS.md's Vision/Consolidation-roadmap sections.
#
# Original description below, still accurate for what THIS script does:
#
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
# a report nobody thinks to check the day it's written. Same for BLOCKERS.md
# (human-owned action items, see docs/feedback-tags.md).
#
# For any project that opts in with a DEPLOY_FRESH_CMD probe in its
# schedule/<project>.conf, prints a prominent "DEPLOY PENDING" line when the
# live build has fallen behind origin -- so a code-shipping night that
# committed + pushed but couldn't run the deploy (e.g. vkv-inventory's clasp
# step needs interactive auth) surfaces here even when it filed no question.
#
# Output is ALSO persisted to DIGEST.md (repo root) -- one compiled document,
# sections per project, meant to be the "read this once, start to end" paper-
# equivalent artifact (see the crt project's own printer/screen split in
# BLOCKERS.md's design discussion 2026-07-20): `scheduler` (the CLI) is the
# short/screen tier, DIGEST.md is the long/paper tier. Pass --no-digest to
# skip writing it (e.g. if this is being piped somewhere that doesn't want a
# side-effect file write).

set -uo pipefail
SCHED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="${REPORTS_DIR:-$HOME/reports}"
QUESTIONS_DIR="$SCHED_DIR/questions"
SCHEDULE_DIR="$SCHED_DIR/schedule"
BLOCKERS_FILE="$SCHED_DIR/BLOCKERS.md"
DIGEST_FILE="$SCHED_DIR/DIGEST.md"

WRITE_DIGEST=1
[ "${1:-}" = "--no-digest" ] && WRITE_DIGEST=0

# Everything below is generated into $body, then printed AND (unless
# --no-digest) written to DIGEST.md -- single source, two destinations.
body="$(
{

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
    # Skip ALL underscore-prefixed meta-confs (_batch.conf, _paced.conf,
    # _runner.conf, ...), not just _batch.conf by name -- the same bug
    # build-services-view.sh had (fixed 61f7dbd): _paced.conf's
    # `name|enabled|cmd` lines get sourced as shell if this only special-
    # cases one filename, which can pipe a real participant name into a
    # command lookup and actually execute a live wrapper as a side effect
    # of sourcing -- this is exactly what was hanging this script.
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

# Blockers -- per-project sections of BLOCKERS.md (human-owned action
# items an unattended run can't clear itself). Reuses the same "## project"
# heading convention collect-feedback.sh's --section matches against, but
# prints the full section body (not just tag lines) since this is the
# read-start-to-end paper tier, not the terse glance tier.
if [ -f "$BLOCKERS_FILE" ]; then
  any_blockers_section=0
  while IFS= read -r proj; do
    section="$(awk -v want="$proj" '
      BEGIN { IGNORECASE=1 }
      /^##[ \t]/ {
        insec = ($0 ~ ("^## *" want "[ \t]*$"))
        next
      }
      insec { print }
    ' "$BLOCKERS_FILE")"
    # Strip leading/trailing blank lines; skip if nothing real is left.
    section="$(printf '%s\n' "$section" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"
    [ -n "$section" ] || continue
    if [ "$any_blockers_section" -eq 0 ]; then
      echo "════════════════════════════════════════"
      echo "  Blockers (BLOCKERS.md)"
      echo "════════════════════════════════════════"
      any_blockers_section=1
    fi
    echo "-- $proj --"
    printf '%s\n' "$section"
    echo
  done < <(for c in "$SCHEDULE_DIR"/*.conf; do b="$(basename "$c" .conf)"; [[ "$b" == _* ]] || echo "$b"; done)
fi

} )"

printf '%s\n' "$body"

if [ "$WRITE_DIGEST" -eq 1 ]; then
  {
    echo "<!-- Generated by bin/morning-report.sh -- do not hand-edit, it's"
    echo "     overwritten every run. One compiled document, sections per"
    echo "     project: reports, deploy-pending flags, open questions,"
    echo "     blockers. The 'read once, start to end' paper-equivalent"
    echo "     tier; 'scheduler' (the CLI) is the short/screen tier. -->"
    echo
    printf '%s\n' "$body"
  } > "$DIGEST_FILE"
fi

# To print automatically on every new shell, add this line to ~/.bashrc:
#   bash "/home/zach/Documents/Project Archive/scheduler/bin/morning-report.sh"
