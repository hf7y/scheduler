#!/usr/bin/env bash
# autonomy-merge.sh -- AUTONOMY_TIER="high" engine enforcement.
#
# Built 2026-07-25 (human-directed): AUTONOMY_TIER was declared in 13 of 14
# schedule/*.conf files but enforced nowhere -- a human had to merge every
# nightly-batch branch by hand, with no cadence forcing that to happen, so
# branches piled up (`scheduler blockers`) faster than review capacity.
# Zach's call: for projects where a bad merge is cheap to revert, replace
# the human gate with a test gate. Modeled directly on the one real
# precedent in this repo, bin/scheduler-dev-cycle.sh's merge_mode() (retired
# 2026-08-15, hf7y/scheduler#190 -- the "review is revert-based, not a
# pre-push gate" framing this inherits lives on in DESIGN-NOTES.md's
# 2026-07-24 "push-on-cycle, not push-on-morning-review" entry) -- same
# push-with-retry, same abort-and-leave-for-review fallback on conflict,
# generalized from one hardcoded branch/repo to any branch in any dedicated
# clone.
#
# Sourced by lib/sweep-loop-common.sh. One entry point:
#
#   autonomy_sweep_repo <repo_dir> <default_branch> <tier> <test_cmd> <label>
#
#   repo_dir        the dedicated clone's top-level directory (not a subdir)
#   default_branch  branch to merge into ("" = resolve from origin HEAD)
#   tier            AUTONOMY_TIER value; anything but "high" is a no-op
#   test_cmd        optional shell command run (via eval) on each candidate
#                   branch before merging; empty = merge ungated. Exists
#                   because the gate replaces a human, not a null check --
#                   an empty test_cmd is a deliberate per-project choice
#                   (see schedule/vkv-inventory.conf's comment on why),
#                   not an oversight.
#   label           short string for log/notify lines (JOB_NAME is fine)
#
# Every branch found ahead of default_branch is considered, not just
# whatever branch this run's own subagent happened to create -- a
# nightly-batch prompt can open more than one feature branch per run, and
# this also lets the SAME function double as the one-off backlog sweep
# (bin/scheduler's `autonomy-sweep` subcommand) with no duplicated logic.
#
# A gate failure (tests fail, merge conflicts, push rejected after retry)
# never blocks anything -- it just declines to act and leaves the branch
# exactly where today's manual-review behavior already leaves it. This
# function adds a new way branches can disappear from `scheduler blockers`;
# it never removes the existing one.

