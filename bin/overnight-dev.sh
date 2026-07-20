#!/usr/bin/env bash
# Overnight self-development driver for the scheduler repo.
#
# The 03:00 cron job (scheduler-nightly-batch-loop.sh) is a SINGLE
# review-gated run and re-running it the same day DESTROYS the prior branch.
# This driver is the "keep developing while I sleep" companion: it runs a
# CHAIN of cycles through the night, each in a throwaway git worktree, and --
# crucially -- each productive cycle branches from the PREVIOUS productive
# cycle so work ACCUMULATES instead of clobbering.
#
# Same conservative philosophy as the nightly job:
#   * REVIEW GATE: every cycle's work lands on a branch overnight/<date>-cNN
#     for a human to inspect and merge in the morning. Nothing is merged to
#     main, pushed, or activated automatically.
#   * The live working tree stays on main, untouched.
#   * crontab is snapshotted before/after every cycle; any change shouts.
#   * A barren cycle (no commits -- e.g. hit a usage cap) is discarded and
#     the chain does NOT advance, so failures cost seconds and don't pollute
#     the review chain. The next cycle still tries.
#
# Launch it detached so it survives closing the terminal:
#     echo /home/zach/.local/bin/overnight-dev.sh | at now + 3 minutes
# (installed copy) or point at this repo copy. Tunables via env:
#     MAX_CYCLES (5)  GAP_MINUTES (55)  DEADLINE_HHMM (0830)  MAX_TURNS (60)
# Dry-run the plumbing without spending tokens:  SCHED_DRYRUN=1 bin/overnight-dev.sh

set -uo pipefail

JOB_NAME="scheduler-overnight-dev"
SCHED_REPO="/home/zach/Documents/Project Archive/scheduler"
STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
WORKTREE="$STATE_DIR/worktree"
REPORTS_DIR="$HOME/reports/scheduler"
DATE="$(date +%F)"
REPORT="$REPORTS_DIR/${DATE}-overnight.md"

MAX_TURNS="${MAX_TURNS:-60}"
MAX_CYCLES="${MAX_CYCLES:-5}"
GAP_MINUTES="${GAP_MINUTES:-55}"
DEADLINE_HHMM="${DEADLINE_HHMM:-0830}"   # don't START a new cycle after this local time
ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep"
NODE_BIN_DIR="${NODE_BIN_DIR:-/home/zach/.nvm/versions/node/v25.2.1/bin}"

export PATH="$NODE_BIN_DIR:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

mkdir -p "$STATE_DIR" "$REPORTS_DIR"

exec 200>"$LOCK"
if ! flock -n 200; then
  echo "$(date -Is) overnight-dev already running, skipping" >> "$LOG"
  exit 0
fi

[ -f "$LOG" ] && { tail -n 8000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }

cleanup() { cd "$SCHED_REPO" 2>/dev/null && git worktree remove --force "$WORKTREE" 2>/dev/null || true; }
trap cleanup EXIT

BASE="main"   # first cycle branches from main; then chains through productive cycles

