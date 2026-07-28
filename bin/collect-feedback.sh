#!/usr/bin/env bash
# collect-feedback.sh <file> [--section "## Heading text"] [--consume]
#
# Scans <file> for inline %%TAG comment lines AND plain `> ` blockquote
# replies (see ../docs/feedback-tags.md for the format) and prints a
# structured summary of what it found, each anchored to the nearest
# preceding markdown heading and the nearest preceding non-blank content
# line. Exists so a human can review a report (or FOCUS.md/QUESTIONS.md/
# BLOCKERS.md) in an ordinary text editor, leave tagged comments or plain
# replies inline, and have the NEXT run pick them up automatically -- no
# separate app, no re-typing feedback into a chat box.
#
# `> ` reply support added 2026-07-20 after a real near-miss: a human
# reply written into a report's LATEST.md (using the same `> ` convention
# QUESTIONS.md's own contract documents) was invisible to this script
# before this change -- LATEST.md gets wholly overwritten each run, so
# that content was one run away from being silently lost, never having
# been read by anything. Consecutive `> ` lines are merged into ONE
# "### REPLY" block (not one per physical line) so a wrapped paragraph
# reads as a single reply. A bare `> (answer inline here)` placeholder
# (the un-answered template slot) is never treated as a reply, and
# neither is an empty `>` line that isn't continuing one (2026-07-26:
# five such bare slots under BLOCKERS.md "## realisateur" were consumed
# as five empty REPLY blocks -- the slots were silently deleted and the
# run was handed answerless feedback).
#
# Exit 0 with output on stdout if any tags were found; exit 1 with no
# output if the file has none, doesn't exist, or (with --section) has none
# under that heading -- callers should treat a non-zero exit as "nothing
# to inject," not an error worth logging.
#
#   --section TEXT   only collect tags anchored under a heading matching
#                     TEXT (case-insensitive, leading #'s/whitespace and
#                     trailing whitespace ignored -- so "## vkv-inventory"
#                     and "vkv-inventory" both match the same heading).
#                     Lets ONE shared file (e.g. a cross-project
#                     BLOCKERS.md organized with a "## <project>" heading
#                     per project) be scanned separately per project, each
#                     run only picking up its own section.
# `--consume` MARKS replies, it does not delete them (changed 2026-07-28,
# Zach-directed, after the defect below). A matched `> reply` is rewritten
# in place as `>> reply` under a dated `>> _[consumed ...]_` header. It
# stays visible, attributed, and in position; it is simply no longer
# collectable, so it can never be handed to a second run as if fresh.
# `>>` lines are skipped outright, which makes --consume idempotent.
#
# Why: --consume stripped the `> ` marker as a SIDE EFFECT of collecting,
# before the calling run had decided whether to act. wtul run 28
# (2026-07-27, wtul repo 0baabb6) consumed 28 of Zach's replies, judged
# them "mostly not actionable", and deleted ZERO entries. The answers
# survived only as unattributed prose wedged inside still-open questions:
# invisible to every future --consume (nothing left to collect) and
# indistinguishable from the question's own body text. A question had
# been answered and by every mechanical measure never had been. Several
# of those "not actionable" replies were specs -- a stream URL, three
# Apps Script URLs plus "build it", a decided either/or.
#
# The deletion of an entry is the CALLER's job and always was; this
# script's job is to report what it read. It no longer destroys evidence
# on the caller's behalf. NOTE: the %%TAG path above still deletes and
# has the identical defect -- filed in FOCUS.md, not fixed here.
#
#   --consume         after collecting, rewrite <file> removing the
#                     matched %%TAG lines (headings, blocker descriptions,
#                     and every other line are left untouched) so they
#                     aren't re-collected next time. A tag under a
#                     DIFFERENT section (when --section filters it out) is
#                     left in place either way. Use for a persistent,
#                     hand-maintained file like BLOCKERS.md; don't use on
#                     a report's LATEST.md -- that file already gets
#                     overwritten wholesale by the run that acts on it.
#
# Consumption receipt (added 2026-07-27): every --consume call that
# actually removes >=1 matched entry appends one line to
# ~/.local/share/scheduler-glance/consumed-receipts.log (override with
# SCHEDULER_RECEIPT_DIR) -- timestamp, file, section, count. This exists
# so "an entry vanished from a QUESTIONS.md/BLOCKERS.md" can later be told
# apart from "a human hand-deleted an entry nothing ever consumed" --
# before this, --consume left no trace it had run, so there was no answer
# key to check a disappearance against. Purely additive: does not change
# what gets removed or when, only records that removal happened.
#
# Deliberately generic: works on any text file, not just reports, so the
# same %%TAG convention can be reused anywhere a human wants to leave an
# inline note for the next unattended run.

set -uo pipefail

FILE=""
SECTION=""
CONSUME=0

while [ $# -gt 0 ]; do
  case "$1" in
    --section) SECTION="${2:-}"; shift 2 ;;
    --consume) CONSUME=1; shift ;;
    *) FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || { echo "usage: collect-feedback.sh <file> [--section TEXT] [--consume]" >&2; exit 2; }
