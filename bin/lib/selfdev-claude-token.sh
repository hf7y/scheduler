#!/usr/bin/env bash
# selfdev-claude-token.sh -- WHERE THE SHARED CLAUDE CODE OAUTH TOKEN LIVES.
# One answer, one host-wide location, sourced by every reader. Same shape and
# same reason as selfdev-app-key.sh; #409 is the cost, in full.
#
# Exports rather than writes: Claude Code reads CLAUDE_CODE_OAUTH_TOKEN from
# the environment, so the replacement leaves no file for a transcript to quote.

[ -n "${SELFDEV_CLAUDE_TOKEN_LIB:-}" ] && return 0
SELFDEV_CLAUDE_TOKEN_LIB=1

SELFDEV_TOKEN_DIR="${SELFDEV_TOKEN_DIR:-/etc/selfdev}"
SELFDEV_TOKEN_PATH_DEFAULT="$SELFDEV_TOKEN_DIR/claude-token"
SELFDEV_TOKEN_GROUP="${SELFDEV_TOKEN_GROUP:-selfdev}"

# selfdev_token_path -- prints the path; says nothing about whether it exists.
selfdev_token_path() {
  printf '%s' "${SELFDEV_TOKEN_FILE:-$SELFDEV_TOKEN_PATH_DEFAULT}"
}

# selfdev_token_readable -- the witness is a READ, not a stat: group membership
# not yet picked up by the session stats fine and reads EACCES, which is the
# whole failure mode of a group-readable secret.
selfdev_token_readable() {
  local p="${1:-$(selfdev_token_path)}"
  head -c 1 -- "$p" >/dev/null 2>&1
}

# selfdev_token_export -- rc 0 exported, 1 no file, 2 unreadable, 3 not an
# oat01 token. Never prints the value, on any path.
selfdev_token_export() {
  local p; p="$(selfdev_token_path)"
  [ -e "$p" ] || return 1
  selfdev_token_readable "$p" || return 2
  local tok; tok="$(tr -d '\r\n' < "$p")"
  case "$tok" in sk-ant-oat*) ;; *) return 3 ;; esac
  export CLAUDE_CODE_OAUTH_TOKEN="$tok"
  return 0
}
