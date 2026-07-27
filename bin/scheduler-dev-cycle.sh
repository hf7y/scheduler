#!/usr/bin/env bash
# scheduler-dev-cycle.sh -- ONE review-gated self-development cycle.
#
# The usage-paced runner calls this when the scheduler's turn comes up (instead
# of the old fixed 03:00 nightly). Built to be called REPEATEDLY through the
# day: all of a day's cycles accumulate on ONE branch  paced/<date>  (each cycle
# branches from that branch's tip and commits back onto it).
#
# REVIEW IS REVERT-BASED, NOT A PRE-PUSH GATE (2026-07-24, human-directed --
# see DESIGN-NOTES.md "push-on-cycle, not push-on-morning-review"). Each
# cycle that produces commits merges $BRANCH into local main AND PUSHES TO
# ORIGIN IMMEDIATELY, same cycle, no waiting for a human. This file used to
# say the opposite ("never touching main, never pushing") -- that was the
# OLD policy and is WRONG now; don't revert to it. The human reviews after
# the fact (git show/git log -p on the merge, git revert -m 1 <sha> to
# undo) same as every other push this repo makes (see CLAUDE.md's push
# permission). This is DURABLE, not a one-off: the trigger was multi-host
# self-dev (mandark + dexter both running this script need each other's
# commits within one pull tick, not held back up to 24h for a morning
# review -- a same-day divergence incident is exactly what a held-back
# push caused before this fix), but the policy applies unconditionally,
# single host or not.
#
# Exit 0 on a clean run (with or without commits), non-zero only on setup
# failure. Honours SCHED_DRYRUN=1 (skips the claude call) for plumbing tests.
set -uo pipefail

JOB_NAME="scheduler-paced-dev"

