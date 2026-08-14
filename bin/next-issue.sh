#!/usr/bin/env bash
# next-issue.sh -- suggest which open issue to pick up next, gated by
# explicit "Depends on #N" text an issue's own body already carries.
#
# ADOPTED, per hf7y/scheduler#150 (decided 2026-08-14, landed in #177):
# schedule/scheduler.conf's own BATCH_PROMPT (TRIAGE step) calls this script
# directly, dogfooding on the one project this account fully owns. Other
# projects' confs keep their own triage prose -- adopting the pointer there
# is each project's own call, not a mandate from #150. Read this script's
# header for the reasoning, or #150 for the fuller research.
#
# WHY THIS SHAPE AND NOT A SCORE. #150's own research (see the PR body)
# found no reliable size signal in this tracker -- issue body length does
# not correlate with hours-to-close, and a WSJF-style score needs an
# estimable size to mean anything. It also found that a PROVENANCE label
# (vim-arcade's `agent`, meant to flag "filed by an agent, not Zach") was
# defined and never once applied across 73 issues -- the same "declared as
# a guard, excludes nothing" failure the removed `in-progress` fallback
# already showed. A field nobody maintains is not a signal; it is a mirror
# that reflects whatever nobody wrote to it back as absence.
#
# WHAT SURVIVES. Two things nobody has to maintain because they already
# exist for other reasons: issue AGE (a GitHub timestamp, free) and an
# issue's own prose naming what blocks it ("Depends on #N"), written by
# whoever filed it because they needed to say it, not because a triage
# process asked them to. This script trusts neither ranking alone --
# it is OLDEST-first, exactly as before #150, but an issue is skipped
# (not merely down-ranked) while ANY "Depends on #N" issue it names is
# still open. That is restoring the removed tie-breaker, gated by a check
# that costs nothing to keep honest because the text it reads is not a
# field about triage -- it is the issue describing itself.
#
# BLIND, not silently wrong. A dependency this script cannot resolve
# (`gh` unreachable, rate-limited, or the named issue deleted) is treated
# as OPEN -- fails closed, never builds a suggestion on top of a state it
# could not verify. Said explicitly on stderr, per issue, not swallowed.
#
# NOT a scheduler. Prints a ranked list and exits 0. Never edits a label,
# never claims an issue, never invokes anything. An agent may ignore the
# suggestion entirely -- Zach, 2026-08-12: sequencing stays agent judgement
# "for now". This is a candidate for what replaces "for now", offered for
# argument, not installed as the answer.
set -uo pipefail

CLI_NAME="next-issue.sh"
GH_BIN="${NEXT_ISSUE_GH_BIN:-gh}"
LIMIT="${NEXT_ISSUE_LIMIT:-5}"

usage() {
  cat <<EOF
usage: $CLI_NAME <owner/repo> [--limit N]

Suggest open issues to pick up next: oldest first, skipping any issue that
names a still-open "Depends on #N" dependency in its own body.

  --limit N   how many suggestions to print (default 5)

exit: 0 ok (suggestions or none)  2 usage  6 blind (could not read the queue)
EOF
}

REPO="";
while [ $# -gt 0 ]; do
  case "$1" in
    --limit) shift; LIMIT="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CLI_NAME: unknown flag $1" >&2; exit 2 ;;
    *) REPO="$1" ;;
  esac
  shift
done
[ -n "$REPO" ] || { echo "$CLI_NAME: name a repo, owner/name (see --help)" >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] && [ "$LIMIT" -gt 0 ] || { echo "$CLI_NAME: --limit wants a positive integer" >&2; exit 2; }

OPEN_JSON="$("$GH_BIN" issue list --repo "$REPO" --state open --limit 200 --json number,title,createdAt,body 2>/dev/null)"
if [ -z "$OPEN_JSON" ] || ! jq -e . >/dev/null 2>&1 <<<"$OPEN_JSON"; then
  echo "BLIND: could not read $REPO's open issue queue (gh unreachable, unauthenticated, or empty output)" >&2
  exit 6
fi

# Dependency state cache: dep number -> "open" | "closed" | "blind"
declare -A DEP_STATE

dep_state() {
  local n="$1"
  if [ -n "${DEP_STATE[$n]+x}" ]; then
    printf '%s' "${DEP_STATE[$n]}"
    return 0
  fi
  local st
  st="$("$GH_BIN" issue view "$n" --repo "$REPO" --json state -q '.state' 2>/dev/null)"
  case "$st" in
    OPEN)   DEP_STATE[$n]="open" ;;
    CLOSED) DEP_STATE[$n]="closed" ;;
    *)      DEP_STATE[$n]="blind" ;;  # unreadable -- fail closed, not open-by-default
  esac
  printf '%s' "${DEP_STATE[$n]}"
}

# Oldest first, exactly the removed tie-breaker.
SORTED_JSON="$(jq -c '[ .[] ] | sort_by(.createdAt)' <<<"$OPEN_JSON")"

printed=0
count="$(jq 'length' <<<"$SORTED_JSON")"
i=0
while [ "$i" -lt "$count" ] && [ "$printed" -lt "$LIMIT" ]; do
  row="$(jq -c ".[$i]" <<<"$SORTED_JSON")"
  num="$(jq -r '.number' <<<"$row")"
  title="$(jq -r '.title' <<<"$row")"
  created="$(jq -r '.createdAt' <<<"$row")"
  body="$(jq -r '.body // ""' <<<"$row")"
  i=$((i + 1))

  blocker=""
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    [ "$dep" != "$num" ] || continue  # an issue cannot depend on itself
    state="$(dep_state "$dep")"
    if [ "$state" != "closed" ]; then
      blocker="#$dep ($state)"
      break
    fi
  done < <(grep -oiE '(depends on|blocked by) #[0-9]+' <<<"$body" | grep -oE '[0-9]+')

  if [ -n "$blocker" ]; then
    echo "SKIP  #$num  waiting on $blocker -- ${title:0:60}" >&2
    continue
  fi

  echo "#$num	$created	$title"
  printed=$((printed + 1))
done

[ "$printed" -gt 0 ] || echo "(nothing eligible: every open issue names a still-open dependency, or the queue is empty)"
exit 0
