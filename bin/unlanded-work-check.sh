#!/usr/bin/env bash
# unlanded-work-check.sh -- did every commit here actually reach main, or is
# it sitting on a clone nobody merged?
#
# hf7y/scheduler#522, rule "LAND YOUR WORK": "checkable against the branch
# and PR state" instead of trusting a run's own report. Two live incidents
# named in that rule's own prose are exactly what this checks for:
#
#   - a stale cached origin/HEAD stranded work on two separate clones (the
#     symbolic-ref check below)
#   - five commits sat unmerged on tmux-pane-mechanic with nothing watching
#     for it (the per-branch check below)
#
# Checks, against <repo> (default: cwd):
#   1. refs/remotes/origin/HEAD, after a fetch, must point at the SAME
#      branch GitHub itself reports as the repo's default. A stale cache
#      here is the exact failure the rule names.
#   2. every local branch other than the default, and not the one checked
#      out (a worktree in progress is not yet a verdict), must either be
#      fully merged into origin/<default>, or have a PR GitHub knows about
#      -- in ANY state. Ancestry alone under-reports here: this repo squash
#      merges, so a landed branch's own commits are never an ancestor of
#      main; only the PR record proves it was seen. A CLOSED PR still
#      counts -- closing one is a human decision, not the failure this
#      checks for. A branch with no PR at all, in no state, is commits
#      nobody can see landing.
#
# EXCLUDED: `salvage/*` branches (lib/salvage.sh). Those are pushed
# deliberately as a crash-recovery net for a DIRTY WORKSPACE, not as
# reviewable work -- salvage.sh's own header says preserve where it can be
# SEEN, not preserve as a PR. Flagging every one would be noise on the
# scale of every crash on every account; a real witness caught this
# building the check against this very repo's own branch list.
#
# Read/fetch only -- never pushes, merges, or deletes a branch.
#
# exit: 0 clean   2 drift or unlanded work found (printed)   3 usage/broken
set -uo pipefail

CLI_NAME="unlanded-work-check.sh"
GH_BIN="${UNLANDED_GH_BIN:-gh}"
GIT_BIN="${UNLANDED_GIT_BIN:-git}"

usage() {
  cat <<EOF
usage: $CLI_NAME [repo]

Checks <repo> (default: cwd) for work that git/GitHub's own state shows as
not landed: a stale cached origin/HEAD, or a local branch that is neither
merged into the default branch nor named by any PR (excludes salvage/*).

exit: 0 clean   2 drift or unlanded work found, printed   3 usage/broken
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
REPO_DIR="${1:-.}"

"$GIT_BIN" -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "$CLI_NAME: BROKEN: $REPO_DIR is not a git repo" >&2; exit 3; }

"$GIT_BIN" -C "$REPO_DIR" fetch -q origin 2>/dev/null

REPO_SLUG="$("$GIT_BIN" -C "$REPO_DIR" remote get-url origin 2>/dev/null \
  | sed -E 's#^git@github\.com:#https://github.com/#; s#^https://github\.com/##; s#\.git$##')"
[ -n "$REPO_SLUG" ] || { echo "$CLI_NAME: BROKEN: $REPO_DIR has no origin remote to resolve" >&2; exit 3; }

PROBLEMS=0

CACHED_DEFAULT="$("$GIT_BIN" -C "$REPO_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
CACHED_DEFAULT="${CACHED_DEFAULT#origin/}"
REAL_DEFAULT="$("$GH_BIN" repo view "$REPO_SLUG" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"

if [ -z "$REAL_DEFAULT" ]; then
  echo "$CLI_NAME: BROKEN: could not resolve the real default branch via gh repo view" >&2
  exit 3
fi

if [ -z "$CACHED_DEFAULT" ]; then
  echo "$CLI_NAME: DRIFT: refs/remotes/origin/HEAD is unset -- run: git -C $REPO_DIR remote set-head origin -a"
  PROBLEMS=1
elif [ "$CACHED_DEFAULT" != "$REAL_DEFAULT" ]; then
  echo "$CLI_NAME: DRIFT: cached origin/HEAD says '$CACHED_DEFAULT', GitHub says '$REAL_DEFAULT' -- run: git -C $REPO_DIR remote set-head origin -a"
  PROBLEMS=1
fi

DEFAULT="${REAL_DEFAULT:-$CACHED_DEFAULT}"
CURRENT_BRANCH="$("$GIT_BIN" -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

while IFS= read -r b; do
  [ -n "$b" ] || continue
  [ "$b" = "$DEFAULT" ] && continue
  [ "$b" = "$CURRENT_BRANCH" ] && continue
  case "$b" in salvage/*) continue ;; esac
  if "$GIT_BIN" -C "$REPO_DIR" merge-base --is-ancestor "$b" "origin/$DEFAULT" 2>/dev/null; then
    continue
  fi
  pr_count="$("$GH_BIN" pr list -R "$REPO_SLUG" --head "$b" --state all --json number -q 'length' 2>/dev/null)"
  if [ -n "$pr_count" ] && [ "$pr_count" -gt 0 ] 2>/dev/null; then
    continue
  fi
  echo "$CLI_NAME: UNLANDED: branch '$b' has commits not on origin/$DEFAULT and no PR, in any state, names it"
  PROBLEMS=1
done < <("$GIT_BIN" -C "$REPO_DIR" branch --format='%(refname:short)')

if [ "$PROBLEMS" -eq 0 ]; then
  echo "$CLI_NAME: clean -- origin/HEAD matches GitHub, every local branch is merged or has a PR on record"
  exit 0
fi
exit 2
