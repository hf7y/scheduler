#!/usr/bin/env bash
# questions-lint.sh -- FLAG hand-written QUESTIONS.md entries.
#
# Built 2026-07-28 (human-directed, /ideate). RETIRES nothing mechanical
# (there was no check); it retires a PROSE CONVENTION -- the "put the
# question first, provenance to DESIGN-NOTES.md" paragraph added to
# scheduler's own .scheduler/QUESTIONS.md header on 2026-07-27. That
# paragraph is now redundant with `scheduler ask` (which generates the
# shape) plus this check (which catches anything that bypassed it), and
# should be deleted rather than left as a second, softer source of truth.
#
# Why it exists at all: the convention it replaces lasted one day. The
# failure it catches is not cosmetic -- `scheduler status` prints an
# entry's bold span, so an entry that opens with its date and buries the
# question on line 3 renders as a stub, and ten such entries render as
# ten identical stubs. That is what scheduler's own QUESTIONS.md looked
# like on 2026-07-27, with 15 entries of which 5 were already resolved.
#
# Checks, per entry (a top-level `- **` bullet outside fenced blocks):
#   1. the bold span opens and CLOSES on the entry's first line
#      -- that span is exactly what the renderer prints;
#   2. the span is not merely a date/provenance stub
#      (a span that is only a date, or that starts with a date followed
#      by a parenthesised source, is the exact anti-pattern);
#   3. a `q-xxxxxx` id is present -- what a resolve/archive step and a
#      cross-reference can name once the wording changes.
#
# Exit: 0 clean, 1 findings, 3 BLIND (could not read/parse a file at
# all). 3 is separate on purpose, per the lesson blockers-freshness-
# check.sh paid for: a check that finds zero entries because it could
# not parse the file must never be reported as "no problems found".
set -uo pipefail

