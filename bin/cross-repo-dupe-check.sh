#!/usr/bin/env bash
# cross-repo-dupe-check.sh -- before writing into a repo you do not watch,
# ask whether the work already exists there (#606: a run burned 28 minutes
# duplicating hf7y/scheduler#599, which had merged 11 minutes earlier).
set -uo pipefail

CLI_NAME="cross-repo-dupe-check.sh"
GH_BIN="${CROSS_REPO_DUPE_CHECK_GH_BIN:-gh}"

usage() {
  cat <<EOF
usage: $CLI_NAME <owner/repo> <search term...>

Searches <owner/repo>'s OPEN pull requests and issues (gh's --search, terms
joined with spaces) for work that may already cover what you are about to
clone that repo and write. Prints any matches found.

exit: 0 no open PR/issue matches -- clear to proceed
      1 a match was found -- read it before cloning and writing
      2 usage error or a gh call failed -- BLIND, never silently 0
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac
REPO="$1"; shift
case "$REPO" in */*) : ;; *) echo "$CLI_NAME: repo must be owner/name, got '$REPO'" >&2; exit 2 ;; esac
[ $# -ge 1 ] || { echo "$CLI_NAME: need at least one search term" >&2; usage >&2; exit 2; }
TERM="$*"

FMT='.[] | "  #\(.number) \(.title) -- \(.url)"'

PR_ROWS="$("$GH_BIN" pr list -R "$REPO" --state open --search "$TERM" --json number,title,url -q "$FMT" 2>&1)"
[ $? -eq 0 ] || { echo "$CLI_NAME: gh pr list failed: $PR_ROWS" >&2; exit 2; }

ISSUE_ROWS="$("$GH_BIN" issue list -R "$REPO" --state open --search "$TERM" --json number,title,url -q "$FMT" 2>&1)"
[ $? -eq 0 ] || { echo "$CLI_NAME: gh issue list failed: $ISSUE_ROWS" >&2; exit 2; }

if [ -z "$PR_ROWS" ] && [ -z "$ISSUE_ROWS" ]; then
  echo "$CLI_NAME: clean -- no open PR or issue in $REPO matches '$TERM'"
  exit 0
fi

echo "$CLI_NAME: open work in $REPO already matches '$TERM':"
[ -n "$PR_ROWS" ] && { echo "pr:"; printf '%s\n' "$PR_ROWS"; }
[ -n "$ISSUE_ROWS" ] && { echo "issue:"; printf '%s\n' "$ISSUE_ROWS"; }
exit 1
