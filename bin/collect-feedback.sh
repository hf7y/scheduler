#!/usr/bin/env bash
# collect-feedback.sh <file> [--section "## Heading text"] [--consume]
#                     <file> --list-consumed
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
#
# ---------------------------------------------------------------------------
# WHERE THE CONSUMPTION RECORD LIVES, AND WHY IT MOVED (2026-08-11, #61/#70)
#
# --consume USED to rewrite <file> in place: `%%TAG` lines were deleted and
# a matched `> reply` was demoted to `>> reply` under a dated
# `>> _[consumed ...]_` header. That worked, and it deadlocked the fleet.
#
# The file it rewrites on a dispatcher host is the repo's own TRACKED
# BLOCKERS.md. bin/usage-paced-runner.sh gates its pull-before-dispatch on
# `git status --porcelain --untracked-files=no`. So the job dirtied the very
# file its own deploy gate refuses to pull past: the FIRST consumed tag on a
# host froze that host at whatever commit it happened to be at, permanently,
# with one `PULL skip` line in a log nobody reads as the only symptom.
# Measured cost: PR #59 fixed vim-arcade's brief and merged 2026-08-06T20:02Z.
# It never ran. Five days later that clone was still pinned behind origin/main
# for exactly this reason, and crt was wedged the same way (#61 comment,
# 2026-08-06: two of six monkey clones, and it is every account that has ever
# consumed a tag, which is every account the feedback channel reaches).
#
# The category error was putting a fact about THIS HOST'S RUN HISTORY into the
# PROJECT'S CONTENT. "A run on this machine has already been handed this
# entry" is not something the repo knows or should carry; it is per-host
# runtime state, like the rotation pointer and the verdict files. So it now
# lives beside them:
#
#   ~/.local/share/scheduler-glance/consumed-entries.tsv
#   (same dir, same SCHEDULER_RECEIPT_DIR override, as consumed-receipts.log)
#
# one tab-separated line per consumed entry:
#   <consumed-at>  <file>  <section>  <anchor>  <kind>  <text>
# and an entry whose (file, section, anchor, kind, text) is already in the
# ledger is never collected again. **<file> IS NEVER MODIFIED.** Consequences,
# all of them the point:
#   - the pull gate never sees a dirty tree caused by this script
#   - a fresh clone is never "dirty on arrival"
#   - the human's words are not merely preserved, they are not touched
#   - the %%TAG path stops DELETING (the defect this header used to note as
#     "still deletes and has the identical defect -- filed in FOCUS.md, not
#     fixed here"). Nothing is removed from anything any more.
#   - a reader with no write access to <file> can consume correctly instead of
#     re-prepending the same feedback on every run forever
#
# WHAT WAS LOST, AND WHERE IT WENT. The `>>` demotion was also a human-visible
# "a run read this" marker in the file. On a dispatcher clone that marker was
# already write-only -- nothing committed or pushed it, so it never reached
# the human who wrote the reply; it only ever fed the next run on the same
# host, which is exactly what the ledger does, and better. For the human, the
# read side is now a flag rather than a file edit:
#
#   collect-feedback.sh <file> --list-consumed
#
# MIGRATION -- existing in-repo `>>` markers (2026-08-11). Two halves:
#   1. `>>` lines are STILL skipped outright, exactly as before. A host
#      carrying an old in-file marker therefore does not re-prepend feedback
#      it already acted on. Nothing to do, nothing lost.
#   2. On a --consume pass, every legacy `>>` block that is not already in the
#      ledger is SEEDED into it, keyed identically to the `> ` reply it was
#      made from. This is what makes the live remediation of a wedged clone
#      safe: after one pass under this code, `git restore BLOCKERS.md` on
#      vim-arcade/crt discards the dirty diff WITHOUT un-consuming the entries
#      it recorded -- which, before the seeding, it would have (#75, 2026-08-11:
#      "git restore destroys a real record").
# The seeding is one-way by design. To deliberately re-ask something already
# consumed, edit the words (a changed entry is a new entry, and collects) or
# delete its line from the ledger.
#
# `--consume` MARKS replies, it does not delete them (changed 2026-07-28,
# Zach-directed, after the defect below) -- and since 2026-08-11 it marks them
# somewhere that is not the file at all. `>>` lines are skipped outright,
# which is what made --consume idempotent then and still does now, alongside
# the ledger.
#
# Why the 2026-07-28 change: --consume stripped the `> ` marker as a SIDE
# EFFECT of collecting, before the calling run had decided whether to act.
# wtul run 28 (2026-07-27, wtul repo 0baabb6) consumed 28 of Zach's replies,
# judged them "mostly not actionable", and deleted ZERO entries. The answers
# survived only as unattributed prose wedged inside still-open questions:
# invisible to every future --consume (nothing left to collect) and
# indistinguishable from the question's own body text. A question had
# been answered and by every mechanical measure never had been. Several
# of those "not actionable" replies were specs -- a stream URL, three
# Apps Script URLs plus "build it", a decided either/or.
#
# The deletion of an entry is the CALLER's job and always was; this
# script's job is to report what it read. It does not destroy evidence on
# the caller's behalf, and no longer edits the caller's file at all.
#
#   --consume         after collecting, record the matched entries in this
#                     account's consumption ledger so they are not collected
#                     again. <file> is NOT modified. An entry under a
#                     DIFFERENT section (when --section filters it out) is
#                     neither collected nor recorded. Use for a persistent,
#                     hand-maintained file like BLOCKERS.md; don't use on
#                     a report's LATEST.md -- that file already gets
#                     overwritten wholesale by the run that acts on it.
#   --list-consumed   print this account's ledger rows for <file> (the read
#                     side of the marker that used to be visible in the file
#                     itself). Exit 1 when there are none.
#
# Consumption receipt (added 2026-07-27): every --consume call that
# actually consumes >=1 matched entry appends one line to
# ~/.local/share/scheduler-glance/consumed-receipts.log (override with
# SCHEDULER_RECEIPT_DIR) -- timestamp, file, section, count. This exists
# so "an entry vanished from a QUESTIONS.md/BLOCKERS.md" can later be told
# apart from "a human hand-deleted an entry nothing ever consumed" --
# before this, --consume left no trace it had run, so there was no answer
# key to check a disappearance against. It remains the per-CALL summary;
# consumed-entries.tsv beside it is the per-ENTRY detail.
#
# Deliberately generic: works on any text file, not just reports, so the
# same %%TAG convention can be reused anywhere a human wants to leave an
# inline note for the next unattended run.

