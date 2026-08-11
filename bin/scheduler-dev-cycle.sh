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
# ("/home/zach/Documents/Projects/scheduler"), which is the only thing
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
    SCHED_REPO="/home/zach/Documents/Projects/scheduler"
  fi
fi

STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
# WHERE THE CYCLE WORKS. A THROWAWAY CLONE since 2026-08-11, a linked git
# worktree before that -- hf7y/scheduler#49, and Zach on 2026-08-06: "we
# should not have any more worktrees after tonight." The 8 worktrees that
# issue surveyed here were removed the same night and the estate was back to
# 30 five days later, because this script and bin/overnight-dev.sh put one
# back on every run. Clearing the directories was never the fix.
#
# A clone gives the cycle what the worktree gave it -- an isolated tree, the
# live checkout left alone on main -- and drops the two things it also gave:
# a registration in $SCHED_REPO/.git/worktrees that outlived the run, and a
# SHARED ref store, which is the concurrent-writer hazard CLAUDE.md's subagent
# rules exist for. The cost is one explicit push to publish the branch back,
# below, in place of a ref update that used to happen implicitly.
#
# LEGACY_WORKTREE is the old path, kept ONLY so a registration left by a cycle
# that ran before this change can still be cleared. Nothing is created there.
LEGACY_WORKTREE="$STATE_DIR/worktree"
DEV_CLONE="$STATE_DIR/clone"
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
# forked from `main` (below -- with a worktree until 2026-08-11, a clone
# since), the next day forks from `main` too and the previous day's unmerged tail is orphaned
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
        # q-756f82: a bare `|| true` guards a notify-send that FAILS, not one
        # that NEVER RETURNS (dbus socket present, nobody listening -- live
        # 2026-07-28). Bounded so a decoration cannot wedge the job.
        timeout 5 notify-send -u critical "$JOB_NAME" "$b conflicts with main -- $n commit(s) stranded, needs a hand merge (see $LOG)" 2>/dev/null || true
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
      timeout 5 notify-send -u critical "$JOB_NAME" "reconcile could not push main ($ahead ahead) -- see $LOG" 2>/dev/null || true
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

# ---- The shared lockout (2026-07-27) --------------------------------------
# This script used to take the private $LOCK above and NOTHING else: no
# registry lock, no .active marker, and -- the one that mattered -- no read of
# the .interactive marker that says a human is in this repo. Every OTHER
# project's job got both halves from lib/sweep-loop-common.sh; the scheduler's
# own cycle, the one editing the scheduler, was the single job exempt from the
# scheduler's own lockout.
#
# In its place it inferred human presence from `git status --porcelain` being
# clean (see the merge below). That proxy is what stranded 14 commits across
# 2026-07-25/26: a dirty tree is not a person (a `sweep` autocommit trips it
# too), it cannot tell "busy now" from "busy forever" so it has no starvation
# cap, and its only response was to give up permanently.
#
# The clean-tree test STAYS where it is -- you genuinely cannot merge into a
# dirty tree -- but it is now a git precondition, which is all it ever was.
# "Is a human here" is answered by the marker, which is the question it was
# built for.
# shellcheck source=../lib/registry-lock.sh
. "$SCHED_REPO/lib/registry-lock.sh"

PROJECT_KEY="scheduler"
DEFER_STREAK_FILE="$STATE_DIR/interactive_defer_since"
[ -f "$STATE_DIR/interactive_deferrals" ] && rm -f "$STATE_DIR/interactive_deferrals"

if ! registry_claim "$PROJECT_KEY" "$JOB_NAME" "paced-dev"; then
  echo "$(date -Is) project '$PROJECT_KEY' already has an active job (${REGISTRY_HOLDER:-unknown}) -- skipping to avoid a concurrent-push conflict" >> "$LOG"
  exit 0
fi

if registry_should_defer "$PROJECT_KEY" "$DEFER_STREAK_FILE" "$SCHED_REPO"; then
  echo "$(date -Is) deferred -- '$PROJECT_KEY' is being worked in (pid $REGISTRY_DEFER_PID, since ${REGISTRY_DEFER_SINCE:-unknown}): $REGISTRY_DEFER_REASON. Standing down while that holds; backstop at ${REGISTRY_DEFER_MAX_HOURS}h continuous, currently ${REGISTRY_DEFER_STREAK_MIN}m. Nothing is stranded by deferring -- reconcile_prior_cycles() picks up any unmerged branch next cycle." >> "$LOG"
  registry_release
  exit 4