{
  echo "############ $(date -Is) overnight-dev START (<=${MAX_CYCLES} cycles, gap ${GAP_MINUTES}m, deadline ${DEADLINE_HHMM}) ############"
  cd "$SCHED_REPO" || { echo "cannot cd $SCHED_REPO"; exit 1; }

  for (( i=1; i<=MAX_CYCLES; i++ )); do
    NOW_HHMM="$(date +%H%M)"
    if [ "$((10#$NOW_HHMM))" -ge "$((10#$DEADLINE_HHMM))" ]; then
      echo "=== $(date -Is) reached deadline $DEADLINE_HHMM before cycle $i -- stopping ==="
      break
    fi

    BRANCH="$(printf 'overnight/%s-c%02d' "$DATE" "$i")"
    echo "==== $(date -Is) cycle $i/$MAX_CYCLES  branch=$BRANCH  base=$BASE ===="
    CRON_BEFORE="$(crontab -l 2>/dev/null | md5sum)"

    git worktree remove --force "$WORKTREE" 2>/dev/null || true
    git branch -D "$BRANCH" 2>/dev/null || true
    git worktree prune
    if ! git worktree add -b "$BRANCH" "$WORKTREE" "$BASE"; then
      echo "cycle $i: worktree add failed on base $BASE -- skipping cycle"
      continue
    fi

    cd "$WORKTREE" || { cd "$SCHED_REPO"; continue; }
    BEFORE_SHA="$(git rev-parse HEAD)"

    PROMPT="/nightly-batch

This is the scheduler improving ITSELF overnight, fully unattended, behind a HUMAN REVIEW GATE. Everything you do lands as commits on branch $BRANCH for a person to review and merge in the morning -- nothing goes live automatically. This is one cycle in an overnight CHAIN: earlier cycles tonight may already be committed on this branch. Run 'git log --oneline main..HEAD' FIRST to see what tonight's earlier cycles already did, and CONTINUE from there -- do not redo finished work.

Read .scheduler/FOCUS.md next -- it is this project's scope AND backlog. Pick the NEXT highest-value, LOWEST-RISK improvement you can fully finish AND verify this cycle. This repo is the meta-tool that controls every other project's cron jobs, so correctness beats volume: one well-tested change is worth more than three risky ones.

HARD RULES (this is infrastructure, not an app):
  * Make changes ONLY as commits in THIS working directory ($WORKTREE) on branch $BRANCH. Touch nothing outside it.
  * NEVER run 'crontab', and NEVER run bin/sync-crontab.sh with --apply. Previewing (no --apply) to validate a schedule change is fine and encouraged.
  * NEVER edit the installed wrapper scripts under ~/.local/bin, or any file outside this repo.
  * Prefer changes verifiable here and now (shellcheck, a dry-run, simulating cron's env with 'env -u SSH_AUTH_SOCK') over changes whose only test is 'wait for tonight'. If a change can't be safely verified without going live, write it up as a proposal in the report instead of committing it.
  * On a real judgment call or anything needing the user's blessing, append it to .scheduler/QUESTIONS.md and describe it in the report rather than deciding unilaterally.

Commit each finished change with a clear message. Then append a section for THIS cycle to $REPORT (create it if absent) and refresh $REPORTS_DIR/LATEST.md to point at tonight's work, covering: what you changed and why, how you verified it, what you deferred and why, and any open questions. A change that isn't committed on $BRANCH didn't happen."

    if [ "${SCHED_DRYRUN:-0}" = "1" ]; then
      echo "DRYRUN: skipping claude invocation"
      STATUS="dryrun"
    elif claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --max-turns "$MAX_TURNS"; then
      STATUS="done"
    else
      STATUS="FAILED"
    fi

    AFTER_SHA="$(git rev-parse HEAD)"
    cd "$SCHED_REPO"

    CRON_AFTER="$(crontab -l 2>/dev/null | md5sum)"
    if [ "$CRON_BEFORE" != "$CRON_AFTER" ]; then
      echo "WARNING: live crontab CHANGED during cycle $i -- investigate"
      notify-send -u critical "$JOB_NAME" "live crontab modified during a self-run -- investigate $LOG"
    fi

    if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
      echo "cycle $i ($STATUS): new commits on $BRANCH --"
      git log --oneline "$BASE..$BRANCH" 2>/dev/null
      git worktree remove --force "$WORKTREE" 2>/dev/null || true
      BASE="$BRANCH"   # chain: next cycle builds on this productive branch
    else
      echo "cycle $i ($STATUS): no commits -- discarding empty branch $BRANCH"
      git worktree remove --force "$WORKTREE" 2>/dev/null || true
      git branch -D "$BRANCH" 2>/dev/null || true
    fi

    if [ "$i" -lt "$MAX_CYCLES" ]; then
      echo "--- $(date -Is) sleeping ${GAP_MINUTES}m before next cycle ---"
      sleep "$((GAP_MINUTES * 60))"
    fi
  done

  echo "############ $(date -Is) overnight-dev END -- review branch: $BASE ############"
  if [ "$BASE" != "main" ]; then
    echo "morning review:  git log --oneline main..$BASE   &&   git branch --list 'overnight/$DATE-*'"
    notify-send "$JOB_NAME" "Overnight work done. Review: git log main..$BASE"
  fi
} >> "$LOG" 2>&1
