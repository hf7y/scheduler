#!/usr/bin/env bash
# gh-comment.sh -- post a GitHub issue comment as this token, WITH the
# provenance stamp (lib/provenance.sh) appended.
#
# hf7y/ecosim#40 found that hf7y/scheduler had never once stamped a comment
# it posted as `hf7y`, so ecosim's blocked-sensor (lib/sensors/blocked.py)
# can't tell this project's own automation apart from a genuine reply from
# Zach in the same shared-token comment history, and reports
# BLIND_NO_STAMP_DISCIPLINE for scheduler instead of a real ratio
# (hf7y/scheduler#172). This is the one place in this repo that should be
# used for a comment posted BY THIS PROJECT'S OWN AUTOMATION -- an agent run
# closing an issue it resolved, a script narrating what it did, and so on.
#
# NOT for `scheduler questions`'s comment post (bin/scheduler, ensure_gh_
# labels callers around line 1025): that path relays a HUMAN's own typed
# answer through $EDITOR, and stamping genuinely-human content as `agent`
# would feed the same sensor a false negative in the other direction --
# it exists to tell Zach's real engagement apart from agent noise, not to
# be told Zach never personally replies.
#
# RUNNER: tests/gh-comment-witness.sh
set -uo pipefail

CLI_NAME="gh-comment.sh"
GH_BIN="${GH_COMMENT_GH_BIN:-gh}"

GHC_LIB_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/provenance.sh
. "$GHC_LIB_DIR/lib/provenance.sh"

usage() {
  cat <<EOF
usage: $CLI_NAME <issue-number> --repo <owner/repo> --job <job> (--body-file <path> | --body <text>) [--project <name>]

Posts a comment to a GitHub issue with a trailing provenance stamp
(<!-- agent: <project>/<job> <ISO8601> -->) appended, so hf7y/ecosim's
blocked-sensor can tell this project's own automation apart from a genuine
human reply under the same shared token (hf7y/scheduler#172).

  --repo OWNER/NAME   required, the issue's repo
  --job JOB           required, identifies the run or script posting (e.g.
                      "issue-triage", "scheduler-dev-cycle")
  --project NAME      default: the last path segment of --repo
  --body-file PATH    comment body; mutually exclusive with --body
  --body TEXT         comment body as a literal argument

exit: 0 posted   2 usage   5 broken (gh could not post the comment)
EOF
}

NUM="" REPO="" JOB="" PROJECT="" BODY_FILE="" BODY_TEXT="" BODY_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) shift; REPO="${1:-}" ;;
    --job) shift; JOB="${1:-}" ;;
    --project) shift; PROJECT="${1:-}" ;;
    --body-file) shift; BODY_FILE="${1:-}"; BODY_SET=$((BODY_SET + 1)) ;;
    --body) shift; BODY_TEXT="${1:-}"; BODY_SET=$((BODY_SET + 1)) ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CLI_NAME: unknown flag $1" >&2; exit 2 ;;
    *) NUM="$1" ;;
  esac
  shift
done

[ -n "$NUM" ] || { echo "$CLI_NAME: name an issue number (see --help)" >&2; exit 2; }
[[ "$NUM" =~ ^[0-9]+$ ]] || { echo "$CLI_NAME: issue number must be numeric, got '$NUM'" >&2; exit 2; }
[ -n "$REPO" ] || { echo "$CLI_NAME: --repo is required (see --help)" >&2; exit 2; }
[ -n "$JOB" ] || { echo "$CLI_NAME: --job is required (see --help)" >&2; exit 2; }
[ "$BODY_SET" -eq 1 ] || { echo "$CLI_NAME: exactly one of --body-file / --body is required" >&2; exit 2; }
[ -n "$PROJECT" ] || PROJECT="${REPO##*/}"

if [ -n "$BODY_FILE" ]; then
  [ -f "$BODY_FILE" ] || { echo "$CLI_NAME: --body-file $BODY_FILE does not exist" >&2; exit 2; }
  BODY_TEXT="$(cat "$BODY_FILE")"
fi

STAMPED="$(provenance_stamp_body "$BODY_TEXT" "$PROJECT" "$JOB")"

TMPF="$(mktemp)" || { echo "$CLI_NAME: could not create a temp file" >&2; exit 5; }
trap 'rm -f "$TMPF"' EXIT
printf '%s\n' "$STAMPED" > "$TMPF"

if ! OUT="$("$GH_BIN" issue comment "$NUM" --repo "$REPO" --body-file "$TMPF" 2>&1)"; then
  echo "$CLI_NAME: gh issue comment FAILED against $REPO#$NUM -- nothing was posted" >&2
  echo "$OUT" >&2
  exit 5
fi

echo "$OUT"
exit 0
