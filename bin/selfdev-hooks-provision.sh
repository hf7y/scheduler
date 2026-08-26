#!/usr/bin/env bash
# selfdev-hooks-provision.sh -- every self-dev account runs THE-FLOOR gate
# 3.2's closeout hook: wired in settings.json, and the CURRENT file.
#
# RUNNER: bin/tests/selfdev-hooks-provision.test.sh -- and an operator, on the host
# GUARD-TEST: bin/tests/selfdev-hooks-provision.test.sh
# GATE: strict
#
# THE SPLIT (#272): something else installs the hook FILE; this wires
# settings.json ("Zach's file"), which #282 crossed that boundary for with
# `permissions`. The file half is the verb build -- carried in
# bin/lib/carries.tsv, installed on the release tick -- since #264 got off
# shims. A sibling of selfdev-permissions-provision.sh, not a merge (#294).
#
# Env overrides (test suite only): HOME_ROOT, ACCOUNTS, SUDO, SELFDEV_HOOK_SRC.

set -uo pipefail

CLI_NAME='selfdev-hooks-provision.sh'
CLI_SUMMARY='wire the SubagentStop closeout hook every self-dev account already has installed'
CLI_USAGE='  selfdev-hooks-provision.sh            report drift, change nothing
  selfdev-hooks-provision.sh --apply    write the block
  selfdev-hooks-provision.sh --strict   exit 1 if any account drifts
  selfdev-hooks-provision.sh --print    print the block and exit'
CLI_FLAGS='--apply --strict --print'
CLI_EXITS='  0  visited every account; no --strict, or --strict and none drifted
  1  --strict was given and at least one account lacks the block (checked
     after --apply, so --apply --strict verifies its own work)
  6  BLIND -- an account home exists but its settings could not be read or
     parsed, or the roster matched no account at all. NEVER 0.'
CLI_POSITIONAL=any
. "$(dirname "${BASH_SOURCE[0]}")/../lib/cli-guard.sh"
cli_guard "$@"

HOME_ROOT="${HOME_ROOT:-/home}"
SUDO="${SUDO-sudo}"