fi
if [ "${REGISTRY_DEFER_CAPPED:-0}" = "1" ]; then
  echo "$(date -Is) WARNING: proceeding despite an ACTIVE repo on '$PROJECT_KEY' (pid $REGISTRY_DEFER_PID, since ${REGISTRY_DEFER_SINCE:-unknown}) -- $REGISTRY_DEFER_REASON. This cycle may write files you have open." >> "$LOG"
  timeout 5 notify-send -u critical "$JOB_NAME: running while you work" "scheduler self-dev has deferred continuously for ${REGISTRY_DEFER_STREAK_MIN}m (backstop ${REGISTRY_DEFER_MAX_HOURS}h) and is now running anyway." 2>/dev/null || true
fi
[ -f "$LOG" ] && { tail -n 4000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }

# The trap deliberately does NOT remove $DEV_CLONE. Under a worktree, forcing
# the removal cost nothing: the branch ref lived in the shared .git, so the
# commits survived. A clone holds the ONLY copy until the publish below
# succeeds, so a trap that removed it would destroy the work of any cycle
# killed between its commit and its push. An abandoned clone is a directory
# under $STATE_DIR -- not a registered worktree, and the next cycle salvages
# any branch in it before discarding it.
cleanup() {
  registry_release
  cd "$SCHED_REPO" 2>/dev/null && git worktree remove --force "$LEGACY_WORKTREE" 2>/dev/null || true
}
trap cleanup EXIT

