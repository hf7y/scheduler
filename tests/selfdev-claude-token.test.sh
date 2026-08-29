#!/usr/bin/env bash
# selfdev-claude-token.test.sh -- offline. HERMETICITY: no network, no sudo, no
# real /home, no real /etc/selfdev. Every path is a fixture under $TMP, reached
# through the same SELFDEV_* overrides production leaves unset, so the code
# under test is the code that runs (exit 0 = all pass).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"
TOOL="$ROOT/selfdev-claude-token.sh"
PASS=0; FAIL=0
ok()  { printf '  ok    %s\n' "$*"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- no '$3' in output" ;; esac; }
rc()  { [ "$2" = "$3" ] && ok "$1 (exit $3)" || bad "$1 -- exit $3, want $2"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAKE_TOKEN='sk-ant-oat01-TESTFIXTURE-not-a-real-credential'

mkhome() {  # mkhome <acct> -- a home shaped as provision-selfdev-user.sh leaves it
  mkdir -p "$TMP/accounts/$1/.claude"
  printf '%s' "$FAKE_TOKEN" > "$TMP/accounts/$1/.claude-token"
  python3 - "$TMP/accounts/$1/.claude/settings.json" "$FAKE_TOKEN" <<'PY'
import json, sys, pathlib
pathlib.Path(sys.argv[1]).write_text(json.dumps(
    {"env": {"CLAUDE_CODE_OAUTH_TOKEN": sys.argv[2]}, "model": "opus"}, indent=2) + "\n")
PY
}
run() { SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" SELFDEV_HOME_ROOT="$TMP/accounts" \
        SELFDEV_ACCOUNTS="alpha beta" bash "$TOOL" "$@" 2>&1; }

echo "selfdev-claude-token.test.sh"

echo "== 1. THE ARGUMENT CONTRACT =========================================="
O="$(bash "$TOOL" 2>&1)"; R=$?
rc  "no argument is a usage error (2), not a default action" 2 "$R"
O="$(bash "$TOOL" --nonsense 2>&1)"; R=$?
rc  "an unknown argument is a usage error (2)" 2 "$R"
has "...and names the argument" "$O" "--nonsense"
O="$(bash "$TOOL" --help 2>&1)"; R=$?
rc  "--help exits 0" 0 "$R"
has "...and states the order that matters" "$O" "ORDER MATTERS"

echo "== 2. --check REPORTS THE GAP AND EVERY STALE COPY ==================="
mkdir -p "$TMP/etc"; mkhome alpha; mkhome beta
O="$(run --check)"; R=$?
has "an absent host-wide copy is a GAP" "$O" "has not been installed"
has "...and every per-account copy is named" "$O" "stale copy: $TMP/accounts/alpha/.claude-token"
rc  "...and a GAP alone exits 4 -- in scope, not done yet" 4 "$R"

# ABSENT is a fact; only UNREADABLE is BLIND -- conflating them reports clean
# by not looking.
O="$(SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" SELFDEV_HOME_ROOT="$TMP/accounts" \
     SELFDEV_ACCOUNTS="ghost" bash "$TOOL" --check 2>&1)"; R=$?
has "an account with no home is a fact, not a blindness" "$O" "no copy to hold"
# Match a BLIND FINDING line, not the tally line, which names BLIND always.
if printf '%s\n' "$O" | grep -q '^  BLIND'; then
  bad "an absent home was reported as a BLIND finding"
else
  ok "...and no BLIND finding is raised"
fi

echo "== 3. --purge REFUSES WITHOUT A REPLACEMENT =========================="
O="$(run --purge)"; R=$?
has "purging with no host-wide copy is refused" "$O" "refusing to purge"
has "...and says what it would cost" "$O" "produce nothing, silently"
rc  "...and that is a FINDING (1), not a no-op" 1 "$R"
[ -e "$TMP/accounts/alpha/.claude-token" ] && ok "...and it deleted nothing" \
                                       || bad "the refusal still removed a file"

echo "== 4. --purge IS DRY RUN UNTIL --apply ==============================="
printf '%s\n' "$FAKE_TOKEN" > "$TMP/etc/claude-token"
O="$(run --purge)"; R=$?
has "a dry run says so" "$O" "DRY RUN"
has "...and names each file it would shred" "$O" "would shred $TMP/accounts/alpha/.claude-token"
has "...and the settings key it would strip" "$O" "would strip CLAUDE_CODE_OAUTH_TOKEN"
[ -e "$TMP/accounts/alpha/.claude-token" ] && ok "...and changed nothing on disk" \
                                       || bad "the DRY RUN deleted a file"
grep -q CLAUDE_CODE_OAUTH_TOKEN "$TMP/accounts/beta/.claude/settings.json" \
  && ok "...and left settings.json untouched" || bad "the DRY RUN edited settings.json"

echo "== 5. --purge --apply REMOVES THE COPY, NOT THE CONFIG ==============="
O="$(run --purge --apply)"; R=$?
[ -e "$TMP/accounts/alpha/.claude-token" ] && bad ".claude-token survived --apply" \
                                       || ok ".claude-token is gone"
grep -q CLAUDE_CODE_OAUTH_TOKEN "$TMP/accounts/alpha/.claude/settings.json" \
  && bad "the token key survived --apply" || ok "the token key is out of settings.json"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('model')=='opus' else 1)" \
  "$TMP/accounts/alpha/.claude/settings.json" \
  && ok "...and every UNRELATED setting is still there (model)" \
  || bad "--apply destroyed unrelated config"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP/accounts/alpha/.claude/settings.json" \
  && ok "...and the file is still valid JSON" || bad "--apply left invalid JSON"
rc  "a completed purge exits 0" 0 "$R"

echo "== 5b. --install VALIDATES SHAPE, NOT JUST PREFIX ===================="
# The 2026-08-19 outage: a stray space passed the prefix check and reached 15
# accounts as a 401 (#409).
GOOD='sk-ant-oat01-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
printf '%s\n' "$GOOD" > "$TMP/etc/claude-token"

# The write needs root, so unprivileged it stops there -- which is the point:
# a padded value must reach that step (group pinned absent, holds on any host).
printf ' %s \n' "$GOOD" > "$TMP/etc/spaced"
O="$(SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" SELFDEV_TOKEN_GROUP="no-such-group-$$" \
     bash "$TOOL" --install "$TMP/etc/spaced" 2>&1)"