set -uo pipefail

FILE=""
SECTION=""
CONSUME=0
LIST_CONSUMED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --section) SECTION="${2:-}"; shift 2 ;;
    --consume) CONSUME=1; shift ;;
    --list-consumed) LIST_CONSUMED=1; shift ;;
    *) FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || { echo "usage: collect-feedback.sh <file> [--section TEXT] [--consume] | <file> --list-consumed" >&2; exit 2; }

# ONE definition of where this account's consumption state lives -- the
# per-call receipt log and the per-entry ledger share a directory and a single
# override, so there is no second place to retype the path.
RECEIPT_DIR="${SCHEDULER_RECEIPT_DIR:-$HOME/.local/share/scheduler-glance}"
LEDGER="$RECEIPT_DIR/consumed-entries.tsv"

# The ledger is keyed on an ABSOLUTE path: callers reach the same file by
# several spellings (lib/../BLOCKERS.md from the engine, ./BLOCKERS.md by
# hand), and an unnormalised key would record them as different entries and
# hand the same feedback over twice.
FILE_ABS="$(readlink -f "$FILE" 2>/dev/null || true)"
[ -n "$FILE_ABS" ] || FILE_ABS="$FILE"

if [ "$LIST_CONSUMED" = "1" ]; then
  [ -f "$LEDGER" ] || exit 1
  OUT="$(awk -F'\t' -v f="$FILE_ABS" '
    $2 == f { printf "%s  [%s under %s] %s\n", $1, $5, ($3 == "" ? "(no section)" : $3), $6 }
  ' "$LEDGER")"
  [ -n "$OUT" ] || exit 1
  printf '%s\n' "$OUT"
  exit 0