SCHED_ROOT="${SCHED_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Runtime witness -- record that this check actually RAN, so a
# built-but-unwired check fails loud in `scheduler sweep` instead of looking
# clean (lib/check-witness.sh + bin/check-witness-lint.sh, 2026-07-28).
# First act, before any early exit: a check that came back BLIND still ran.
# Guarded, and never fatal -- bookkeeping must not be able to break a check.
if [ -r "$SCHED_ROOT/lib/check-witness.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCHED_ROOT/lib/check-witness.sh"
  check_witness "$(basename "${BASH_SOURCE[0]}")"
fi

findings=0
blind=0
scanned=0
entries=0

lint_file() {
  local f="$1" label="$2"
  # Callers reach here only because the farm glob MATCHED, so a path that
  # is not a readable regular file is a wiring failure, never an absence.
  # This used to be `[ -f "$f" ] || return 0` -- a silent skip, and the
  # exact fail-open this file's own header forbids (see Exit, above): a
  # registered project whose QUESTIONS.md had moved or been deleted left a
  # dangling symlink that matched the glob, was dropped without a word,
  # and was not counted in `scanned` -- so the run still printed
  # "0 finding(s)" and exited 0. The project read as CLEAN because it had
  # become unreadable. Found 2026-07-29; reproduced with a two-link farm
  # (one live, one dangling), which reported "0 finding(s) ... in 1
  # file(s)", rc=0, and never named the dead one.
  if [ ! -e "$f" ]; then
    echo "BLIND: $label -- farm entry points at nothing ($f -> $(readlink "$f" 2>/dev/null || echo '?'))"
    echo "  (a registered project whose QUESTIONS.md is unreachable is NOT a clean project)"
    blind=1
    return 0
  fi
  if [ ! -f "$f" ]; then
    echo "BLIND: $label -- not a regular file ($f)"
    blind=1
    return 0
  fi
  if [ ! -r "$f" ]; then
    echo "BLIND: $label -- exists but is not readable ($f)"
    blind=1
    return 0
  fi
  scanned=$((scanned + 1))

  local out
  out="$(awk -v label="$label" '
    function flushclaim() {
      # Unstamped state-claim rule (2026-07-28). CLAUDE.md already REQUIRED
      # "claims about system state re-probed, not quoted -- and if written
      # down, stamped `verified <date> via <command>`". That was prose, and
      # prose does not enforce: on 2026-07-27 an /ideate pass answered a
      # question asserting three ~/.local/bin scripts were COPIES, and acted
      # on it. `ls -l` showed all four had been symlinks since 07-26/27 --
      # the claim had outlived its verification by a day, and nothing said
      # so even though deploy-drift-check.sh runs in sweep and knew better.
      if (claim_open && claim_state && !claim_stamped) {
        printf "%s:%d: asserts machine state with no verification stamp -- re-probe, do not quote\n", label, claim_line
        printf "    %.90s\n", claim_span
      }
      claim_open = 0
    }
    BEGIN { infence = 0; n = 0; claim_open = 0; dead = 0; pre = 0 }
    # Pass 1 (same file, read twice): does this file have ANY `## ` section
    # heading outside a fence? Everything above the first one is HEADER
    # PROSE -- the how-to-answer contract -- not entries, and linting it as
    # entries is a false finding per bullet, per project, forever. Found
    # 2026-07-29 the moment that header grew `- **A. ...**`-shaped rule
    # bullets: 4 findings on a file with exactly one real question.
    # DELIBERATELY conditional on a heading EXISTING: a legacy hand-written
    # file with entries and no headings at all still gets linted from line
    # 1, because going quiet on precisely the hand-written files this check
    # exists to catch would be a fail-open. The residual miss is an entry
    # typed ABOVE the first heading in a file that has one; `scheduler ask`
    # cannot produce that shape (it inserts under `## Open`, or appends a
    # new `## Open` section), so the trade is 4 certain false findings
    # against one unlikely true one.
    NR == FNR {
      if ($0 ~ /^```/) { infence = !infence; next }
      if (!infence && $0 ~ /^## /) hashead = 1
      next
    }
    FNR == 1 { infence = 0; pre = hashead }
    /^```/ { infence = !infence; next }
    infence { next }
    # A `## Consumed` / `## Recently resolved` ledger is ARCHIVE. Its
    # one-line entries legitimately lead with a date, so linting them as
    # open questions produced a finding per archived line -- noise that
    # would have trained the reader to ignore this check (2026-07-28).
    /^## / {
      flushclaim()
      pre = 0
      dead = (tolower($0) ~ /consumed|resolved|archive/) ? 1 : 0
      next
    }
    pre { next }
    dead { next }
    /^- \*\*/ {
      flushclaim()
      n++
      line = $0
      if (!match(line, /^- \*\*.*\*\*/)) {
        printf "%s:%d: bold span does not close on this line -- summary views print the raw line\n", label, FNR
        printf "    %.90s\n", line
        next
      }
      span = substr(line, 5, RLENGTH - 6)
      claim_open = 1; claim_line = FNR; claim_span = span
      claim_stamped = 0; claim_state = 0
      if (span ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
        printf "%s:%d: entry leads with a date, not the question\n", label, FNR
        printf "    %.90s\n", span
        next
      }
      if (span !~ /[?]/ && length(span) < 25) {
        printf "%s:%d: bold span is too short to be a question\n", label, FNR
        printf "    %.90s\n", span
        next
      }
      if (line !~ /`q-[0-9a-f]+`/) {
        printf "%s:%d: no q-id -- nothing durable to name it by; use `scheduler ask`\n", label, FNR
        printf "    %.90s\n", span
      }
      next
    }
    claim_open && tolower($0) ~ /symlink|copies|installed|crontab|enabled=|reachable|expired|deploy key/ { claim_state = 1 }
    claim_open && tolower($0) ~ /verified [0-9]{4}-[0-9]{2}-[0-9]{2}|verified live|verified from|verified by running|verified against|re-probed/ { claim_stamped = 1 }
    END { flushclaim(); printf "__ENTRIES__%d\n", n }
  ' "$f" "$f")" || {
    echo "BLIND: $label -- awk failed to parse ($f)"
    blind=1
    return 0
  }

  local n
  n="$(printf '%s\n' "$out" | sed -n 's/^__ENTRIES__//p')"
  entries=$((entries + ${n:-0}))
  local body
  body="$(printf '%s\n' "$out" | grep -v '^__ENTRIES__' || true)"
  if [ -n "$body" ]; then
    printf '%s\n' "$body"
    findings=$((findings + $(printf '%s\n' "$body" | grep -c ':[0-9]*: ' || true)))
  fi
}

# Every registered project's own QUESTIONS.md, via the symlinks scheduler
# already maintains -- one source for the path, not a re-derived guess.
shopt -s nullglob
for link in "$SCHED_ROOT"/questions/*.md; do
  lint_file "$link" "$(basename "$link" .md)/QUESTIONS.md"
done
shopt -u nullglob

if [ "$scanned" -eq 0 ]; then
  echo "BLIND: found no QUESTIONS.md to scan under $SCHED_ROOT/questions/"
  echo "  (that is a parse/wiring failure, NOT a clean result)"
  exit 3
fi

echo "== summary: $findings finding(s) across $entries entr(ies) in $scanned file(s) =="
[ "$blind" -eq 1 ] && exit 3
[ "$findings" -gt 0 ] && exit 1
exit 0