# SCHED_REPO used to be hardcoded to mandark's checkout
# ("/home/zach/Documents/Project Archive/scheduler"), which is the only thing
# that tied this script to one machine -- and it lives INSIDE the repo it
# operates on, so the location is derivable instead. Made host-agnostic
# 2026-07-24 during dexter's bring-up (see DESIGN-NOTES.md for why this
# became host-agnostic rather than dexter getting a second near-identical
# wrapper). Resolution order, first match wins:
#   1. $SCHED_REPO from the environment (explicit override)
#   2. the repo this script actually lives in (symlinks resolved, so an
#      installed ~/.local/bin/scheduler-dev-cycle.sh still finds it)
#   3. mandark's original absolute path, for a copied-not-symlinked install
# Identified as a repo by .git PLUS a file only this repo has, so a stray
# parent git repo can never be mistaken for the scheduler checkout.
SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"
[ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_REPO="$(cd "$(dirname "$SELF_REAL")/.." 2>/dev/null && pwd)"
: "${SELF_REPO:=}"
if [ -z "${SCHED_REPO:-}" ]; then
  if [ -n "$SELF_REPO" ] && [ -e "$SELF_REPO/.git" ] && [ -f "$SELF_REPO/bin/usage-paced-runner.sh" ]; then
    SCHED_REPO="$SELF_REPO"
  else
    SCHED_REPO="/home/zach/Documents/Project Archive/scheduler"
  fi
fi

STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
WORKTREE="$STATE_DIR/worktree"
REPORTS_DIR="$HOME/reports/scheduler"
DATE="$(date +%F)"
BRANCH="paced/$DATE"
REPORT="$REPORTS_DIR/${DATE}-paced.md"

# Merge policy toggle (2026-07-19, human-directed; push behavior updated
# 2026-07-24 -- see file header): default is "merge" -- each cycle's
# finished commits get merged into local main AND PUSHED to origin/main
# immediately (a human reviews after the fact and can `git revert -m 1
# <merge-sha>` same as any other merge commit). Set to "branch" as a manual
# escape hatch to pause auto-merge/push entirely (commits sit on $BRANCH
# only, a human merges+pushes by hand) -- a deliberate opt-out for a
# specific risky stretch, not the recommended default; don't read its
# presence as "the safer everyday choice," that framing is retired along
# with the old hold-for-morning-review policy. Toggle with:
#   echo branch > ~/.local/share/scheduler-paced-dev/merge_mode   # manual pause
#   echo merge  > ~/.local/share/scheduler-paced-dev/merge_mode   # default
# or just: rm ~/.local/share/scheduler-paced-dev/merge_mode  (resets to merge)
MERGE_MODE_FILE="$STATE_DIR/merge_mode"
merge_mode() { [ -f "$MERGE_MODE_FILE" ] && cat "$MERGE_MODE_FILE" || echo "merge"; }

# ---- Reconciliation of PRIOR cycles (2026-07-27) --------------------------
#
# WHAT THIS RETIRES: the two "left for a human" dead ends further down --
# the dirty-tree fallback ("merge_mode=merge but ... isn't clean/on-main
# ... safe fallback") and the failed-push path ("CRITICAL: could not push
# main after this cycle"). Both were safe in the moment and both ended the
# cycle in a state that NOTHING EVER REVISITED. Because the day's branch is
# created with `git worktree add -b paced/<date> ... main` (below), the next
# day forks from `main` and the previous day's unmerged tail is orphaned
# permanently -- no mechanism pointed at it again. The prose fallbacks stay
# (they are still the right immediate move); what changes is that they are
# now the FIRST half of a retry, not the whole story.
#
# Verified damage this was written against, re-probed not quoted --
# `git log --oneline main..paced/2026-07-25` and `...07-26`, 2026-07-27:
# 7 unmerged commits each, confirmed ABSENT from main file-by-file (not
# superseded by later cycles), including `bin/deploy-drift-check.sh`,
# `schedule/_usage.conf`, `docs/scheduler-cli.md`, and the `RESCUE_REF`
# unpushed-commit guard in `lib/sweep-loop-common.sh`. Root cause read out
# of ~/.local/share/scheduler-paced-dev/run.log, which logged the dirty-tree
# fallback three times on 07-26 and never merged that branch again.
#
# WHY AT CYCLE START: the blockers are transient (a human mid-edit in vim,
# a `sweep` autocommit in flight, a network blip on push) but the loss was
# permanent. Running first means a blocker costs ONE CYCLE instead of the
# work. Under the paced runner this retries every few minutes, so a branch
# stays stranded only as long as the tree is genuinely busy.
#
# Never destructive: a conflicting merge is aborted and left for a human,
# and no branch ref is ever deleted. A conflict is reported EVERY cycle
# (honest -- the debt is still there) but notified only once per branch, so
# a real blockage doesn't become notification spam that trains you to
# ignore it.
reconcile_prior_cycles() {
  local mode b n ahead marker merged_any=0 conflicted=0

  mode="$(merge_mode)"
  if [ "$mode" != "merge" ]; then
    echo "reconcile: merge_mode=$mode (manual pause) -- prior branches stay unmerged BY CHOICE, not by accident"
    return 0
  fi

  # Same precondition as the merge below: never touch a tree someone else
  # is working in. Difference from the old behavior is only what happens
  # next -- this returns to be retried, it does not abandon anything.
  if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" != "main" ] || [ -n "$(git status --porcelain)" ]; then
    echo "reconcile: SKIPPED -- $SCHED_REPO is not clean/on-main (likely a human mid-edit). Retried next cycle; nothing is orphaned by this skip."
    return 0
  fi

  git fetch origin main --quiet 2>&1 || echo "reconcile: fetch failed (network?) -- proceeding against local refs"

  # Fast-forward onto origin first so merges land on the current base --
  # but only when main has nothing of its own to lose. If main is ahead
  # (the failed-push case) the push retry below is what resolves it.
  if [ "$(git rev-list --count origin/main..main 2>/dev/null || echo 0)" -eq 0 ]; then
    git merge --ff-only origin/main --quiet 2>&1 || true
  fi

  # (1) Every paced/<date> branch still holding commits main lacks --
  # including today's, if an earlier cycle today failed to merge it.
  # Oldest first, so recovered history lands in the order it was written.
  for b in $(git for-each-ref --format='%(refname:short)' 'refs/heads/paced/*' 2>/dev/null | sort); do
    n="$(git rev-list --count "main..$b" 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] || continue
    marker="$STATE_DIR/conflict-${b//\//-}"
    echo "reconcile: $b holds $n commit(s) not on main -- attempting merge"
    if git merge --no-ff --no-edit "$b" >/dev/null 2>&1; then
      merged_any=1
      echo "reconcile: MERGED $b into main -- $(git rev-parse HEAD) (revert with: git revert -m 1 $(git rev-parse HEAD))"
      rm -f "$marker"
    else
      git merge --abort 2>/dev/null || true
      conflicted=$((conflicted + 1))
      echo "reconcile: CONFLICT merging $b -- aborted, main UNCHANGED. Needs a human: git merge $b"
      if [ ! -f "$marker" ]; then
        : > "$marker"
        notify-send -u critical "$JOB_NAME" "$b conflicts with main -- $n commit(s) stranded, needs a hand merge (see $LOG)" 2>/dev/null || true
      fi
    fi
  done

  # (2) Push whatever is now ahead -- both the merges just made and any
  # commits a previous cycle merged locally but could not push.
  ahead="$(git rev-list --count origin/main..main 2>/dev/null || echo 0)"
  if [ "${ahead:-0}" -gt 0 ]; then
    echo "reconcile: local main is $ahead commit(s) ahead of origin/main -- pushing"
    if git push origin main --quiet 2>&1; then
      echo "reconcile: pushed -- local main and origin/main are level"
    else
      echo "reconcile: push FAILED -- local main left ahead of origin, will retry next cycle"
      notify-send -u critical "$JOB_NAME" "reconcile could not push main ($ahead ahead) -- see $LOG" 2>/dev/null || true
    fi
  fi

  # The summary line must never contradict the lines above it. An earlier
  # draft printed "nothing to reconcile" straight after reporting two
  # conflicts, because it keyed only on merged_any and ahead -- caught by
  # the live witness in tests/reconcile-witness.sh, case 7.
  if [ "$conflicted" -gt 0 ]; then
    echo "reconcile: $conflicted branch(es) STILL STRANDED after this pass -- not clean, needs a hand merge"
  elif [ "$merged_any" = "0" ] && [ "${ahead:-0}" -eq 0 ]; then
    echo "reconcile: nothing to reconcile (no unmerged paced/* branches, main level with origin)"
  fi
}

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

  # Recover anything a previous cycle could not merge or push, BEFORE the
  # branch below is created -- `git worktree add -b ... main` forks from
  # main, so reconciling first is what stops a new day's branch from
  # stepping over the previous day's stranded tail. See the function's
  # header for the incident this was written against.
  reconcile_prior_cycles

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

Read .scheduler/FOCUS.md next -- it is this project's scope AND backlog. Pick the NEXT highest-value, LOWEST-RISK improvement you can fully finish AND verify this cycle. This repo is the meta-tool that controls every other project's scheduling, so correctness beats volume.

HARD RULES (infrastructure, not an app):
  * Commit ONLY in this working directory ($WORKTREE) on branch $BRANCH. Touch nothing outside it.
  * NEVER run 'crontab', and NEVER run bin/sync-crontab.sh with --apply. Previewing (no --apply) is fine.
  * NEVER edit installed wrappers under ~/.local/bin, or any file outside this repo.
  * Prefer changes verifiable here and now (shellcheck, dry-run, 'env -u SSH_AUTH_SOCK' to simulate cron). If a change can't be safely verified without going live, write it up as a proposal in the report instead of committing it.
  * On a real judgment call, append it to .scheduler/QUESTIONS.md and describe it in the report rather than deciding unilaterally.

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
    notify-send -u critical "$JOB_NAME" "live crontab modified during a self-run -- investigate $LOG" 2>/dev/null || true
  fi

  MERGED=0
  PUSHED=0
  if [ "$AFTER_SHA" != "$BEFORE_SHA" ] && [ "$STATUS" = "done" ]; then
    MODE="$(merge_mode)"
    if [ "$MODE" = "merge" ]; then
      if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "main" ] && [ -z "$(git status --porcelain)" ]; then
        # Refresh main immediately before merging -- minimizes (does not
        # eliminate) the chance of merging this cycle's work onto a base
        # the OTHER host has already moved past. ff-only: if this fails,
        # local main already has unpushed history ahead of origin, which
        # shouldn't happen once every cycle pushes promptly (see below) --
        # fail loud and proceed rather than silently building on stale main.
        if ! git fetch origin main --quiet 2>&1; then
          echo "fetch before merge failed (network?) -- proceeding on possibly-stale main"
        elif ! git merge --ff-only origin/main --quiet 2>&1; then
          echo "WARNING: local main has unpushed history ahead of origin (unexpected under push-every-cycle) -- proceeding anyway, investigate after"
        fi
        if git merge --no-ff --no-edit "$BRANCH"; then
          MERGED=1
          MERGE_SHA="$(git rev-parse HEAD)"
          echo "merged $BRANCH into main -- $MERGE_SHA (revert with: git revert -m 1 $MERGE_SHA)"
          # Push immediately -- see DESIGN-NOTES.md 2026-07-24 "push-on-cycle,
          # not push-on-morning-review". Review is revert-based, not a
          # pre-push gate: this repo's CLAUDE.md already grants push
          # permission generally, so holding a self-dev cycle's commits
          # back from origin was never actually the safety mechanism it
          # looked like -- it just added staleness risk for no review
          # benefit. Two attempts: a push rejected because origin moved
          # between the fetch above and now gets one reconcile-and-retry
          # before giving up loudly.
          for attempt in 1 2; do
            if git push origin main --quiet 2>&1; then
              PUSHED=1
              echo "pushed main -- $MERGE_SHA"
              break
            fi
            echo "push attempt $attempt failed -- fetching + reconciling"
            git fetch origin main --quiet 2>&1
            git merge --no-ff --no-edit origin/main --quiet 2>&1 \
              || { echo "reconcile merge failed -- giving up, local main left ahead of origin for a human"; break; }
          done
          if [ "$PUSHED" = "1" ]; then
            notify-send "$JOB_NAME" "Pushed self-dev cycle $MERGE_SHA to origin/main -- review via revert: git revert -m 1 $MERGE_SHA" 2>/dev/null || true
          else
            echo "CRITICAL: could not push main after this cycle -- local main is ahead of origin/main. Retried automatically by reconcile_prior_cycles() next cycle (since 2026-07-27); needs a human only if that keeps failing."
            notify-send -u critical "$JOB_NAME" "self-dev cycle merged but COULD NOT PUSH -- local main ahead of origin, investigate $LOG" 2>/dev/null || true
          fi
        else
          echo "merge into main FAILED (conflict?) -- aborting merge, leaving $BRANCH for manual review"
          git merge --abort 2>/dev/null || true
        fi
      else
        echo "merge_mode=merge but $SCHED_REPO isn't clean/on-main right now (likely another session's in-progress edit) -- leaving $BRANCH unmerged. NOT a dead end since 2026-07-27: reconcile_prior_cycles() retries this at the start of every later cycle."
      fi
    else
      echo "merge_mode=$MODE -- leaving $BRANCH unmerged for manual review (manual pause, not the default)"
    fi
  fi

  if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
    if [ "$MERGED" = "1" ] && [ "$PUSHED" = "1" ]; then
      echo "cycle $STATUS: new commits, MERGED and PUSHED to origin/main -- review with: git show $MERGE_SHA / git log -p $BEFORE_SHA..$AFTER_SHA"
    elif [ "$MERGED" = "1" ]; then
      echo "cycle $STATUS: new commits, MERGED to local main but NOT PUSHED (see CRITICAL line above) -- needs a human"
    else
      echo "cycle $STATUS: new commits on $BRANCH (unmerged) --"
      git log --oneline "main..$BRANCH" 2>/dev/null | head -20
      notify-send "$JOB_NAME" "New commits on $BRANCH awaiting review/merge." 2>/dev/null || true
    fi
  else
    echo "cycle $STATUS: no commits"
  fi
  echo "==== $STATUS $(date -Is) ===="
  [ "$STATUS" = "FAILED" ] && exit 1
  exit 0
} >> "$LOG" 2>&1