autonomy_sweep_repo() {
  local repo_dir="$1" default_branch="$2" tier="$3" test_cmd="$4" label="$5"

  if [ "$tier" != "high" ]; then
    return 0
  fi
  if [ ! -d "$repo_dir/.git" ]; then
    echo "[$label] autonomy sweep: '$repo_dir' is not a git clone -- skipping"
    return 0
  fi

  (
    cd "$repo_dir" || exit 0
    set -uo pipefail

    if ! git fetch origin --quiet; then
      echo "[$label] autonomy sweep: fetch failed -- skipping this run, next cycle retries"
      exit 0
    fi

    if [ -z "$default_branch" ]; then
      default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
    fi
    if [ -z "$default_branch" ]; then
      # Local bare-repo remotes (the crt/realisateur-spawned projects'
      # /home/zach/git-remotes/*.git pattern) never get origin/HEAD set --
      # `git remote show origin` reports "HEAD branch: (unknown)" even
      # though the repo works fine day to day. Fall back to a local "main"
      # if one exists, same as lib/sweep-loop-common.sh's own BRANCH
      # resolution does as its last resort -- announced, not silent.
      if git show-ref --verify --quiet refs/heads/main; then
        default_branch="main"
        echo "[$label] autonomy sweep: origin/HEAD unresolvable -- falling back to local 'main'"
      fi
    fi
    if [ -z "$default_branch" ]; then
      echo "[$label] autonomy sweep: could not resolve default branch -- skipping"
      exit 0
    fi

    if ! git checkout --quiet "$default_branch"; then
      echo "[$label] autonomy sweep: cannot checkout '$default_branch' -- skipping"
      exit 0
    fi
    if [ -n "$(git status --porcelain)" ]; then
      echo "[$label] autonomy sweep: working tree not clean on $default_branch -- skipping this run rather than risk a dirty merge"
      exit 0
    fi
    git merge --ff-only --quiet "origin/$default_branch" 2>/dev/null \
      || echo "[$label] autonomy sweep: WARNING local $default_branch not fast-forward to origin -- proceeding anyway"

    git for-each-ref --format='%(refname:short)' refs/heads/ | while read -r branch; do
      [ "$branch" = "$default_branch" ] && continue
      ahead="$(git rev-list --count "$default_branch..$branch" 2>/dev/null || echo 0)"
      [ "$ahead" -gt 0 ] || continue

      # SQUASH-MERGE CHECK (scheduler#146). `ahead` alone is right only for
      # ff/no-ff integration. A squash merge puts a NEW commit on
      # $default_branch whose diff equals the branch's cumulative diff but
      # does not contain the branch's own commits as ancestors -- so `ahead`
      # never returns to 0 for a branch that already landed, and this loop
      # re-merged the same already-shipped content every cycle and CRITICALed
      # on the inevitable non-fast-forward push, forever (realisateur,
      # observed 2026-08-12, four dispatches straight on one branch).
      #
      # Detect it with patch-id, not a forge API call: this sweep must keep
      # working with no network and no `gh` auth (see the fetch-failure and
      # unresolvable-default-branch skips above, same philosophy). If the
      # branch's total diff since its merge-base has the same patch-id as
      # some commit $default_branch already carries, the content is upstream
      # even though the branch's commits are not ancestors.
      base="$(git merge-base "$default_branch" "$branch" 2>/dev/null || true)"
      already_landed=""
      if [ -n "$base" ]; then
        branch_patch_id="$(git diff "$base" "$branch" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)"
        if [ -n "$branch_patch_id" ]; then
          already_landed="$(git rev-list "$base..$default_branch" 2>/dev/null | while read -r c; do
            git show "$c" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1
          done | grep -xF "$branch_patch_id" || true)"
        fi
      fi
      if [ -n "$already_landed" ]; then
        echo "[$label] autonomy sweep: $branch already landed on $default_branch (squash, patch-id match) -- skipping, not re-merging"
        continue
      fi

      echo "[$label] autonomy sweep: $branch is $ahead commit(s) ahead of $default_branch"

      gate="ungated"
      if [ -n "$test_cmd" ]; then
        if git checkout --quiet "$branch" && eval "$test_cmd"; then
          gate="tests-passed"
          git checkout --quiet "$default_branch"
        else
          echo "[$label] autonomy sweep: $branch FAILED test gate ($test_cmd) -- leaving for manual review"
          git checkout --quiet "$default_branch" 2>/dev/null
          continue
        fi
      fi

      git fetch origin --quiet
      git merge --ff-only --quiet "origin/$default_branch" 2>/dev/null || true

      if git merge --no-ff --no-edit -m "Merge branch '$branch' [autonomy-tier:high, gate:$gate]" "$branch" --quiet; then
        merge_sha="$(git rev-parse HEAD)"
        pushed=0
        for attempt in 1 2; do
          if git push origin "$default_branch" --quiet; then
            pushed=1
            break
          fi
          echo "[$label] autonomy sweep: push attempt $attempt failed -- fetching + reconciling"
          git fetch origin --quiet
          git merge --no-ff --no-edit "origin/$default_branch" --quiet \
            || { echo "[$label] autonomy sweep: reconcile merge failed -- giving up, local $default_branch left ahead of origin for a human"; break; }
        done
        if [ "$pushed" = "1" ]; then
          echo "[$label] autonomy sweep: $branch MERGED and PUSHED -- $merge_sha (revert with: git revert -m 1 $merge_sha)"
          # q-756f82: a bare `|| true` guards a notify-send that FAILS, not one
          # that NEVER RETURNS (dbus socket present, nobody listening -- live
          # 2026-07-28). Bounded so a decoration cannot wedge the job.
          timeout 5 notify-send "$label" "auto-merged $branch ($gate): $merge_sha -- revert with git revert -m 1 $merge_sha" 2>/dev/null || true
        else
          echo "[$label] autonomy sweep: CRITICAL merged $branch locally but could not push -- $default_branch ahead of origin, needs a human"
          timeout 5 notify-send -u critical "$label" "auto-merge of $branch could not push -- investigate" 2>/dev/null || true
        fi
      else
        echo "[$label] autonomy sweep: $branch merge conflict -- aborting, leaving for manual review"
        git merge --abort 2>/dev/null || true
        git checkout --quiet "$default_branch" 2>/dev/null
      fi
    done
  )
}