[ -f "$FILE" ] || exit 1

norm() { printf '%s' "$1" | sed -E 's/^[ \t]*#+[ \t]*//; s/[ \t]+$//' | tr '[:upper:]' '[:lower:]'; }

SECTION_NORM=""
[ -n "$SECTION" ] && SECTION_NORM="$(norm "$SECTION")"

KEEP_FILE=""
if [ "$CONSUME" = "1" ]; then
  KEEP_FILE="$(mktemp)"
fi

OUT="$(awk -v section_filter="$SECTION_NORM" -v keep_file="${KEEP_FILE:-}" -v consume="$CONSUME" -v consume_date="$(date +%Y-%m-%d)" '
  function norm(s,   t) {
    t = s
    sub(/^[ \t]*#+[ \t]*/, "", t)
    gsub(/[ \t]+$/, "", t)
    return tolower(t)
  }
  function flush_reply() {
    if (in_reply) {
      if (reply_matched) {
        print "### REPLY"
        if (heading != "") print "Section: " heading
        if (reply_anchor != "") print "Re: \"" reply_anchor "\""
        print reply_text
        print ""
      }
      in_reply = 0
      reply_text = ""
    }
  }
  BEGIN { heading = ""; heading_norm = ""; anchor = ""; in_reply = 0; reply_text = "" }
  /^#+[ \t]/ {
    flush_reply()
    heading = $0
    heading_norm = norm($0)
    anchor = ""
    if (consume) print $0 > keep_file
    next
  }
  /^%%(ACTION|BLOCKER|QUESTION|NOTE|APPROVE|REJECT)([ \t]|$)/ {
    flush_reply()
    matched = (section_filter == "" || heading_norm == section_filter)
    if (matched) {
      line = $0
      sub(/^%%/, "", line)
      split(line, parts, /[ \t]+/)
      kw = parts[1]
      text = line
      sub("^" kw "[ \t]*", "", text)
      print "### " kw
      if (heading != "") print "Section: " heading
      if (anchor != "") print "Re: \"" anchor "\""
      if (text != "") print text
      print ""
      # deliberately NOT written to keep_file -- this is the removal
    } else if (consume) {
      print $0 > keep_file
    }
    next
  }
  /^[ \t]*>>/ {
    # An ALREADY-CONSUMED reply (see the marking rule below). Never
    # re-collected, never re-marked, kept verbatim. This is what makes
    # --consume idempotent.
    flush_reply()
    if (consume) print $0 > keep_file
    next
  }
  /^[ \t]*>[ \t]?/ {
    content = $0
    sub(/^[ \t]*>[ \t]?/, "", content)
    if (content == "(answer inline here)" || content ~ /^\(answer inline here\)/) {
      flush_reply()
      if (consume) print $0 > keep_file
      next
    }
    if (content ~ /^[ \t]*$/ && !in_reply) {
      # A bare ">" not continuing a reply is an un-answered slot, same as
      # the "(answer inline here)" placeholder: keep it, collect nothing.
      if (consume) print $0 > keep_file
      next
    }
    if (!in_reply) {
      in_reply = 1
      reply_anchor = anchor
      reply_text = content
      reply_matched = (section_filter == "" || heading_norm == section_filter)
      if (consume && reply_matched) {
        # Open the marked block. See the header note on why a consumed
        # reply is MARKED and not deleted.
        print ">> _[consumed " consume_date " -- read by a run; this entry is" > keep_file
        print ">> still OPEN until something deletes it]_" > keep_file
      }
    } else {
      reply_text = reply_text " " content
    }
    if (consume) {
      if (reply_matched) {
        # MARK, do not delete: demote "> foo" to ">> foo". Still visibly
        # the words of the human, in place and in order -- but no longer
        # collectable, so it cannot reach a second run as if it were new.
        # NB: no apostrophes in this awk program; it is single-quoted.
        marked = $0
        sub(/^([ \t]*)>/, "&>", marked)
        print marked > keep_file
      } else {
        print $0 > keep_file
      }
    }
    next
  }
  {
    flush_reply()
    if ($0 !~ /^[ \t]*$/) anchor = $0
    if (consume) print $0 > keep_file
  }
  END { flush_reply() }
' "$FILE")"

if [ "$CONSUME" = "1" ] && [ -n "$KEEP_FILE" ]; then
  mv "$KEEP_FILE" "$FILE"
  if [ -n "$OUT" ]; then
    RECEIPT_COUNT="$(printf '%s\n' "$OUT" | grep -c '^### ')"
    RECEIPT_DIR="${SCHEDULER_RECEIPT_DIR:-$HOME/.local/share/scheduler-glance}"
    mkdir -p "$RECEIPT_DIR" 2>/dev/null || true
    printf '%s\tfile=%s\tsection=%s\tconsumed=%s\n' \
      "$(date -Is)" "$FILE" "${SECTION:--}" "$RECEIPT_COUNT" \
      >> "$RECEIPT_DIR/consumed-receipts.log" 2>/dev/null || true
  fi
fi

if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  exit 0
fi
exit 1
