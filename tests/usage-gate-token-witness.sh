#!/usr/bin/env bash
# Witness for "where will the quota gate look for a credential?"
#
# THE BUG THIS RETIRES (2026-08-03, live, and it blocked the first dispatch on
# a new host). bin/usage-gate.sh read exactly one location:
#
#   ~/.claude/.credentials.json  ->  ['claudeAiOauth']['accessToken']
#
# which is the INTERACTIVE OAuth login -- the one that expires, and the one a
# headless host cannot perform. `monkey`, the self-dev host, authenticates
# with a long-lived token from `claude setup-token` written into
# ~/.claude/settings.json's "env" block, because that is the only shape
# `claude` reads with no session bus and nothing inherited through cron.
#
# Result: `claude -p "reply ok"` worked perfectly as the dispatching user,
# while every tick logged `HOLD (gate rc=2) verdict=ERROR reason=no_token`.
# The ecosystem's unattended-auth story and its quota gate disagreed about
# where a credential lives, and the gate was the half that decided.
#
# Asserted structurally against the source: a behavioural test would need to
# stand up a fake api.anthropic.com, and what actually regressed here is which
# FILES get consulted.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/bin/usage-gate.sh"
[ -f "$GATE" ] || { echo "not found: $GATE"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
src="$(cat "$GATE")"

echo "== the gate consults every place a token can live"
case "$src" in
  *'CLAUDE_CODE_OAUTH_TOKEN:-'*) ok "reads an exported \$CLAUDE_CODE_OAUTH_TOKEN" ;;
  *) bad "does not read \$CLAUDE_CODE_OAUTH_TOKEN -- an explicitly exported token is ignored" ;;
esac
case "$src" in
  *'settings.json'*) ok "reads ~/.claude/settings.json (the setup-token shape)" ;;
  *) bad "does not read settings.json -- an unattended host cannot pass the gate" ;;
esac
case "$src" in
  *'claudeAiOauth'*) ok "still reads .credentials.json (no regression for interactive hosts)" ;;
  *) bad "dropped .credentials.json -- mandark authenticates that way" ;;
esac

echo "== and the exported token wins, because a caller that set it meant it"
# Comments must be stripped first, and matched on CODE, not prose: the first
# version of this check found "settings.json" in the explanatory comment above
# the code and concluded the precedence was backwards. A witness that reads
# documentation instead of behaviour is worse than none.
code="$(printf '%s\n' "$src" | sed 's/[[:space:]]*#.*$//')"
env_line="$(printf '%s\n' "$code" | grep -n 'TOKEN="\${CLAUDE_CODE_OAUTH_TOKEN' | head -1 | cut -d: -f1)"
set_line="$(printf '%s\n' "$code" | grep -n 'SETTINGS="\$HOME/.claude/settings.json"' | head -1 | cut -d: -f1)"
crd_line="$(printf '%s\n' "$code" | grep -n "open('\$CREDS')" | head -1 | cut -d: -f1)"
if [ -n "$env_line" ] && [ -n "$set_line" ] && [ -n "$crd_line" ] \
   && [ "$env_line" -lt "$set_line" ] && [ "$set_line" -lt "$crd_line" ]; then
  ok "precedence is env -> settings.json -> credentials.json"
else
  bad "precedence is wrong (env=$env_line settings=$set_line creds=$crd_line)"
fi

echo "== 'found nowhere' still reports the reason callers already match on"
case "$src" in
  *'emit_error no_token'*) ok "still emits reason=no_token when every source is empty" ;;
  *) bad "no_token no longer emitted -- run.log lines and any matcher on it break" ;;
esac

echo
echo "usage-gate token witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
