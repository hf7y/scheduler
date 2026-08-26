#!/usr/bin/env bash
# HERMETICITY: HOME_ROOT is a throwaway tree under $T, SUDO is empty -- no
# case touches a real account. Witness for bin/selfdev-hooks-provision.sh,
# same shape as selfdev-permissions-provision.test.sh: A no hooks key ->
# DRIFT+write, B wrong event -> DRIFT not ok, C correct -> ok+no rewrite, D
# unparseable -> BLIND, E human account skipped, F --apply preserves env/
# permissions, G backs up first, H empty roster -> BLIND, I --print valid.
set -uo pipefail
REPO_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"  # tests/ -> bin/ (was bin/tests/ in realisateur)
SCRIPT="$REPO_BIN/selfdev-hooks-provision.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing: $3)" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1 (unexpected: $3)" ;; *) ok "$1" ;; esac; }
rc()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi; }

# shellcheck disable=SC1007  # `SUDO= cmd` is deliberate: keeps every case here from invoking sudo
WANT="$(SUDO= "$SCRIPT" --print)"

mkhome() { # $1 = root name, $2 = account, $3 = settings content ('' = no file)
  mkdir -p "$T/$1/$2/.claude"
  [ -n "$3" ] && printf '%s\n' "$3" > "$T/$1/$2/.claude/settings.json"
  return 0
}
# shellcheck disable=SC1007  # see WANT above: empty SUDO on purpose
run() { local r="$1"; shift; HOME_ROOT="$T/$r" SUDO= "$SCRIPT" "$@" 2>&1; }

mkhome h1 blank    '{"env":{"CLAUDE_CODE_OAUTH_TOKEN":"secret"},"permissions":{"defaultMode":"auto"}}'
mkhome h1 otherevt '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}'
mkhome h1 correct  "$(jq -cn --argjson w "$WANT" '{hooks:$w}')"
mkhome h1 broken   'this is not json {{{'
mkhome h1 zach     '{"env":{}}'

out="$(run h1)"; run h1 >/dev/null 2>&1; got=$?
has  "A: a missing hooks key is DRIFT"        "$out" "DRIFT blank"
has  "B: a hooks key without SubagentStop is DRIFT" "$out" "DRIFT otherevt"
hasnt "B: and is never reported ok"           "$out" "ok    otherevt"
has  "C: a correct account reports ok"        "$out" "ok    correct"
has  "D: unparseable settings is BLIND"       "$out" "BLIND broken"
has  "D: and says it is NOT overwriting it"   "$out" "NOT overwriting"
hasnt "E: the human's own account is never visited" "$out" "zach"
rc   "D: BLIND exits 6 even without --strict" 6 "$got"

[ "$(jq -c '.hooks // "absent"' "$T/h1/blank/.claude/settings.json")" = '"absent"' ] \
  && ok "J: bare invocation wrote nothing" || bad "J: bare invocation wrote to an account"

mkhome h2 blank    '{"env":{"CLAUDE_CODE_OAUTH_TOKEN":"secret"},"permissions":{"defaultMode":"auto","deny":["Bash(sudo:*)"]}}'
mkhome h2 otherevt '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}'
mkhome h2 nofile   ''
out="$(run h2 --apply --strict)"; run h2 --strict >/dev/null 2>&1; got=$?
has "A: --apply reports the write"      "$out" "-> written"
has "A: an account with no settings.json is DRIFT, not BLIND" "$out" "DRIFT nofile"
rc  "A: --strict is green after --apply" 0 "$got"

got_hooks="$(jq -c '.hooks' "$T/h2/blank/.claude/settings.json")"
[ "$got_hooks" = "$(jq -c . <<<"$WANT")" ] \
  && ok "A: the block written matches --print exactly" \
  || bad "A: written block differs from --print"

has "F: env is preserved"            "$(cat "$T/h2/blank/.claude/settings.json")" "CLAUDE_CODE_OAUTH_TOKEN"
has "F: permissions is preserved"    "$(cat "$T/h2/blank/.claude/settings.json")" "defaultMode"
has "F: the deny floor is preserved" "$(cat "$T/h2/blank/.claude/settings.json")" "Bash(sudo:*)"
ls "$T/h2/blank/.claude/"settings.json.bak-* >/dev/null 2>&1 \
  && ok "G: --apply backed the file up first" || bad "G: no backup was made"
