#!/usr/bin/env bash
# close-audit.sh -- checks GitHub's own closingIssuesReferences on merged
# PRs against issue state, so rule 1 (CLOSE WHAT YOU RESOLVED, #522) does
# not depend on an agent's own report.
# exit: 0 clean   1 mismatch(es) found (printed)   2 usage/broken
set -uo pipefail

CLI_NAME="close-audit.sh"
GH_BIN="${CLOSE_AUDIT_GH_BIN:-gh}"
LIMIT="${CLOSE_AUDIT_LIMIT:-40}"

usage() {
  cat <<EOF
usage: $CLI_NAME [--limit N] [owner/repo]

Lists merged PRs (most recent N, default $LIMIT) in <owner/repo> (default:
this checkout's origin) whose linked issue(s) GitHub itself still shows
open.

exit: 0 clean   1 mismatch(es) found, printed   2 usage/broken
EOF
}

REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --limit) LIMIT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CLI_NAME: unknown flag $1" >&2; usage >&2; exit 2 ;;
    *) REPO="$1"; shift ;;
  esac
done

case "$LIMIT" in
  ''|*[!0-9]*) echo "$CLI_NAME: --limit needs a number, got '$LIMIT'" >&2; exit 2 ;;
esac

if [ -z "$REPO" ]; then
  REPO="$("$GH_BIN" repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
  [ -n "$REPO" ] || { echo "$CLI_NAME: no repo named and none resolvable from cwd" >&2; exit 2; }
fi

case "$REPO" in
  */*) OWNER="${REPO%%/*}"; NAME="${REPO#*/}" ;;
  *) echo "$CLI_NAME: repo must be owner/name, got '$REPO'" >&2; exit 2 ;;
esac

QUERY='
query($owner: String!, $name: String!, $n: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: MERGED, first: $n, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        url
        closingIssuesReferences(first: 10) {
          nodes { number state url }
        }
      }
    }
  }
}'

RAW="$("$GH_BIN" api graphql -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" -F n="$LIMIT" 2>&1)"
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "$CLI_NAME: BROKEN: gh api graphql failed: $RAW" >&2
  exit 2
fi

MISMATCHES="$(echo "$RAW" | jq -r '
  .data.repository.pullRequests.nodes[]
  | . as $pr
  | ($pr.closingIssuesReferences.nodes // [])[]
  | select(.state == "OPEN")
  | "\($pr.url)\t\(.url)"
')"

if [ -z "$MISMATCHES" ]; then
  echo "$CLI_NAME: clean -- no merged PR in $REPO (last $LIMIT) links an issue still open"
  exit 0
fi

echo "$CLI_NAME: merged, but the issue it names is still open:"
echo "$MISMATCHES" | while IFS=$'\t' read -r pr issue; do
  echo "  PR $pr -> $issue"
done
exit 1