fi

[ -f "$FILE" ] || exit 1

norm() { printf '%s' "$1" | sed -E 's/^[ \t]*#+[ \t]*//; s/[ \t]+$//' | tr '[:upper:]' '[:lower:]'; }

SECTION_NORM=""
[ -n "$SECTION" ] && SECTION_NORM="$(norm "$SECTION")"

# Keys of entries consumed by THIS call, collected by awk and appended to the
# ledger below. Written by awk rather than parsed back out of $OUT: the printed
# block is for a human/agent to read and its shape is free to change, while the
# key must stay byte-stable or an entry silently un-consumes itself.
KEYS_FILE=""
if [ "$CONSUME" = "1" ]; then
  KEYS_FILE="$(mktemp)"
fi

OUT="$(awk -v section_filter="$SECTION_NORM" -v consume="$CONSUME" \
           -v ledger="$LEDGER" -v keys_file="${KEYS_FILE:-}" -v file_key="$FILE_ABS" '
  function norm(s,   t) {
    t = s
    sub(/^[ \t]*#+[ \t]*/, "", t)
    gsub(/[ \t]+$/, "", t)
    return tolower(t)
  }
  # The ledger key. Section AND anchor are both in it on purpose: a short
  # reply ("> yes") can legitimately appear twice under one heading, and a key
  # that could not tell those apart would silently swallow the second one.
  # Feedback lost is a worse failure than feedback offered twice, so the key
  # errs narrow -- editing the line above a consumed reply re-collects it,
  # which is visible and harmless.
  function mkkey(h, a, kind, text,   th, ta, tt) {
    th = h; ta = a; tt = text
    gsub(/\t/, " ", th); gsub(/\t/, " ", ta); gsub(/\t/, " ", tt)
    return file_key "\t" th "\t" ta "\t" kind "\t" tt
  }
  # Should this entry be collected now? Only if no run has been handed it
  # before. Marked as consumed only when --consume: a plain read must not
  # change what the next read sees.
  function claim(k) {
    if (k in seen) return 0
    if (consume) { seen[k] = 1; print k > keys_file }
    return 1
  }
  # Migration: record a legacy in-file `>>` marker in the ledger, so the
  # record survives the tracked file being restored/reverted/re-cloned.
  function seed(k) {
    if (!consume) return
    if (k in seen) return
    seen[k] = 1
    print k > keys_file
  }
  function flush_reply(   k) {
    if (in_reply) {
      if (reply_matched) {
        k = mkkey(reply_heading_norm, reply_anchor, "REPLY", reply_text)
        if (claim(k)) {
          print "### REPLY"
          if (reply_heading != "") print "Section: " reply_heading
          if (reply_anchor != "") print "Re: \"" reply_anchor "\""
          print reply_text
          print ""
        }
      }
      in_reply = 0
      reply_text = ""
    }
  }
  function flush_consumed(   k) {
    if (in_consumed) {
      if (consumed_text != "") {
        k = mkkey(consumed_heading_norm, consumed_anchor, "REPLY", consumed_text)
        seed(k)
      }
      in_consumed = 0
      consumed_text = ""
    }
  }
  BEGIN {
    heading = ""; heading_norm = ""; anchor = ""
    in_reply = 0; reply_text = ""
    in_consumed = 0; consumed_text = ""
    if (ledger != "") {
      while ((getline lline < ledger) > 0) {
        lp = index(lline, "\t")
        if (lp > 0) seen[substr(lline, lp + 1)] = 1
      }
      close(ledger)
    }
  }
  /^#+[ \t]/ {
    flush_reply(); flush_consumed()
    heading = $0
    heading_norm = norm($0)
    anchor = ""
    next
  }
  /^%%(ACTION|BLOCKER|QUESTION|NOTE|APPROVE|REJECT)([ \t]|$)/ {
    flush_reply(); flush_consumed()
    matched = (section_filter == "" || heading_norm == section_filter)
    if (matched) {
      tagline = $0
      sub(/^%%/, "", tagline)
      split(tagline, parts, /[ \t]+/)
      kw = parts[1]
      text = tagline
      sub("^" kw "[ \t]*", "", text)
      if (claim(mkkey(heading_norm, anchor, kw, text))) {
        print "### " kw
        if (heading != "") print "Section: " heading
        if (anchor != "") print "Re: \"" anchor "\""
        if (text != "") print text
        print ""
      }
    }
    next
  }
  /^[ \t]*>>/ {
    # An ALREADY-CONSUMED reply, in the pre-2026-08-11 in-file format. Never
    # re-collected, never re-marked, kept verbatim -- this is half of what
    # makes --consume idempotent. The other half is the ledger, and this block
    # feeds it: see seed() above and the MIGRATION note in the header.
    flush_reply()
    cc = $0
    sub(/^[ \t]*>>[ \t]?/, "", cc)
    if (!in_consumed) {
      in_consumed = 1
      consumed_anchor = anchor
      consumed_heading_norm = heading_norm
      consumed_text = ""
    }
    # The two header lines the old in-place marker wrote are not part of the
    # human reply and must not enter the key, or the seeded key would not
    # match the one the same reply produces when it is a plain `> ` line.
    if (cc ~ /^_\[consumed / || cc ~ /^still OPEN until something deletes it\]_$/) next
    if (consumed_text == "") consumed_text = cc; else consumed_text = consumed_text " " cc
    next
  }
  /^[ \t]*>[ \t]?/ {
    flush_consumed()
    content = $0
    sub(/^[ \t]*>[ \t]?/, "", content)
    if (content == "(answer inline here)" || content ~ /^\(answer inline here\)/) {
      flush_reply()
      next
    }
    if (content ~ /^[ \t]*$/ && !in_reply) {
      # A bare ">" not continuing a reply is an un-answered slot, same as
      # the "(answer inline here)" placeholder: keep it, collect nothing.
      next
    }
    if (!in_reply) {
      in_reply = 1
      reply_anchor = anchor
      reply_heading = heading
      reply_heading_norm = heading_norm
      reply_text = content
      reply_matched = (section_filter == "" || heading_norm == section_filter)
    } else {
      reply_text = reply_text " " content
    }
    next
  }
  {
    flush_reply(); flush_consumed()
    if ($0 !~ /^[ \t]*$/) anchor = $0
  }
  END { flush_reply(); flush_consumed() }
' "$FILE")"

if [ "$CONSUME" = "1" ] && [ -n "$KEYS_FILE" ]; then
  if [ -s "$KEYS_FILE" ]; then
    # LOUD on failure. An unrecordable consumption is not a no-op: the entry
    # will be handed to the next run as if it were fresh, which is the exact
    # re-prepend loop the ledger exists to end.
    if ! { mkdir -p "$RECEIPT_DIR" 2>/dev/null \
           && awk -v ts="$(date -Is)" '{ print ts "\t" $0 }' "$KEYS_FILE" >> "$LEDGER"; }; then
      echo "collect-feedback.sh: WARNING could not record consumption in $LEDGER -- these entries WILL be collected again next run" >&2
    fi
  fi
  rm -f "$KEYS_FILE"

  if [ -n "$OUT" ]; then
    RECEIPT_COUNT="$(printf '%s\n' "$OUT" | grep -c '^### ')"
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