case "$O" in
  *"characters, the one it replaces is"*) bad "a stray space was read as a length mismatch -- whitespace is not being stripped" ;;
  *) ok "a value padded with spaces passes validation (all whitespace stripped, not just \\r\\n)" ;;
esac
has "...and stops only at the privileged write" "$O" "no group"

printf '%s\n' "${GOOD}EXTRA" > "$TMP/etc/wrong"
O="$(SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" bash "$TOOL" --install "$TMP/etc/wrong" 2>&1)"; R=$?
rc  "a value of the WRONG LENGTH is REFUSED (7), not a gap to fill later" 7 "$R"
has "...and says both lengths" "$O" "characters, the one it replaces is"
has "...and names what it would have cost" "$O" "carry it to every account"
[ "$(tr -d '[:space:]' < "$TMP/etc/claude-token")" = "$GOOD" ] \
  && ok "...and the good value is still in place" || bad "the refusal overwrote the token"

O="$(SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" bash "$TOOL" --install "$TMP/etc/wrong" --force-length 2>&1)"
case "$O" in
  *"characters, the one it replaces is"*) bad "--force-length did not override the length refusal" ;;
  *) ok "--force-length overrides it, for a real format change" ;;
esac

printf 'not-a-token\n' > "$TMP/etc/nope"
O="$(SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" bash "$TOOL" --install "$TMP/etc/nope" 2>&1)"; R=$?
rc  "a non-oat value is a usage error (2), before any length check" 2 "$R"

echo "== 6. --fanout DERIVES THE COPIES FROM THE ONE FILE =================="
# Rebuild homes holding the OLD value, and put a DIFFERENT value host-wide.
OLD="$FAKE_TOKEN"; NEW='sk-ant-oat01-ROTATED-fixture-value'
mkhome alpha; mkhome beta
printf '%s\n' "$NEW" > "$TMP/etc/claude-token"

O="$(run --fanout)"; R=$?
has "a dry run says so" "$O" "DRY RUN"
has "...and names the accounts it would rewrite" "$O" "would rewrite $TMP/accounts/alpha"
grep -q "$OLD" "$TMP/accounts/alpha/.claude-token" \
  && ok "...and changed nothing on disk" || bad "the DRY RUN rewrote a file"

# --fanout writes via sudo -u, unavailable here: assert the refusals only.
rm -f "$TMP/etc/claude-token"
O="$(run --fanout --apply)"; R=$?
has "fanout with no host-wide copy is refused" "$O" "run --install first"
rc  "...and that is a FINDING (1), not a silent no-op" 1 "$R"
grep -q "$OLD" "$TMP/accounts/alpha/.claude-token" \
  && ok "...and it rewrote nothing" || bad "the refusal still touched a home"
printf '%s\n' "$NEW" > "$TMP/etc/claude-token"

echo "== 7. IT NEVER PRINTS THE VALUE ======================================"
ALL="$(run --check; run --purge; run --fanout; run --fanout --apply; run --purge --apply)"
case "$ALL" in
  *"$FAKE_TOKEN"*|*"$NEW"*) bad "a token VALUE appeared in output -- this tool's output is quoted into issues" ;;
  *) ok "no mode printed either token value" ;;
esac

echo "== 8. THE RESOLVER IS ONE ANSWER ====================================="
# shellcheck source=../lib/selfdev-claude-token.sh
( . "$ROOT/lib/selfdev-claude-token.sh"
  [ "$(selfdev_token_path)" = "/etc/selfdev/claude-token" ] || exit 1 ) \
  && ok "the default path is /etc/selfdev/claude-token" || bad "default path moved"
( SELFDEV_TOKEN_FILE=/x/y; . "$ROOT/lib/selfdev-claude-token.sh"
  [ "$(selfdev_token_path)" = "/x/y" ] || exit 1 ) \
  && ok "SELFDEV_TOKEN_FILE overrides it" || bad "the override does not take"
( . "$ROOT/lib/selfdev-claude-token.sh"
  SELFDEV_TOKEN_FILE="$TMP/etc/claude-token" selfdev_token_export || exit 1
  [ "$CLAUDE_CODE_OAUTH_TOKEN" = "$NEW" ] || exit 1 ) \
  && ok "selfdev_token_export puts it in the ENVIRONMENT, leaving no file" \
  || bad "selfdev_token_export did not export the value"
printf 'not-a-token\n' > "$TMP/etc/bogus"
( . "$ROOT/lib/selfdev-claude-token.sh"
  SELFDEV_TOKEN_FILE="$TMP/etc/bogus" selfdev_token_export; [ $? -eq 3 ] ) \
  && ok "a file that is not an oat01 token is rc 3, not a silent export" \
  || bad "a malformed token was exported anyway"
( . "$ROOT/lib/selfdev-claude-token.sh"
  SELFDEV_TOKEN_FILE="$TMP/etc/absent" selfdev_token_export; [ $? -eq 1 ] ) \
  && ok "an absent file is rc 1" || bad "an absent file did not report rc 1"

echo
printf 'selfdev-claude-token.test.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
