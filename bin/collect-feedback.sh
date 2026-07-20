#!/usr/bin/env bash
# collect-feedback.sh <file>
#
# Scans <file> for inline %%TAG comment lines (see ../docs/feedback-tags.md
# for the format) and prints a structured summary of what it found, each
# anchored to the nearest preceding markdown heading and the nearest
# preceding non-blank content line. Exists so a human can review a report
# (or FOCUS.md/QUESTIONS.md) in an ordinary text editor, leave tagged
# comments inline, and have the NEXT run pick them up automatically --
# no separate app, no re-typing feedback into a chat box.
#
# Exit 0 with output on stdout if any tags were found; exit 1 with no
# output if the file has none (or doesn't exist) -- callers should treat
# a non-zero exit as "nothing to inject," not an error worth logging.
#
# Deliberately generic: works on any text file, not just reports, so the
# same %%TAG convention can be reused on FOCUS.md/QUESTIONS.md or anywhere
# else a human wants to leave an inline note for the next unattended run.

set -uo pipefail

FILE="${1:?usage: collect-feedback.sh <file>}"
[ -f "$FILE" ] || exit 1

OUT="$(awk '
  BEGIN { heading = ""; anchor = "" }
  /^#+[ \t]/ { heading = $0; anchor = ""; next }
  /^%%(ACTION|BLOCKER|QUESTION|NOTE|APPROVE|REJECT)([ \t]|$)/ {
    line = $0
    sub(/^%%/, "", line)
    n = split(line, parts, /[ \t]+/)
    kw = parts[1]
    text = line
    sub("^" kw "[ \t]*", "", text)
    print "### " kw
    if (heading != "") print "Section: " heading
    if (anchor != "") print "Re: \"" anchor "\""
    if (text != "") print text
    print ""
    next
  }
  /^[ \t]*$/ { next }
  { anchor = $0 }
' "$FILE")"

if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  exit 0
fi
exit 1
