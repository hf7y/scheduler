#!/usr/bin/env bash
# blockers-freshness-check.sh -- offline-first staleness check for BLOCKERS.md
# (this repo's cross-project, human-owned action file). Zero AI cost, same
# discipline as docs/offline-first-checks.md and realisateur's
# milestone-audit.sh/hygiene-lint.sh/ecosystem-survey.sh trio.
#
# Written 2026-07-24 after a live near-miss: the wtul Discogs/fpcalc blocker
# sat in BLOCKERS.md's active section for days after the underlying work
# (token wired, fpcalc installed) had already landed and been marked done in
# wtul's own .claude/FOCUS.md -- nobody pruned BLOCKERS.md because nothing
# was watching for either signal. This script catches the two mechanical
# halves of that gap (see BLOCKERS.md's own header: the actual RESOLVED/
# RETRACTED judgment call always stays a human/`/ideate` job, this only
# flags candidates):
#
#   1. STALE-BY-AGE: an active bullet's own newest mentioned date
#      (YYYY-MM-DD) is more than $STALE_DAYS old -- probably needs a human
#      look regardless of what else has happened.
#   2. STALE-BY-DRIFT: that project's own FOCUS.md (respecting
#      SCHEDULER_SUBDIR, same override milestone-audit.sh already honors)
#      was committed to AFTER the blocker entry's own newest date -- the
#      project's status moved on and this entry might already be resolved
#      there without ever being pruned here.
#
# Findings are SIGNALS, not verdicts -- exactly the sibling surveys'
# convention. A human (or an /ideate pass) still decides RESOLVED/RETRACTED.
set -uo pipefail

# Overridable so the parse paths can be exercised against fixture files
# offline (same scratch-SCHED_ROOT convention bin/scheduler's tests use).
SCHED_ROOT="${SCHED_ROOT:-/home/zach/Documents/Project Archive/scheduler}"

