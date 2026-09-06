#!/usr/bin/env bash
# unlanded-work-check.sh -- checks a stale cached origin/HEAD against
# GitHub's real default branch, and flags a local branch with commits no
# PR (any state) names, for rule "LAND YOUR WORK" (#522) -- ANY state
# counts as landed since this repo squash-merges (ancestry under-reports);
# excludes salvage/* (lib/salvage.sh's crash-recovery net). Exit: see usage().
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