ls "$T/h2/nofile/.claude/"settings.json.bak-* >/dev/null 2>&1 \
  && bad "G: backed up a file that did not exist" \
  || ok "G: no spurious backup for an account that had no settings.json"

mkhome h3 correct "$(jq -cn --argjson w "$WANT" '{hooks:$w}')"
before="$(ls "$T/h3/correct/.claude/")"
out="$(run h3 --apply)"
has "C: --apply leaves a correct account alone" "$out" "ok    correct"
[ "$(ls "$T/h3/correct/.claude/")" = "$before" ] \
  && ok "C: and made no backup and no write" || bad "C: rewrote a correct account"

mkdir -p "$T/h4"
# shellcheck disable=SC1007  # empty SUDO on purpose
HOME_ROOT="$T/h4" SUDO= "$SCRIPT" >/dev/null 2>&1
rc "H: no account found exits 6 BLIND" 6 "$?"

printf '%s' "$WANT" | jq -e . >/dev/null 2>&1 && ok "I: --print emits valid JSON" \
                                              || bad "I: --print is not valid JSON"
has "I: SubagentStop is the wired event" "$WANT" "SubagentStop"
has "I: the closeout hook is the command" "$WANT" "subagent-closeout.sh"
[ "$(printf '%s' "$WANT" | jq -r '.SubagentStop[0].hooks[0].type')" = "command" ] \
  && ok "I: the hook type is command" || bad "I: the hook type is not command"

mkdir -p "$T/hj/acctj/.claude/hooks"
printf '%s' "$WANT" | jq '{hooks:.}' > "$T/hj/acctj/.claude/settings.json"
SRC="$T/hook-src.sh"; printf '#!/usr/bin/env bash\necho current\n' > "$SRC"; chmod +x "$SRC"

printf '#!/usr/bin/env bash\necho stale\n' > "$T/hj/acctj/.claude/hooks/subagent-closeout.sh"
O="$(HOME_ROOT="$T/hj" SUDO='' SELFDEV_HOOK_SRC="$SRC" "$SCRIPT" 2>&1)"
case "$O" in *"hook FILE is"*) ok "J: a stale hook file is reported as DRIFT" ;;
  *) bad "J: stale hook file not reported: $O" ;; esac

O="$(HOME_ROOT="$T/hj" SUDO='' SELFDEV_HOOK_SRC="$SRC" "$SCRIPT" --apply 2>&1)"
if [ "$(cat "$T/hj/acctj/.claude/hooks/subagent-closeout.sh")" = "$(cat "$SRC")" ]; then
  ok "J: --apply refreshes it from the build"
else
  bad "J: --apply did not refresh the hook file"
fi

O="$(HOME_ROOT="$T/hj" SUDO='' SELFDEV_HOOK_SRC="$SRC" "$SCRIPT" 2>&1)"
case "$O" in *"hook FILE is"*) bad "J: a current hook file should not report drift: $O" ;;
  *) ok "J: a current hook file stops being a finding" ;; esac

O="$(HOME_ROOT="$T/hj" SUDO='' SELFDEV_HOOK_SRC="$T/no-such-build" "$SCRIPT" 2>&1)"
case "$O" in *"BLIND the hook file source"*) ok "J: an unreadable build source says BLIND, not ok" ;;
  *) bad "J: unreadable source did not report BLIND: $O" ;; esac

mkdir -p "$T/hk/acctk/.claude"
printf '%s' "$WANT" | jq '{env:{CLAUDE_CODE_OAUTH_TOKEN:"sk-ant-oat01-FIXTURE"}}' > "$T/hk/acctk/.claude/settings.json"
chmod 664 "$T/hk/acctk/.claude/settings.json"
HOME_ROOT="$T/hk" SUDO='' "$SCRIPT" --apply >/dev/null 2>&1
live="$(stat -c %a "$T/hk/acctk/.claude/settings.json")"
[ "$live" = 600 ] && ok "K: a 664 settings.json is tightened to 600" \
                  || bad "K: live settings.json left at $live"
loose=0
for b in "$T/hk/acctk/.claude"/settings.json.bak-*; do
  [ -e "$b" ] || continue
  [ "$(stat -c %a "$b")" = 600 ] || loose=$((loose+1))
done
[ "$loose" -eq 0 ] && ok "K: every backup it wrote is 600, whatever the source was" \
                   || bad "K: $loose backup(s) wider than 600"

echo
echo "  passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