# Runtime witness -- record that this check actually RAN, so a
# built-but-unwired check fails loud in `scheduler sweep` instead of looking
# clean (lib/check-witness.sh + bin/check-witness-lint.sh, 2026-07-28). This
# check is the reason that mechanism exists: it was silently unwired for two
# days in July 2026 and nothing reported it.
# Guarded, and never fatal -- bookkeeping must not be able to break a check.
if [ -r "$SCHED_ROOT/lib/check-witness.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCHED_ROOT/lib/check-witness.sh"
  check_witness "$(basename "${BASH_SOURCE[0]}")"
fi
BLOCKERS_FILE="$SCHED_ROOT/BLOCKERS.md"
STALE_DAYS="${STALE_DAYS:-14}"

[ -f "$BLOCKERS_FILE" ] || { echo "FATAL: $BLOCKERS_FILE not found" >&2; exit 2; }

today_epoch="$(date +%s)"
today="$(date '+%Y-%m-%d')"

echo "blockers-freshness-check -- $today (STALE_DAYS=$STALE_DAYS)"
echo "(offline-first: no claude calls -- findings are SIGNALS, not verdicts.)"

# Active section only: everything before the first "## Recently resolved"
# heading (case-insensitive). Project headings are "## <key>" matching
# schedule/<key>.conf's PROJECT/PROJECT_KEY, same contract collect-feedback.sh
# --section relies on.
#
# Both the stop heading and the project headings are matched as WHOLE LINES
# and only outside fenced code blocks. Prefix matching was a real bug, not a
# nit: BLOCKERS.md's own header sentence explains where resolved entries go
# by naming the heading ("...moves it down into `## Recently resolved`"), so
# a prefix match stopped the scan inside the header and this script reported
# "0/0 active project section(s) flagged" -- a clean bill of health -- for two
# days after ec89b84 corrupted the file (2026-07-25..27). Same root cause as
# the machine-append that caused the corruption: a structural marker matched
# by a rule the file's own prose about that marker can satisfy.
active_text="$(awk '
  BEGIN{stop=0; fence=0}
  /^[[:space:]]*(```|~~~)/{fence=!fence; if(!stop) print; next}
  !fence && /^##[[:space:]]+[Rr]ecently[[:space:]]+[Rr]esolved[[:space:]]*$/{stop=1}
  stop{next}
  {print}
' "$BLOCKERS_FILE")"

projects="$(printf '%s\n' "$active_text" | awk '
  BEGIN{fence=0}
  /^[[:space:]]*(```|~~~)/{fence=!fence; next}
  !fence && /^##[[:space:]]+[A-Za-z0-9_-]+[[:space:]]*$/{
    sub(/^##[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print
  }
' | sort -u)"

# A section-scoped reader that finds ZERO sections in a non-trivial file has
# not found "nothing to report" -- it has failed to parse, and must say so
# loudly rather than printing a passing summary (realisateur BUILD-DISCIPLINE
# pattern 14's UNKNOWN rule, applied to this script's own scoping).
file_bytes="$(wc -c <"$BLOCKERS_FILE")"
if [ -z "$projects" ] && [ "$file_bytes" -gt 500 ]; then
  echo "FATAL: no '## <project>' headings found in the active section of" >&2
  echo "  $BLOCKERS_FILE ($file_bytes bytes) -- this is a PARSE FAILURE, not a" >&2
  echo "  clean result. Likely causes: a duplicate/misplaced '## Recently" >&2
  echo "  resolved' heading ahead of the real one, or the file's structure" >&2
  echo "  was damaged by an append/merge. Inspect it by hand; this check" >&2
  echo "  reports UNKNOWN and refuses to imply the blockers are fresh." >&2
  exit 3
fi

flagged=0
checked=0

for name in $projects; do
  section="$(printf '%s\n' "$active_text" | awk -v h="## $name" '
    BEGIN{fence=0}
    /^[[:space:]]*(```|~~~)/{fence=!fence; if(grab) print; next}
    !fence { trimmed=$0; sub(/[[:space:]]+$/, "", trimmed) }
    !fence && trimmed == h {grab=1; next}
    !fence && /^##[[:space:]]/{grab=0}
    grab{print}
  ')"
  [ -z "$section" ] && continue
  checked=$((checked+1))

  newest="$(printf '%s\n' "$section" | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort -u | tail -1)"
  if [ -z "$newest" ]; then
    continue
  fi

  newest_epoch="$(date -d "$newest" +%s 2>/dev/null || true)"
  if [ -z "$newest_epoch" ]; then
    continue
  fi
  age_days=$(( (today_epoch - newest_epoch) / 86400 ))

  warns=()
  if [ "$age_days" -gt "$STALE_DAYS" ]; then
    warns+=("STALE-BY-AGE: newest dated reference is $newest ($age_days days old, > ${STALE_DAYS}d)")
  fi

  conf="$SCHED_ROOT/schedule/$name.conf"
  if [ -f "$conf" ]; then
    repo="$(grep -oP '(?<=PROJECT_REPO_PATH=")[^"]*' "$conf" || true)"
    subdir="$(grep -v '^[[:space:]]*#' "$conf" | grep -m1 -oP '(?<=SCHEDULER_SUBDIR=")[^"]*' || true)"
    [ -z "$subdir" ] && subdir=".claude"
    focus="$repo/$subdir/FOCUS.md"
    if [ -n "$repo" ] && [ -f "$focus" ] && [ -d "$repo/.git" -o -d "$repo/../.git" ]; then
      focus_date="$(cd "$repo" 2>/dev/null && git log -1 --format=%ad --date=short -- "$subdir/FOCUS.md" 2>/dev/null || true)"
      if [ -n "$focus_date" ]; then
        focus_epoch="$(date -d "$focus_date" +%s 2>/dev/null || true)"
        if [ -n "$focus_epoch" ] && [ "$focus_epoch" -gt "$newest_epoch" ]; then
          warns+=("STALE-BY-DRIFT: $subdir/FOCUS.md last committed $focus_date, after this entry's newest date ($newest) -- check if already resolved there")
        fi
      fi
    fi
  fi

  if [ "${#warns[@]}" -gt 0 ]; then
    flagged=$((flagged+1))
    echo
    echo "## $name"
    for w in "${warns[@]}"; do
      echo "  - $w"
    done
  fi
done

echo
echo "== summary: $flagged/$checked active project section(s) flagged =="
[ "$flagged" -gt 0 ] && exit 1
exit 0
