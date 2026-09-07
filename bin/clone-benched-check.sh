#!/usr/bin/env bash
set -uo pipefail  # flags a clone stuck on a branch that can never fast-forward again (#653)

CLI_NAME="clone-benched-check.sh"
GH_BIN="${BENCHED_GH_BIN:-gh}"
GIT_BIN="${BENCHED_GIT_BIN:-git}"

usage() {
  cat <<EOF
usage: $CLI_NAME [repo]

Checks <repo> (default: cwd) for the state that benched wtul (#653): HEAD is
off the default branch, and its configured upstream is missing or no longer
exists on origin (its PR merged and the branch was deleted). No amount of
retrying \`git pull --ff-only\` fixes that -- only a human running
\`git checkout <default> && git pull --ff-only\` does.

exit: 0 clean   2 BENCHED, printed   3 usage/broken
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
REPO_DIR="${1:-.}"

"$GIT_BIN" -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "$CLI_NAME: BROKEN: $REPO_DIR is not a git repo" >&2; exit 3; }

REPO_SLUG="$("$GIT_BIN" -C "$REPO_DIR" remote get-url origin 2>/dev/null \
  | sed -E 's#^git@github\.com:#https://github.com/#; s#^https://github\.com/##; s#\.git$##')"
[ -n "$REPO_SLUG" ] || { echo "$CLI_NAME: BROKEN: $REPO_DIR has no origin remote to resolve" >&2; exit 3; }

DEFAULT="$("$GH_BIN" repo view "$REPO_SLUG" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"
[ -n "$DEFAULT" ] || { echo "$CLI_NAME: BROKEN: could not resolve the default branch via gh repo view" >&2; exit 3; }

CURRENT="$("$GIT_BIN" -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ "$CURRENT" = "$DEFAULT" ]; then
  echo "$CLI_NAME: clean -- $REPO_DIR is on $DEFAULT"
  exit 0
fi

REMOTE="$("$GIT_BIN" -C "$REPO_DIR" config "branch.$CURRENT.remote" 2>/dev/null)"
MERGE_REF="$("$GIT_BIN" -C "$REPO_DIR" config "branch.$CURRENT.merge" 2>/dev/null)"
FIX="git -C $REPO_DIR checkout $DEFAULT && git -C $REPO_DIR pull --ff-only"

if [ -z "$REMOTE" ] || [ -z "$MERGE_REF" ]; then
  echo "$CLI_NAME: BENCHED: $REPO_DIR is on '$CURRENT' with no upstream configured -- can never fast-forward. Fix: $FIX"
  exit 2
fi

if "$GIT_BIN" -C "$REPO_DIR" ls-remote --exit-code "$REMOTE" "$MERGE_REF" >/dev/null 2>&1; then
  echo "$CLI_NAME: clean -- $REPO_DIR is on '$CURRENT', off $DEFAULT but $MERGE_REF still exists on $REMOTE"
  exit 0
fi

echo "$CLI_NAME: BENCHED: $REPO_DIR is on '$CURRENT', whose upstream $MERGE_REF on $REMOTE no longer exists -- can never fast-forward. Fix: $FIX"
exit 2
