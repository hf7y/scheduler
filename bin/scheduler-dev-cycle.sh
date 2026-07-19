#!/usr/bin/env bash
# scheduler-dev-cycle.sh -- ONE review-gated self-development cycle.
#
# The usage-paced runner calls this when the scheduler's turn comes up (instead
# of the old fixed 03:00 nightly). Same conservative, review-gated philosophy as
# scheduler-nightly-batch-loop.sh, but built to be called REPEATEDLY through the
# day: all of a day's cycles accumulate on ONE branch  paced/<date>  (each cycle
# branches from that branch's tip and commits back onto it), so work builds up
# for a single morning review -- never touching main, never pushing.
#
# Exit 0 on a clean run (with or without commits), non-zero only on setup
# failure. Honours SCHED_DRYRUN=1 (skips the claude call) for plumbing tests.
set -uo pipefail

JOB_NAME="scheduler-paced-dev"
SCHED_REPO="/home/zach/Documents/Project Archive/scheduler"
STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
WORKTREE="$STATE_DIR/worktree"
REPORTS_DIR="$HOME/reports/scheduler"
DATE="$(date +%F)"
BRANCH="paced/$DATE"
REPORT="$REPORTS_DIR/${DATE}-paced.md"

MAX_TURNS="${MAX_TURNS:-60}"
ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep"
NODE_BIN_DIR="${NODE_BIN_DIR:-/home/zach/.nvm/versions/node/v25.2.1/bin}"

export PATH="$NODE_BIN_DIR:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

mkdir -p "$STATE_DIR" "$REPORTS_DIR"

exec 200>"$LOCK"
if ! flock -n 200; then
  echo "$(date -Is) paced-dev already running, skipping" >> "$LOG"
  exit 0
fi
[ -f "$LOG" ] && { tail -n 4000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }

cleanup() { cd "$SCHED_REPO" 2>/dev/null && git worktree remove --force "$WORKTREE" 2>/dev/null || true; }
trap cleanup EXIT

{
  echo "==== $(date -Is) paced-dev cycle on $BRANCH ===="
  cd "$SCHED_REPO" || { echo "cannot cd $SCHED_REPO"; exit 1; }
  CRON_BEFORE="$(crontab -l 2>/dev/null | md5sum)"

  git worktree remove --force "$WORKTREE" 2>/dev/null || true
  git worktree prune
  # Branch paced/<date>: create from main on the day's first cycle, else reuse.
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git worktree add "$WORKTREE" "$BRANCH" || { echo "worktree add (reuse) failed"; exit 1; }
  else
    git worktree add -b "$BRANCH" "$WORKTREE" main || { echo "worktree add (new) failed"; exit 1; }
  fi

  cd "$WORKTREE" || exit 1
  BEFORE_SHA="$(git rev-parse HEAD)"
  echo "base $BEFORE_SHA"

  PROMPT="/nightly-batch

This is the scheduler improving ITSELF, unattended, behind a HUMAN REVIEW GATE, running in a USAGE-PACED cycle (it fires whenever you have spare weekly quota, not on a fixed clock). Everything lands as commits on branch $BRANCH for a person to review and merge -- nothing goes live automatically. Today's earlier paced cycles are already committed on this branch: run 'git log --oneline main..HEAD' FIRST and CONTINUE from there, don't redo finished work.

Read .claude/scheduler/FOCUS.md next -- it is this project's scope AND backlog. Pick the NEXT highest-value, LOWEST-RISK improvement you can fully finish AND verify this cycle. This repo is the meta-tool that controls every other project's scheduling, so correctness beats volume.

HARD RULES (infrastructure, not an app):
  * Commit ONLY in this working directory ($WORKTREE) on branch $BRANCH. Touch nothing outside it.
  * NEVER run 'crontab', and NEVER run bin/sync-crontab.sh with --apply. Previewing (no --apply) is fine.
  * NEVER edit installed wrappers under ~/.local/bin, or any file outside this repo.
  * Prefer changes verifiable here and now (shellcheck, dry-run, 'env -u SSH_AUTH_SOCK' to simulate cron). If a change can't be safely verified without going live, write it up as a proposal in the report instead of committing it.
  * On a real judgment call, append it to .claude/scheduler/QUESTIONS.md and describe it in the report rather than deciding unilaterally.

Commit each finished change with a clear message. Then append a section for THIS cycle to $REPORT (create if absent) and refresh $REPORTS_DIR/LATEST.md. A change not committed on $BRANCH didn't happen."

  if [ "${SCHED_DRYRUN:-0}" = "1" ]; then
    echo "DRYRUN: skipping claude invocation"; STATUS="dryrun"
  elif claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --max-turns "$MAX_TURNS"; then
    STATUS="done"
  else
    STATUS="FAILED"
  fi

  AFTER_SHA="$(git rev-parse HEAD)"
  cd "$SCHED_REPO"
  git worktree remove --force "$WORKTREE" 2>/dev/null || true

  CRON_AFTER="$(crontab -l 2>/dev/null | md5sum)"
  if [ "$CRON_BEFORE" != "$CRON_AFTER" ]; then
    echo "WARNING: live crontab CHANGED during a paced cycle -- investigate"
    notify-send -u critical "$JOB_NAME" "live crontab modified during a self-run -- investigate $LOG"
  fi

  if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
    echo "cycle $STATUS: new commits on $BRANCH --"
    git log --oneline "main..$BRANCH" 2>/dev/null | head -20
    notify-send "$JOB_NAME" "New commits on $BRANCH awaiting review/merge." 2>/dev/null || true
  else
    echo "cycle $STATUS: no commits"
  fi
  echo "==== $STATUS $(date -Is) ===="
  [ "$STATUS" = "FAILED" ] && exit 1
  exit 0
} >> "$LOG" 2>&1
