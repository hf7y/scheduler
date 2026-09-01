#!/usr/bin/env bash
# Overnight self-development driver for the scheduler repo.
#
# The 03:00 cron job (scheduler-nightly-batch-loop.sh) is a SINGLE
# review-gated run and re-running it the same day DESTROYS the prior branch.
# This driver is the "keep developing while I sleep" companion: it runs a
# CHAIN of cycles through the night, each in a throwaway git CLONE, and --
# crucially -- each productive cycle branches from the PREVIOUS productive
# cycle so work ACCUMULATES instead of clobbering.
#
# IT WAS A WORKTREE UNTIL 2026-08-11 (hf7y/scheduler#49; Zach, 2026-08-06:
# "we should not have any more worktrees after tonight"). Each cycle created
# one and each cycle removed it, so this was the tidier of the two creators in
# this repo -- but a cycle killed mid-run left the registration behind, and
# the shared .git it borrowed is the concurrent-writer hazard CLAUDE.md's
# subagent rules exist for. A clone gives the same isolation, registers
# nothing, and costs one explicit push per productive cycle to publish the
# branch the morning review reads.
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
SCHED_REPO="/home/zach/Documents/Projects/scheduler"
STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
# LEGACY_WORKTREE is the old path, kept ONLY so a registration left by a run
# from before 2026-08-11 can still be cleared. Nothing is created there.
LEGACY_WORKTREE="$STATE_DIR/worktree"
DEV_CLONE="$STATE_DIR/clone"
REPORTS_DIR="$HOME/reports/scheduler"
DATE="$(date +%F)"
REPORT="$REPORTS_DIR/${DATE}-overnight.md"

MAX_TURNS="${MAX_TURNS:-60}"
MAX_CYCLES="${MAX_CYCLES:-5}"
GAP_MINUTES="${GAP_MINUTES:-55}"
DEADLINE_HHMM="${DEADLINE_HHMM:-0830}"   # don't START a new cycle after this local time
ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep"
# node_bin_dir() -- THIS account's `claude` dir, discovered, not assumed.
# Same fix and same shape as bin/usage-paced-runner.sh's node_bin_dir() and
# lib/sweep-loop-common.sh's copy (hf7y/scheduler#366). The literal stays
# LAST, as the fallback, so a host with no nvm resolves exactly as before.
node_bin_dir() {
  local newest
  newest="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
  printf '%s' "${newest:-/home/zach/.nvm/versions/node/v25.2.1/bin}"
}
NODE_BIN_DIR="${NODE_BIN_DIR:-$(node_bin_dir)}"

[ -d "$NODE_BIN_DIR" ] && export PATH="$NODE_BIN_DIR:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

mkdir -p "$STATE_DIR" "$REPORTS_DIR"

# THE MISS IS LOUD. This driver is about to invoke `claude -p` for real
# cycles overnight, so an unresolved NODE_BIN_DIR is reported here rather
# than discovered at 8am as a night of cycles that each produced nothing.
command -v claude >/dev/null 2>&1 || echo "$(date -Is) CRITICAL: no \`claude\` on PATH after resolution (NODE_BIN_DIR=$NODE_BIN_DIR, $([ -d "$NODE_BIN_DIR" ] && echo present || echo ABSENT)) -- every cycle tonight will fail outright." >> "$LOG"

exec 200>"$LOCK"
if ! flock -n 200; then
  echo "$(date -Is) overnight-dev already running, skipping" >> "$LOG"
  exit 0
fi

[ -f "$LOG" ] && { tail -n 8000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }

# The trap clears a legacy registration and nothing else. It must NOT rm the
# clone: with a worktree the branch ref lived in the shared .git so a forced
# removal cost no commits, whereas the clone holds the only copy until the
# push below succeeds. An abandoned clone is a directory under $STATE_DIR, not
# a registered worktree, and the next cycle salvages any branch in it.
cleanup() { cd "$SCHED_REPO" 2>/dev/null && git worktree remove --force "$LEGACY_WORKTREE" 2>/dev/null || true; }
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

    git worktree remove --force "$LEGACY_WORKTREE" 2>/dev/null || true
    git worktree prune

    # SALVAGE BEFORE DISCARD: a cycle killed between its commit and its push
    # left the only copy of that work in the clone. A refused push (the branch
    # already landed, or is behind) is not a finding and stays quiet.
    if [ -d "$DEV_CLONE/.git" ]; then
      mapfile -t _stranded < <(git -C "$DEV_CLONE" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
      for _b in ${_stranded[@]+"${_stranded[@]}"}; do
        [ "$_b" = "main" ] && continue
        git -C "$DEV_CLONE" push -q "$SCHED_REPO" "$_b:refs/heads/$_b" 2>/dev/null \
          && echo "salvaged $_b from an interrupted cycle's clone"
      done
    fi
    rm -rf "$DEV_CLONE"

    git branch -D "$BRANCH" 2>/dev/null || true
    if ! git clone -q "$SCHED_REPO" "$DEV_CLONE"; then
      echo "cycle $i: clone of $SCHED_REPO failed -- skipping cycle"
      continue
    fi
    if ! git -C "$DEV_CLONE" checkout -q -b "$BRANCH" --no-track "origin/$BASE"; then
      echo "cycle $i: could not branch $BRANCH off $BASE -- skipping cycle"
      rm -rf "$DEV_CLONE"
      continue
    fi

    # The RECOVERY cd is guarded too (SC2164). If both fail we are in an
    # unknown directory, and `continue` walks straight back into a `rm -rf`
    # and a `git branch -D` at the top of the loop.
    cd "$DEV_CLONE" || { cd "$SCHED_REPO" || { echo "cannot cd $SCHED_REPO after a failed clone cd -- stopping"; exit 1; }; continue; }
    BEFORE_SHA="$(git rev-parse HEAD)"

    PROMPT="/nightly-batch

This is the scheduler improving ITSELF overnight, fully unattended, behind a HUMAN REVIEW GATE. Everything you do lands as commits on branch $BRANCH for a person to review and merge in the morning -- nothing goes live automatically. This is one cycle in an overnight CHAIN: earlier cycles tonight may already be committed on this branch. Run 'git log --oneline main..HEAD' FIRST to see what tonight's earlier cycles already did, and CONTINUE from there -- do not redo finished work.

Read 'gh issue list --repo hf7y/scheduler --limit 200' next -- the tracker is this project's scope AND backlog. Read the COMMENTS on an issue before treating it as unaddressed; Zach answers by commenting and leaves the issue open, so open is not evidence of unaddressed work. Pick the NEXT highest-value, LOWEST-RISK improvement you can fully finish AND verify this cycle. This repo is the meta-tool that controls every other project's cron jobs, so correctness beats volume: one well-tested change is worth more than three risky ones.

HARD RULES (this is infrastructure, not an app):
  * Make changes ONLY as commits in THIS working directory ($DEV_CLONE) on branch $BRANCH. Touch nothing outside it.
  * NEVER run 'crontab', and NEVER run bin/sync-crontab.sh with --apply. Previewing (no --apply) to validate a schedule change is fine and encouraged.
  * NEVER edit the installed wrapper scripts under ~/.local/bin, or any file outside this repo.
  * Prefer changes verifiable here and now (shellcheck, a dry-run, simulating cron's env with 'env -u SSH_AUTH_SOCK') over changes whose only test is 'wait for tonight'. If a change can't be safely verified without going live, write it up as a proposal in the report instead of committing it.
  * On a real judgment call or anything needing the user's blessing, file it with 'bin/scheduler ask scheduler \"<the question>\"' (it opens a GitHub issue) and describe it in the report rather than deciding unilaterally.

Commit each finished change with a clear message. Then append a section for THIS cycle to $REPORT (create it if absent) and refresh the LATEST.md pointer by running: bin/publish-report.sh scheduler $(basename "$REPORT") -- do NOT 'cp' onto LATEST.md, it is a symlink and cp follows it straight into a past report (that destroyed 2026-07-27's report). The report should cover: what you changed and why, how you verified it, what you deferred and why, and any open questions. A change that isn't committed on $BRANCH didn't happen."

    if [ "${SCHED_DRYRUN:-0}" = "1" ]; then
      echo "DRYRUN: skipping claude invocation"
      STATUS="dryrun"
    elif claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --max-turns "$MAX_TURNS"; then
      STATUS="done"
    else
      STATUS="FAILED"
    fi

    AFTER_SHA="$(git rev-parse HEAD)"
    # cwd is $DEV_CLONE here. If this cd fails and the loop continues, the next
    # cycle runs `rm -rf "$DEV_CLONE"` and `git branch -D` from INSIDE the
    # directory an unattended agent just wrote in. Refuse instead.
    cd "$SCHED_REPO" || { echo "cannot cd back to $SCHED_REPO after cycle $i -- stopping before the destructive clone reset"; exit 1; }

    CRON_AFTER="$(crontab -l 2>/dev/null | md5sum)"
    if [ "$CRON_BEFORE" != "$CRON_AFTER" ]; then
      echo "WARNING: live crontab CHANGED during cycle $i -- investigate"
      # q-756f82: a bare `|| true` guards a notify-send that FAILS, not one
      # that NEVER RETURNS (dbus socket present, nobody listening -- live
      # 2026-07-28). Bounded so a decoration cannot wedge the job.
      timeout 5 notify-send -u critical "$JOB_NAME" "live crontab modified during a self-run -- investigate $LOG" 2>/dev/null || true
    fi

    if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
      # PUBLISH, then chain. The morning review is `git log main..$BASE` in
      # $SCHED_REPO, and the NEXT cycle branches off `origin/$BASE` in a fresh
      # clone -- neither can see this branch until it is pushed back. Under a
      # worktree both were free, because the ref store was shared.
      if git -C "$DEV_CLONE" push -q "$SCHED_REPO" "$BRANCH:refs/heads/$BRANCH"; then
        echo "cycle $i ($STATUS): new commits on $BRANCH --"
        git log --oneline "$BASE..$BRANCH" 2>/dev/null
        rm -rf "$DEV_CLONE"
        BASE="$BRANCH"   # chain: next cycle builds on this productive branch
      else
        # Do NOT advance the chain and do NOT delete the clone: the commits
        # exist only there. The next cycle's salvage pass pushes them.
        echo "cycle $i ($STATUS): CRITICAL -- committed on $BRANCH but could not publish it into $SCHED_REPO. Commits are in $DEV_CLONE and it is left in place; the chain stays on $BASE. Recover with: git -C $SCHED_REPO fetch $DEV_CLONE $BRANCH:$BRANCH"
        timeout 5 notify-send -u critical "$JOB_NAME" "cycle $i could not publish $BRANCH -- commits are in $DEV_CLONE, see $LOG" 2>/dev/null || true
      fi
    else
      echo "cycle $i ($STATUS): no commits -- discarding empty branch $BRANCH"
      rm -rf "$DEV_CLONE"
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
    timeout 5 notify-send "$JOB_NAME" "Overnight work done. Review: git log main..$BASE" 2>/dev/null || true
  fi
} >> "$LOG" 2>&1
