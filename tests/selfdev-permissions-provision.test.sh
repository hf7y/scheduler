#!/usr/bin/env bash
#
# selfdev-permissions-provision.test.sh -- witness for
# bin/selfdev-permissions-provision.sh.
#
# Cases:
#   A no permissions key at all        -> DRIFT, and --apply writes the block
#   B a PARTIAL permissions key        -> DRIFT, not "ok" (the shape
#     bibliothecaire actually had: {"allow":[...]} with no defaultMode and no
#     deny -- a key that exists and grants nothing, which is #294's "a guard
#     that exists and grades nothing" in config form)
#   C already correct                  -> ok, and --apply rewrites nothing
#   D unparseable settings.json        -> BLIND, never overwritten
#   E the human's own account (zach)   -> never visited
#   F --apply PRESERVES env and the other keys (the OAuth token lives in env;
#     clobbering it takes the account off the air to fix its permissions)
#   G --apply makes a backup first
#   H an empty roster                  -> BLIND (3), never a clean 0
#   I --print emits valid JSON, and the deny floor is non-empty
#   J bare invocation writes NOTHING
#
# Usage: bin/tests/selfdev-permissions-provision.test.sh  (exit 0 = all pass)
set -uo pipefail
# shellcheck source=bin/tests/lib/harness.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"
REPO_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"  # tests/ -> bin/ (was bin/tests/ in realisateur)
SCRIPT="$REPO_BIN/selfdev-permissions-provision.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# shellcheck disable=SC1007  # `SUDO= cmd` is a deliberate per-command env
# override setting SUDO to the empty string, not a mistyped assignment: it
# is what keeps every case in this file from invoking sudo.
WANT="$(SUDO= "$SCRIPT" --print)"

mkhome() { # $1 = root name, $2 = account, $3 = settings content ('' = no file)
  mkdir -p "$T/$1/$2/.claude"
  [ -n "$3" ] && printf '%s\n' "$3" > "$T/$1/$2/.claude/settings.json"
  return 0
}
# shellcheck disable=SC1007  # see the note on WANT above: empty SUDO on purpose.
run() { local r="$1"; shift; HOME_ROOT="$T/$r" SUDO= "$SCRIPT" "$@" 2>&1; }

# --- A/B/C/D/E: one tree carrying every shape -------------------------------
mkhome h1 blank    '{"env":{"CLAUDE_CODE_OAUTH_TOKEN":"secret"},"enabledPlugins":["honey"]}'
mkhome h1 partial  '{"permissions":{"allow":["WebSearch","WebFetch"]}}'
mkhome h1 correct  "$(jq -cn --argjson w "$WANT" '{permissions:$w}')"
mkhome h1 broken   'this is not json {{{'
mkhome h1 zach     '{"env":{}}'

out="$(run h1)"; run h1 >/dev/null 2>&1; got=$?
has  "A: a missing permissions key is DRIFT"  "$out" "DRIFT blank"
has  "B: a partial permissions key is DRIFT"  "$out" "DRIFT partial"
hasnt "B: and is never reported ok"           "$out" "ok    partial"
has  "C: a correct account reports ok"        "$out" "ok    correct"
has  "D: unparseable settings is BLIND"       "$out" "BLIND broken"
has  "D: and says it is NOT overwriting it"   "$out" "NOT overwriting"
hasnt "E: the human's own account is never visited" "$out" "zach"
rc   "D: BLIND exits 6 even without --strict" 6 "$got"

# --- J: bare invocation changed nothing -------------------------------------
[ "$(jq -c '.permissions // "absent"' "$T/h1/blank/.claude/settings.json")" = '"absent"' ] \
  && ok "J: bare invocation wrote nothing" || bad "J: bare invocation wrote to an account"

# --- A/F/G: --apply, on a tree with no BLIND account ------------------------
mkhome h2 blank    '{"env":{"CLAUDE_CODE_OAUTH_TOKEN":"secret"},"enabledPlugins":["honey"]}'
mkhome h2 partial  '{"permissions":{"allow":["WebSearch"]}}'
mkhome h2 nofile   ''
out="$(run h2 --apply --strict)"; run h2 --strict >/dev/null 2>&1; got=$?
has "A: --apply reports the write"      "$out" "-> written"
has "A: an account with no settings.json is DRIFT, not BLIND" "$out" "DRIFT nofile"
rc  "A: --strict is green after --apply" 0 "$got"

got_perms="$(jq -c '.permissions' "$T/h2/blank/.claude/settings.json")"
[ "$got_perms" = "$(jq -c . <<<"$WANT")" ] \
  && ok "A: the block written matches --print exactly" \
  || bad "A: written block differs from --print"

has "F: env is preserved"            "$(cat "$T/h2/blank/.claude/settings.json")" "CLAUDE_CODE_OAUTH_TOKEN"
has "F: other keys are preserved"    "$(cat "$T/h2/blank/.claude/settings.json")" "enabledPlugins"
ls "$T/h2/blank/.claude/"settings.json.bak-* >/dev/null 2>&1 \
  && ok "G: --apply backed the file up first" || bad "G: no backup was made"
ls "$T/h2/nofile/.claude/"settings.json.bak-* >/dev/null 2>&1 \
  && bad "G: backed up a file that did not exist" \
  || ok "G: no spurious backup for an account that had no settings.json"

# --- C: --apply on an already-correct account rewrites nothing --------------
mkhome h3 correct "$(jq -cn --argjson w "$WANT" '{permissions:$w}')"
before="$(ls "$T/h3/correct/.claude/")"
out="$(run h3 --apply)"
has "C: --apply leaves a correct account alone" "$out" "ok    correct"
[ "$(ls "$T/h3/correct/.claude/")" = "$before" ] \
  && ok "C: and made no backup and no write" || bad "C: rewrote a correct account"

# --- H: an empty roster is BLIND, never a clean 0 ---------------------------
mkdir -p "$T/h4"
# shellcheck disable=SC1007  # empty SUDO on purpose, as above.
HOME_ROOT="$T/h4" SUDO= "$SCRIPT" >/dev/null 2>&1
rc "H: no account found exits 6 BLIND" 6 "$?"

# --- I: the block itself ----------------------------------------------------
printf '%s' "$WANT" | jq -e . >/dev/null 2>&1 && ok "I: --print emits valid JSON" \
                                              || bad "I: --print is not valid JSON"
[ "$(printf '%s' "$WANT" | jq -r '.defaultMode')" = "auto" ] \
  && ok "I: defaultMode is auto (the mode this fleet uses)" \
  || bad "I: defaultMode is not auto"
[ "$(printf '%s' "$WANT" | jq -r '.deny|length')" -ge 5 ] \
  && ok "I: the deny floor is not empty" || bad "I: the deny floor is empty"
has "I: force-push is denied"      "$WANT" "git push --force"
has "I: pushing main is denied"    "$WANT" "git push origin main"
has "I: --admin merging is denied" "$WANT" "gh pr merge --admin"
has "I: the App key is unreadable" "$WANT" "/etc/selfdev/app.pem"

echo
summary
