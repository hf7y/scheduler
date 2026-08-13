#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's ceiling-cutoff resume breadcrumb --
# hf7y/scheduler#31 item 2.
#
# THE GAP: item 1 (#166) made a --max-turns cutoff distinguishable in the log
# and ledger, but changed nothing about what the NEXT dispatch sees. A run cut
# off mid-task gets its pushed commits back for free (the next run clones/
# fetches origin, which already has them) -- what it does NOT get back is
# CONTEXT: the next dispatch receives the exact same conf brief from scratch,
# with no sense that this is a continuation of a task already in progress
# rather than a fresh start. chezz's #31 case is the live example: two real
# commits landed, then the run was cut off, and the next tick had no way to
# know that "Bump pawn spawn allowance" was step one of something larger.
#
# THE FIX: write_ceiling_breadcrumb() runs at the end of a run whose
# STATUS_DETAIL names a ceiling cutoff, and records the commit range plus a
# tail of the transcript to a file in STATE_DIR (survives between runs --
# STATE_DIR is the account's own persistent state dir, not the disposable
# clone). read_ceiling_breadcrumb() runs near the top of the NEXT run,
# prepends that content to PROMPT the same way FEEDBACK_BLOCK/BLOCKERS_BLOCK
# already do, and consumes (deletes) the file so it is not replayed a third
# time.
#
# Must NOT change dispatch behaviour: still NOT-DONE, still re-dispatched,
# same as claude-failure-detail-witness.sh's item 1. This is context recovery
# only.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Sourcing the whole engine would run a real job (clone, claude, push), so
# lift just the two functions out of it -- same technique as
# claude-failure-detail-witness.sh. An extraction that stops matching is a
# FAILURE, not a pass by absence: it means the functions were renamed or
# reshaped without this witness being updated to track them.
awk '/^write_ceiling_breadcrumb\(\) \{$/,/^\}$/' "$LIB" > "$TMP/fn.sh"
awk '/^read_ceiling_breadcrumb\(\) \{$/,/^\}$/' "$LIB" >> "$TMP/fn.sh"
grep -q 'write_ceiling_breadcrumb' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract write_ceiling_breadcrumb() from $LIB"; exit 1; }
grep -q 'read_ceiling_breadcrumb' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract read_ceiling_breadcrumb() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

# A real repo, not a mock -- write_ceiling_breadcrumb runs `git log` against
# BEFORE_SHA..AFTER_SHA, and a fixture that fakes shas would not catch a
# broken range expression.
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
git -C "$REPO" commit -q --allow-empty -m "first commit"
SHA1="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" commit -q --allow-empty -m "second commit, cut off here"
SHA2="$(git -C "$REPO" rev-parse HEAD)"
cd "$REPO" || exit 1

echo "== 1. no-op when STATUS_DETAIL does not name a ceiling cutoff"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb.txt"
STATUS_DETAIL=" (auth: not logged in)"
BEFORE_SHA="$SHA1"; AFTER_SHA="$SHA2"; MAX_TURNS=40; CLAUDE_OUT="$TMP/does-not-exist"
write_ceiling_breadcrumb
[ ! -e "$CEILING_BREADCRUMB_FILE" ] \
  && ok "no breadcrumb written for a non-ceiling failure" \
  || bad "breadcrumb file exists when it should not: $(cat "$CEILING_BREADCRUMB_FILE" 2>/dev/null)"

echo "== 2. ceiling cutoff with commits made -- breadcrumb records the range"
printf 'turn 1\nturn 2\nError: Reached max turns (40)\n' > "$TMP/claude-out"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb.txt"
STATUS_DETAIL=" (ceiling: max turns reached)"
BEFORE_SHA="$SHA1"; AFTER_SHA="$SHA2"; MAX_TURNS=40; CLAUDE_OUT="$TMP/claude-out"
write_ceiling_breadcrumb
if [ -f "$CEILING_BREADCRUMB_FILE" ]; then
  BODY="$(cat "$CEILING_BREADCRUMB_FILE")"
  case "$BODY" in
    *"second commit, cut off here"*) ok "breadcrumb names the commit made this run" ;;
    *) bad "breadcrumb missing the commit log: $BODY" ;;
  esac
  case "$BODY" in
    *"Reached max turns"*) ok "breadcrumb carries the transcript tail" ;;
    *) bad "breadcrumb missing the transcript tail: $BODY" ;;
  esac
else
  bad "no breadcrumb file written for a ceiling cutoff"
fi

echo "== 3. ceiling cutoff with no commits made -- says so, does not fabricate a range"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb-nocommit.txt"
STATUS_DETAIL=" (ceiling: max turns reached)"
BEFORE_SHA="$SHA2"; AFTER_SHA="$SHA2"; MAX_TURNS=40; CLAUDE_OUT="$TMP/claude-out"
write_ceiling_breadcrumb
BODY="$(cat "$CEILING_BREADCRUMB_FILE" 2>/dev/null)"
case "$BODY" in
  *"No commits made"*) ok "no-commits case says so explicitly" ;;
  *) bad "no-commits case did not say so: $BODY" ;;
esac

echo "== 4. next run, no breadcrumb present -- PROMPT untouched"
CEILING_BREADCRUMB_FILE="$TMP/does-not-exist-breadcrumb.txt"
PROMPT="original prompt text"
read_ceiling_breadcrumb
[ "$PROMPT" = "original prompt text" ] \
  && ok "PROMPT unchanged when there is nothing to resume" \
  || bad "PROMPT was rewritten with no breadcrumb file: $PROMPT"

echo "== 5. next run, breadcrumb present -- prepended to PROMPT and consumed"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb.txt"
printf 'Cut off mid-task.\nCommits made this run (%s..%s):\nsecond commit, cut off here\n' "${SHA1:0:12}" "${SHA2:0:12}" > "$CEILING_BREADCRUMB_FILE"
PROMPT="the conf's own brief"
read_ceiling_breadcrumb
case "$PROMPT" in
  *"second commit, cut off here"*"the conf's own brief") ok "breadcrumb prepended ahead of the conf's own brief" ;;
  *) bad "breadcrumb not prepended correctly: $PROMPT" ;;
esac
[ ! -e "$CEILING_BREADCRUMB_FILE" ] \
  && ok "breadcrumb file consumed (deleted) after being read" \
  || bad "breadcrumb file still exists after being read -- would replay forever"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