{
  echo "==== $(date -Is) paced-dev cycle on $BRANCH ===="
  cd "$SCHED_REPO" || { echo "cannot cd $SCHED_REPO"; exit 1; }
  CRON_BEFORE="$(crontab -l 2>/dev/null | md5sum)"

  # Clears a registration left by a cycle that ran before 2026-08-11. This
  # creates nothing; it is the un-doing half of hf7y/scheduler#49.
  git worktree remove --force "$LEGACY_WORKTREE" 2>/dev/null || true
  git worktree prune

  # SALVAGE BEFORE DISCARD. A cycle killed between its commit and its publish
  # leaves the only copy of that work in the clone below.
  # reconcile_prior_cycles() recovers branches that reached $SCHED_REPO; this
  # recovers the ones that never did. Same lesson as that function's header,
  # one step earlier in the pipe. Pushes that are refused (main is checked out
  # here; an older branch is behind) are not findings and stay quiet.
  if [ -d "$DEV_CLONE/.git" ]; then
    mapfile -t _stranded < <(git -C "$DEV_CLONE" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
    for _b in ${_stranded[@]+"${_stranded[@]}"}; do
      [ "$_b" = "main" ] && continue
      git -C "$DEV_CLONE" push -q "$SCHED_REPO" "$_b:refs/heads/$_b" 2>/dev/null \
        && echo "salvaged $_b from an interrupted cycle's clone"
    done
  fi
  rm -rf "$DEV_CLONE"

  # Recover anything a previous cycle could not merge or push, BEFORE the
  # branch below is created -- a new day's branch forks from main, so
  # reconciling first is what stops it from stepping over the previous day's
  # stranded tail. See the function's header for the incident this was
  # written against.
  reconcile_prior_cycles

  git clone -q "$SCHED_REPO" "$DEV_CLONE" || { echo "clone of $SCHED_REPO failed"; exit 1; }

  # Branch paced/<date>: create from main on the day's first cycle, else reuse.
  # Asked of $SCHED_REPO and not of the clone, so the answer is the same fact
  # the merge phase below will act on. --no-track: the branch is published by
  # an explicit refspec push, and an upstream pointing at a local clone would
  # only be a second, wrong answer to "where does this branch live".
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$DEV_CLONE" checkout -q -b "$BRANCH" --no-track "origin/$BRANCH" \
      || { echo "checkout (reuse $BRANCH) failed"; exit 1; }
  else
    git -C "$DEV_CLONE" checkout -q -b "$BRANCH" --no-track origin/main \
      || { echo "checkout (new $BRANCH) failed"; exit 1; }
  fi

  cd "$DEV_CLONE" || exit 1
  BEFORE_SHA="$(git rev-parse HEAD)"
  echo "base $BEFORE_SHA"

  PROMPT="/nightly-batch

This is the scheduler improving ITSELF, unattended, behind a HUMAN REVIEW GATE, running in a USAGE-PACED cycle (it fires whenever you have spare weekly quota, not on a fixed clock). Everything lands as commits on branch $BRANCH for a person to review and merge -- nothing goes live automatically. Today's earlier paced cycles are already committed on this branch: run 'git log --oneline main..HEAD' FIRST and CONTINUE from there, don't redo finished work.

Read .scheduler/FOCUS.md next -- it is this project's scope AND backlog. Pick the NEXT highest-value, LOWEST-RISK improvement you can fully finish AND verify this cycle. This repo is the meta-tool that controls every other project's scheduling, so correctness beats volume.

HARD RULES (infrastructure, not an app):
  * Commit ONLY in this working directory ($DEV_CLONE) on branch $BRANCH. Touch nothing outside it.
  * NEVER run 'crontab', and NEVER run bin/sync-crontab.sh with --apply. Previewing (no --apply) is fine.
  * NEVER edit installed wrappers under ~/.local/bin, or any file outside this repo.
  * Prefer changes verifiable here and now (shellcheck, dry-run, 'env -u SSH_AUTH_SOCK' to simulate cron). If a change can't be safely verified without going live, write it up as a proposal in the report instead of committing it.
  * On a real judgment call, append it to .scheduler/QUESTIONS.md and describe it in the report rather than deciding unilaterally.

Commit each finished change with a clear message. Then append a section for THIS cycle to $REPORT (create if absent) and refresh the LATEST.md pointer by running: bin/publish-report.sh $PROJECT_KEY $(basename "$REPORT") -- do NOT 'cp' onto LATEST.md, it is a symlink and cp follows it straight into a past report (that destroyed 2026-07-27's report). A change not committed on $BRANCH didn't happen."

  # PER-CYCLE TRANSCRIPT (2026-07-29). Until this existed, a cycle that hit
  # --max-turns left EXACTLY ONE line of evidence: "Error: Reached max turns
  # (60)". Not a gap at the margins -- a total one. `claude -p` with the default
  # text output format prints only the FINAL result, so on the max-turns path
  # there is no final result and it prints nothing; intermediate tool calls are
  # never emitted in any case. The body is already wrapped in
  # `{ ... } >> "$LOG" 2>&1`, so this was never a missing redirect. There was
  # simply nothing to redirect.
  #
  # WHY IT MATTERED, concretely: on 2026-07-29 THE PLAY's bootstrap turn failed
  # four times, three on max-turns, once burning 60 turns and 12 minutes for
  # ZERO commits. "60 turns is too few for this bar" and "the agent is thrashing
  # and would fail at any ceiling" demand OPPOSITE fixes -- raise the ceiling
  # vs. shrink the bar -- and nothing recorded anywhere could tell them apart.
  # Retrying blind burns quota and learns nothing.
  #
  # stream-json goes to its own FILE, not into run.log: `scheduler status`
  # slices run.log for the ====-delimited last-run record, and tens of thousands
  # of JSON lines per cycle would swamp the signal it reads. run.log keeps the
  # summary and NAMES the transcript; the transcript holds the turns.
  # --verbose is required by stream-json in print mode.
  TRANSCRIPT_DIR="$STATE_DIR/transcripts"
  mkdir -p "$TRANSCRIPT_DIR" 2>/dev/null || true
  TRANSCRIPT="$TRANSCRIPT_DIR/$(date +%Y%m%dT%H%M%S).jsonl"

  if [ "${SCHED_DRYRUN:-0}" = "1" ]; then
    echo "DRYRUN: skipping claude invocation"; STATUS="dryrun"
  elif claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --max-turns "$MAX_TURNS" \
         --output-format stream-json --verbose > "$TRANSCRIPT" 2>&1; then
    STATUS="done"
  else
    STATUS="FAILED"
  fi

  if [ -s "$TRANSCRIPT" ]; then
    # Name it in run.log with enough shape to decide whether to open it. The
    # tool-name histogram is the thrash/insufficiency discriminator: 60 turns of
    # varied edits reads very differently from 60 turns re-reading one file.
    echo "transcript: $TRANSCRIPT ($(wc -l < "$TRANSCRIPT") events; tools: $(grep -o '"name":"[A-Za-z_]*"' "$TRANSCRIPT" 2>/dev/null | sed 's/.*:"//;s/"//' | sort | uniq -c | sort -rn | head -6 | awk '{printf "%s=%s ", $2, $1}'))"
  elif [ "${SCHED_DRYRUN:-0}" != "1" ]; then
    # An empty transcript on a real cycle means the invocation produced nothing
    # at all -- said out loud, not left as a silent 0-byte file.
    echo "transcript: EMPTY ($TRANSCRIPT) -- claude produced no output; that is itself the finding"
  fi

  AFTER_SHA="$(git rev-parse HEAD)"
  # cwd is $DEV_CLONE here, and what follows removes it. An unguarded cd
  # (SC2164) means that runs from inside the directory being deleted,
  # discarding whatever the cycle just wrote. Refuse instead.
  cd "$SCHED_REPO" || { echo "cannot cd back to $SCHED_REPO -- refusing to delete the clone from inside it"; exit 1; }

  # PUBLISH. Under a worktree this step did not exist: the branch lived in
  # $SCHED_REPO's own ref store, so committing in the worktree moved
  # refs/heads/$BRANCH and everything below saw it. A clone has its own ref
  # store, so the branch is pushed back before the merge phase reads it.
  #
  # A failed publish is the one place this design can lose work the old one
  # could not, so it is loud and the clone is NOT deleted: the commits are
  # still in it, the message says how to get them, and the salvage pass at the
  # top of the next cycle does it without being asked.
  if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
    if git -C "$DEV_CLONE" push -q "$SCHED_REPO" "$BRANCH:refs/heads/$BRANCH"; then
      echo "published $BRANCH into $SCHED_REPO"
      rm -rf "$DEV_CLONE"
    else
      echo "CRITICAL: this cycle committed on $BRANCH and could NOT publish it into $SCHED_REPO. The commits exist only in $DEV_CLONE, which is deliberately left in place. Recover with: git -C $SCHED_REPO fetch $DEV_CLONE $BRANCH:$BRANCH"
      timeout 5 notify-send -u critical "$JOB_NAME" "self-dev cycle could not publish $BRANCH -- commits are in $DEV_CLONE, see $LOG" 2>/dev/null || true
    fi
  else
    rm -rf "$DEV_CLONE"
  fi

  CRON_AFTER="$(crontab -l 2>/dev/null | md5sum)"
  if [ "$CRON_BEFORE" != "$CRON_AFTER" ]; then
    echo "WARNING: live crontab CHANGED during a paced cycle -- investigate"
    timeout 5 notify-send -u critical "$JOB_NAME" "live crontab modified during a self-run -- investigate $LOG" 2>/dev/null || true
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
            timeout 5 notify-send "$JOB_NAME" "Pushed self-dev cycle $MERGE_SHA to origin/main -- review via revert: git revert -m 1 $MERGE_SHA" 2>/dev/null || true
          else
            echo "CRITICAL: could not push main after this cycle -- local main is ahead of origin/main. Retried automatically by reconcile_prior_cycles() next cycle (since 2026-07-27); needs a human only if that keeps failing."
            timeout 5 notify-send -u critical "$JOB_NAME" "self-dev cycle merged but COULD NOT PUSH -- local main ahead of origin, investigate $LOG" 2>/dev/null || true
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
      timeout 5 notify-send "$JOB_NAME" "New commits on $BRANCH awaiting review/merge." 2>/dev/null || true
    fi
  else
    echo "cycle $STATUS: no commits"
  fi
  echo "==== $STATUS $(date -Is) ===="
  [ "$STATUS" = "FAILED" ] && exit 1
  exit 0
} >> "$LOG" 2>&1
