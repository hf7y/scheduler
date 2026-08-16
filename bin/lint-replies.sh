#!/usr/bin/env bash
# lint-replies.sh <file>... [--fix] [--quiet]
#
# The safety net for hand-written `> ` replies in FOCUS.md/QUESTIONS.md/
# BLOCKERS.md. Zach asked for this directly (2026-07-28): "there should be
# a safety net that also enforces styling on my comments if I drift, or at
# least one that leaves a noisy exit when I quit vim".
#
# WHAT IT CATCHES: a reply whose continuation lines lost their `> `.
# collect-feedback.sh merges CONSECUTIVE `> ` lines into one reply and
# stops at the first line without one. So a reply written as
#
#     > yes we need to disable. this is properly delegated to senechal (a).
#       (b) also yes belt and suspenders, but notify_senechal is what's
#       really being tested here. watch that path.
#
# is collected as its first line alone -- a truncated half-sentence -- and
# the rest is left behind as orphaned prose indistinguishable from the
# question's own body. This is not hypothetical: on 2026-07-27 all 28
# replies in wtul's QUESTIONS.md were written this way and every one of
# them was collected truncated (wtul repo cbe597d restored them).
#
# WHAT IT DOES NOT TOUCH:
#   - indentation. An indented `  > ` line is left exactly as written.
#     wtul run 28 hit the opposite bug -- an entry whose OWN sub-questions
#     were written `  > ` and got eaten as if they were a reply -- and
#     "normalize indentation" would recreate it. Column-1 is the documented
#     style; enforcing it mechanically is not worth reintroducing that.
#   - `>>` blocks (already read by a run) or their continuations.
#   - anything that is not immediately below a reply line.
#
# EXIT: 0 clean. 1 drift found (or, with --fix, drift found and repaired).
# 2 usage error. Callers that want a noisy human-facing warning should
# treat 1 as "say something", never as a failure worth aborting over --
# this is a net under a human, not a gate in front of one.

set -uo pipefail

FIX=0
QUIET=0
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --fix)   FIX=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help)
      sed -n '/^# lint-replies.sh/,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'
      exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

[ "${#FILES[@]}" -gt 0 ] || {
  echo "usage: lint-replies.sh <file>... [--fix] [--quiet]" >&2; exit 2; }

TOTAL_DRIFT=0

for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || continue

  TMP="$(mktemp)" || exit 2
  REPORT="$(mktemp)" || exit 2

  awk -v fix="$FIX" -v out="$TMP" -v report="$REPORT" -v fname="$FILE" '
    function is_reply(l)      { return l ~ /^[ \t]*>[ \t]/ && l !~ /^[ \t]*>>/ }
    function is_consumed(l)   { return l ~ /^[ \t]*>>/ }
    function is_blank(l)      { return l ~ /^[ \t]*$/ }
    function is_new_entry(l)  { return l ~ /^[ \t]*-[ \t]+\*\*/ }
    function is_heading(l)    { return l ~ /^#+[ \t]/ }
    function is_fence(l)      { return l ~ /^[ \t]*```/ }

    BEGIN { in_reply = 0; drift = 0; in_fence = 0 }

    {
      line = $0

      if (is_fence(line)) { in_fence = !in_fence; in_reply = 0; print line > out; next }
      if (in_fence)       { print line > out; next }

      if (is_consumed(line)) { in_reply = 0; print line > out; next }

      if (is_reply(line)) { in_reply = 1; print line > out; next }

      if (in_reply) {
        # First line after a reply block that is not blank, not a new
        # entry, not a heading -- that is a dropped "> ".
        if (is_blank(line) || is_new_entry(line) || is_heading(line)) {
          in_reply = 0
          print line > out
          next
        }
        drift++
        printf "  %s:%d: %s\n", fname, NR, substr(line, 1, 68) > report
        if (fix) {
          body = line
          sub(/^[ \t]+/, "", body)
          print "> " body > out
        } else {
          print line > out
        }
        next
      }

      print line > out
    }

    END { print drift > "/dev/stderr" }
  ' "$FILE" 2>"$TMP.count"

  DRIFT="$(tail -1 "$TMP.count" 2>/dev/null)"
  DRIFT="${DRIFT:-0}"

  if [ "$DRIFT" -gt 0 ]; then
    TOTAL_DRIFT=$((TOTAL_DRIFT + DRIFT))
    if [ "$QUIET" != "1" ]; then
      echo ""
      echo "  ============================================================"
      if [ "$FIX" = "1" ]; then
        echo "  lint-replies: FIXED $DRIFT reply line(s) missing their '> '"
      else
        echo "  lint-replies: $DRIFT reply line(s) are MISSING their '> '"
      fi
      echo "  ============================================================"
      cat "$REPORT"
      echo ""
      echo "  Why this matters: collect-feedback.sh stops a reply at the"
      echo "  first line without '> '. Unmarked continuation lines are NOT"
      echo "  collected -- the next run would read only your first line."
      if [ "$FIX" = "1" ]; then
        echo "  Repaired in place. Review with: git diff -- $FILE"
      else
        echo "  Repair with: lint-replies.sh --fix $FILE"
      fi
      echo ""
    fi
    [ "$FIX" = "1" ] && cat "$TMP" > "$FILE"
  fi

  rm -f "$TMP" "$TMP.count" "$REPORT"
done

[ "$TOTAL_DRIFT" -gt 0 ] && exit 1
exit 0
