#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's ceiling-cutoff resume breadcrumb --
# hf7y/scheduler#31 item 2, widened by #347 item 2 to also trigger on the
# computed WORKED-CUTOFF verdict (not just the literal ceiling string), so a
# non-ceiling cutoff that still shipped work also resumes with context on the
# next dispatch instead of starting cold. See write_ceiling_breadcrumb()'s own
# comment for the full rationale.
#
# Must NOT change dispatch behaviour: still NOT-DONE, still re-dispatched,
# same as claude-failure-detail-witness.sh's item 1. This is context recovery
# only.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

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

echo "== 1. no-op when STATUS_DETAIL does not name a ceiling cutoff and RR_VERDICT is not WORKED-CUTOFF"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb.txt"
STATUS_DETAIL=" (auth: not logged in)"
unset RR_VERDICT
BEFORE_SHA="$SHA1"; AFTER_SHA="$SHA2"; MAX_TURNS=40; CLAUDE_OUT="$TMP/does-not-exist"
write_ceiling_breadcrumb
[ ! -e "$CEILING_BREADCRUMB_FILE" ] \
  && ok "no breadcrumb written for a non-ceiling failure" \
  || bad "breadcrumb file exists when it should not: $(cat "$CEILING_BREADCRUMB_FILE" 2>/dev/null)"

echo "== 1b. no-op when RR_VERDICT is FAILED (rc!=0, nothing shipped) and no ceiling match"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb-failed.txt"
STATUS_DETAIL=""
RR_VERDICT="FAILED"
BEFORE_SHA="$SHA1"; AFTER_SHA="$SHA1"; MAX_TURNS=40; CLAUDE_OUT="$TMP/does-not-exist"
write_ceiling_breadcrumb
[ ! -e "$CEILING_BREADCRUMB_FILE" ] \
  && ok "no breadcrumb written for a plain FAILED verdict" \
  || bad "breadcrumb file exists when it should not: $(cat "$CEILING_BREADCRUMB_FILE" 2>/dev/null)"

echo "== 2. ceiling cutoff with commits made -- breadcrumb records the range"
printf 'turn 1\nturn 2\nError: Reached max turns (40)\n' > "$TMP/claude-out"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb.txt"
STATUS_DETAIL=" (ceiling: max turns reached)"
unset RR_VERDICT
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
unset RR_VERDICT
BEFORE_SHA="$SHA2"; AFTER_SHA="$SHA2"; MAX_TURNS=40; CLAUDE_OUT="$TMP/claude-out"
write_ceiling_breadcrumb
BODY="$(cat "$CEILING_BREADCRUMB_FILE" 2>/dev/null)"
case "$BODY" in
  *"No commits made"*) ok "no-commits case says so explicitly" ;;
  *) bad "no-commits case did not say so: $BODY" ;;
esac

echo "== 3b. non-ceiling failure but RR_VERDICT=WORKED-CUTOFF -- breadcrumb fires with a generic cause"
CEILING_BREADCRUMB_FILE="$TMP/breadcrumb-noncelling.txt"
printf 'turn 1\nsome unrecognized transcript error\n' > "$TMP/claude-out-other"
STATUS_DETAIL=""
RR_VERDICT="WORKED-CUTOFF"
RUN_RC=1
BEFORE_SHA="$SHA1"; AFTER_SHA="$SHA2"; MAX_TURNS=40; CLAUDE_OUT="$TMP/claude-out-other"
write_ceiling_breadcrumb
if [ -f "$CEILING_BREADCRUMB_FILE" ]; then
  BODY="$(cat "$CEILING_BREADCRUMB_FILE")"
  case "$BODY" in
    *"second commit, cut off here"*) ok "non-ceiling WORKED-CUTOFF breadcrumb names the commit made this run" ;;
    *) bad "non-ceiling WORKED-CUTOFF breadcrumb missing the commit log: $BODY" ;;
  esac
  case "$BODY" in
    *"WORKED-CUTOFF"*) ok "non-ceiling breadcrumb names the verdict that triggered it, not a fabricated ceiling claim" ;;
    *) bad "non-ceiling breadcrumb does not explain its own cause: $BODY" ;;
  esac
  case "$BODY" in
    *"--max-turns"*) bad "non-ceiling breadcrumb wrongly blames --max-turns: $BODY" ;;
    *) ok "non-ceiling breadcrumb does not misattribute the cutoff to --max-turns" ;;
  esac
else
  bad "no breadcrumb file written for a non-ceiling WORKED-CUTOFF run"
fi
unset RR_VERDICT RUN_RC

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