# DERIVED, not typed -- a typed list is what produced the 2026-07-27 shim gap.
DEFAULT_ACCOUNTS=''
if [ -z "${ACCOUNTS:-}" ]; then
  for d in "$HOME_ROOT"/*/; do
    u="$(basename "$d")"
    [ "$u" = "zach" ] && continue          # the human's own account is not a self-dev account
    $SUDO test -d "$d/.claude" 2>/dev/null || continue
    DEFAULT_ACCOUNTS="$DEFAULT_ACCOUNTS $u"
  done
  ACCOUNTS="$DEFAULT_ACCOUNTS"
fi

APPLY=0; STRICT=0; PRINT=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --strict) STRICT=1 ;;
    --print) PRINT=1 ;;
  esac
done

# One jq literal: the drift check and the write read the SAME value.
read -r -d '' HOOKS <<'JSON'
{
  "SubagentStop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/hooks/subagent-closeout.sh"
        }
      ]
    }
  ]
}
JSON

if [ "$PRINT" = 1 ]; then printf '%s\n' "$HOOKS"; exit 0; fi

set -- $ACCOUNTS
[ "$#" -gt 0 ] || {
  echo "BLIND: no self-dev account found under $HOME_ROOT -- nothing was checked." >&2
  echo "$CLI_NAME: nothing was measured. This is NOT a clean result." >&2
  exit 6
}

echo "selfdev-hooks-provision -- $(date '+%Y-%m-%d %H:%M')"
if [ "$APPLY" = 1 ]; then
  echo "(--apply: writing the block; every settings.json is backed up first)"
else
  echo "(read-only: reporting drift, changing nothing -- pass --apply to fix)"
fi
echo

drift=0; blind=0; okc=0

# THE FILE, NOT ONLY THE BLOCK: the verb build refreshes it from a local
# CLONE 13 of 15 accounts lost to #385/#386. FOUR live versions, none main's.
# THE ONE CONSTANT THIS BLOCK STILL SHARES WITH realisateur, and it is named
# rather than inlined so the sharing is visible. The host pin is the verb
# build's own layout -- realisateur cuts the build and owns PROP_HOST_PIN in
# its bin/lib/propagation-set.sh. This declares the same path in
# lib/provision-set.sh, and tests/dresse.test.sh asserts the two agree, so a
# change on either side is a red suite rather than a hook that silently
# provisions from a directory nothing writes.
# shellcheck source=../lib/provision-set.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/provision-set.sh"
HOOK_SRC="${SELFDEV_HOOK_SRC:-$PROVISION_HOST_PIN/realisateur/hooks/subagent-closeout.sh}"
hook_drift=0
hook_sum() { $SUDO md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
want_sum="$(hook_sum "$HOOK_SRC")"
[ -n "$want_sum" ] || echo "  BLIND the hook file source is unreadable at $HOOK_SRC -- not checked"

for u in "$@"; do
  f="$HOME_ROOT/$u/.claude/settings.json"

  if [ -n "$want_sum" ]; then
    hf="$HOME_ROOT/$u/.claude/hooks/subagent-closeout.sh"
    got_sum="$(hook_sum "$hf")"
    if [ "$got_sum" = "$want_sum" ]; then
      :
    else
      echo "  DRIFT $u: hook FILE is ${got_sum:-absent}, build has ${want_sum}"
      hook_drift=$((hook_drift+1))
      if [ "$APPLY" = 1 ]; then
        if $SUDO install -m 755 -D "$HOOK_SRC" "$hf" 2>/dev/null; then
          $SUDO chown "$u:$u" "$hf" 2>/dev/null || true
          echo "        -> refreshed from the build"
        else
          echo "        -> FAILED to refresh the hook file"
        fi
      fi
    fi
  fi

  if ! $SUDO test -f "$f" 2>/dev/null; then
    echo "  DRIFT $u: no settings.json at all"
    drift=$((drift+1))
    [ "$APPLY" = 1 ] || continue
    cur='{}'
  else
    cur="$($SUDO cat "$f" 2>/dev/null)"
    if ! printf '%s' "$cur" | jq -e . >/dev/null 2>&1; then
      # unparseable is BLIND, never DRIFT: never overwrite state we can't read
      echo "  BLIND $u: settings.json is unreadable or not valid JSON -- NOT overwriting it"
      blind=$((blind+1))
      continue
    fi

    if printf '%s' "$cur" | jq -e --argjson want "$HOOKS" '.hooks == $want' >/dev/null 2>&1; then
      echo "  ok    $u"
      okc=$((okc+1))
      continue
    fi
    have="$(printf '%s' "$cur" | jq -c '.hooks // "absent"' 2>/dev/null)"
    echo "  DRIFT $u: hooks=$have"
    drift=$((drift+1))
    [ "$APPLY" = 1 ] || continue
  fi

  new="$(printf '%s' "$cur" | jq --argjson want "$HOOKS" '.hooks = $want' 2>/dev/null)"
  if [ -z "$new" ]; then
    echo "        -> FAILED to build the new settings; left untouched"
    continue
  fi
  # 0600 ALWAYS: `cp -p` copies the source's mode, and two live settings.json
  # were 664 -- world-readable copies of a live token (#409).
  bak="$f.bak-$(date +%Y%m%d%H%M%S)"
  if $SUDO test -f "$f"; then
    $SUDO cp -p "$f" "$bak" && $SUDO chmod 600 "$bak"
    $SUDO chmod 600 "$f"
  fi
  if printf '%s\n' "$new" | $SUDO tee "$f" >/dev/null 2>&1; then
    $SUDO chown "$u:$u" "$f" 2>/dev/null
    $SUDO chmod 0600 "$f" 2>/dev/null
    # verify by re-reading: success-that-did-not-land is the recurring failure
    if $SUDO cat "$f" 2>/dev/null | jq -e --argjson want "$HOOKS" '.hooks == $want' >/dev/null 2>&1; then
      echo "        -> written (backup: $bak)"
      drift=$((drift-1)); okc=$((okc+1))
    else
      echo "        -> WROTE but the re-read does not match -- treat as drifted"
    fi
  else
    echo "        -> FAILED to write (need sudo on this host?)"
  fi
done

echo
[ "$hook_drift" -gt 0 ] && echo "== $hook_drift account(s) ran a hook FILE that is not the build's =="
echo "== $okc with the block, $drift drifted, $blind BLIND, out of $# account(s) =="

[ "$blind" -eq 0 ] || { echo "$CLI_NAME: $blind account(s) unreadable -- counts above are NOT trustworthy."; exit 6; }
[ "$STRICT" = 1 ] && [ "$drift" -gt 0 ] && exit 1
exit 0
