#!/usr/bin/env bash
# blockers-append.sh -- the one safe way for an agent to machine-append a
# line to BLOCKERS.md (this repo's cross-project, human-owned action file).
#
# Exists because the append side of BLOCKERS.md has never had a shared
# implementation: every project's own nightly job hand-rolls its own
# insertion logic. ec89b84 (chezz, 2026-07-25) is the live exhibit of what
# that costs -- it anchored on the first line containing "## " and landed
# its new section INSIDE the header paragraph's own sentence (which names
# the "## Recently resolved" heading in prose), truncating the header and
# leaving a duplicate, fake "## Recently resolved" heading 372 lines ahead
# of the real one. blockers-freshness-check.sh had the identical bug on the
# reading side (fixed 2026-07-27, see its own comments) -- this is the
# writer-side twin, using the exact same anchor rules so the two scripts
# cannot disagree about where a section starts or ends.
#
# Anchoring rules (must match blockers-freshness-check.sh):
#   - A heading match requires a WHOLE LINE reading exactly "## <name>"
#     (trailing whitespace ignored), never a substring/prefix match.
#   - Matching is skipped inside fenced code blocks (``` or ~~~).
#
# Usage:
#   blockers-append.sh <PROJECT_KEY> <text...>
#   printf '%s\n' "$text" | blockers-append.sh <PROJECT_KEY> -
#
# Behavior:
#   - If a "## <PROJECT_KEY>" section already exists (in the active part of
#     the file, i.e. before "## Recently resolved"), the new line is
#     inserted as a new top-level bullet at the END of that section (just
#     before the next "## " heading or the stop heading, whichever comes
#     first).
#   - If no such section exists, a brand-new "## <PROJECT_KEY>" section is
#     created immediately before "## Recently resolved" (or at end of file
#     if that heading is absent).
#   - Refuses (exit 1, file untouched) if BLOCKERS.md fails the same
#     zero-sections parse-failure check blockers-freshness-check.sh uses --
#     an agent must never append into a file it cannot safely parse.
set -uo pipefail

SCHED_ROOT="${SCHED_ROOT:-/home/zach/Documents/Project Archive/scheduler}"
BLOCKERS_FILE="$SCHED_ROOT/BLOCKERS.md"

usage() {
  echo "usage: blockers-append.sh <PROJECT_KEY> <text...>" >&2
  echo "       printf '%s\\n' \"\$text\" | blockers-append.sh <PROJECT_KEY> -" >&2
}

project="${1:-}"
shift || true

if [ -z "$project" ]; then
  usage
  exit 2
fi
if ! printf '%s' "$project" | grep -qE '^[A-Za-z0-9_-]+$'; then
  echo "blockers-append.sh: PROJECT_KEY must match [A-Za-z0-9_-]+, got: $project" >&2
  exit 2
fi

if [ "$#" -eq 1 ] && [ "$1" = "-" ]; then
  text="$(cat)"
else
  text="$*"
fi

if [ -z "$text" ]; then
  usage
  exit 2
fi

[ -f "$BLOCKERS_FILE" ] || { echo "blockers-append.sh: FATAL: $BLOCKERS_FILE not found" >&2; exit 2; }

# Same parse-failure guard as blockers-freshness-check.sh: a file this size
# with zero "## <name>" headings in its active section is corrupt, not
# empty. An agent must not append into a file it cannot safely parse.
active_text="$(awk '
  BEGIN{stop=0; fence=0}
  /^[[:space:]]*(```|~~~)/{fence=!fence; if(!stop) print; next}
  !fence && /^##[[:space:]]+[Rr]ecently[[:space:]]+[Rr]esolved[[:space:]]*$/{stop=1}
  stop{next}
  {print}
' "$BLOCKERS_FILE")"

existing_projects="$(printf '%s\n' "$active_text" | awk '
  BEGIN{fence=0}
  /^[[:space:]]*(```|~~~)/{fence=!fence; next}
  !fence && /^##[[:space:]]+[A-Za-z0-9_-]+[[:space:]]*$/{
    sub(/^##[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print
  }
' | sort -u)"

file_bytes="$(wc -c <"$BLOCKERS_FILE")"
if [ -z "$existing_projects" ] && [ "$file_bytes" -gt 500 ]; then
  echo "blockers-append.sh: FATAL: no '## <project>' headings found in the" >&2
  echo "  active section of $BLOCKERS_FILE ($file_bytes bytes) -- this looks" >&2
  echo "  like a PARSE FAILURE (duplicate/misplaced stop heading, or damage" >&2
  echo "  from a previous bad append), not an empty file. Refusing to" >&2
  echo "  append. Inspect BLOCKERS.md by hand first." >&2
  exit 1
fi

has_section=0
printf '%s\n' "$existing_projects" | grep -qxF "$project" && has_section=1

# Build the bullet exactly as given, indented as a top-level "- " item.
bullet="$(printf '%s\n' "$text" | awk 'NR==1{print "- " $0; next}{print}')"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [ "$has_section" -eq 1 ]; then
  awk -v h="## $project" -v bullet="$bullet" '
    BEGIN{fence=0; in_sec=0; inserted=0}
    function flush_insert() {
      if (in_sec && !inserted) { print bullet; print ""; inserted=1 }
    }
    /^[[:space:]]*(```|~~~)/{
      fence=!fence; print; next
    }
    !fence {
      trimmed=$0; sub(/[[:space:]]+$/, "", trimmed)
      if (in_sec && trimmed ~ /^##[[:space:]]/) { flush_insert(); in_sec=0 }
      if (trimmed == h) { in_sec=1 }
    }
    { print }
    END{ flush_insert() }
  ' "$BLOCKERS_FILE" > "$tmp"
else
  awk -v h="## $project" -v bullet="$bullet" '
    BEGIN{fence=0; done=0}
    /^[[:space:]]*(```|~~~)/{fence=!fence; print; next}
    !fence {
      trimmed=$0; sub(/[[:space:]]+$/, "", trimmed)
      if (!done && trimmed ~ /^##[[:space:]]+[Rr]ecently[[:space:]]+[Rr]esolved[[:space:]]*$/) {
        print h; print ""; print bullet; print ""; done=1
      }
    }
    { print }
    END{
      if (!done) { print ""; print h; print ""; print bullet }
    }
  ' "$BLOCKERS_FILE" > "$tmp"
fi

mv "$tmp" "$BLOCKERS_FILE"
trap - EXIT
echo "blockers-append.sh: appended to '## $project' section in $BLOCKERS_FILE"
