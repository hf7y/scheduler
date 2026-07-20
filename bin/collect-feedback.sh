#!/usr/bin/env bash
# collect-feedback.sh <file> [--section "## Heading text"] [--consume]
#
# Scans <file> for inline %%TAG comment lines (see ../docs/feedback-tags.md
# for the format) and prints a structured summary of what it found, each
# anchored to the nearest preceding markdown heading and the nearest
# preceding non-blank content line. Exists so a human can review a report
# (or FOCUS.md/QUESTIONS.md/BLOCKERS.md) in an ordinary text editor, leave
# tagged comments inline, and have the NEXT run pick them up automatically
# -- no separate app, no re-typing feedback into a chat box.
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

OUT="$(awk -v section_filter="$SECTION_NORM" -v keep_file="${KEEP_FILE:-}" -v consume="$CONSUME" '
  function norm(s,   t) {
    t = s
    sub(/^[ \t]*#+[ \t]*/, "", t)
    gsub(/[ \t]+$/, "", t)
    return tolower(t)
  }
  BEGIN { heading = ""; heading_norm = ""; anchor = "" }
  /^#+[ \t]/ {
    heading = $0
    heading_norm = norm($0)
    anchor = ""
    if (consume) print $0 > keep_file
    next
  }
  /^%%(ACTION|BLOCKER|QUESTION|NOTE|APPROVE|REJECT)([ \t]|$)/ {
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
  {
    if ($0 !~ /^[ \t]*$/) anchor = $0
    if (consume) print $0 > keep_file
  }
' "$FILE")"

if [ "$CONSUME" = "1" ] && [ -n "$KEEP_FILE" ]; then
  mv "$KEEP_FILE" "$FILE"
fi

if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  exit 0
fi
exit 1
