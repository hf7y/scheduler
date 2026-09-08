#!/usr/bin/env bash
# next-issue.sh -- suggest which open issue to pick up next, gated by
# explicit "Depends on #N" text an issue's own body already carries.
#
# ADOPTED per #150 (decided 2026-08-14, landed in #177): scheduler.conf's own
# BATCH_PROMPT calls this directly, dogfooding on the one project this account
# owns. Other confs keep their own triage prose -- their call, not a mandate.
# #150's PR body carries the fuller research.
#
# WHY THIS SHAPE AND NOT A SCORE. #150 found no reliable size signal in this
# tracker -- body length does not predict hours-to-close, and a WSJF-style
# score needs an estimable size to mean anything. It also found a PROVENANCE
# label (vim-arcade's `agent`, meant to flag "filed by an agent, not Zach")
# defined and never once applied across 73 issues, like the removed
# `in-progress` fallback before it. A field nobody maintains is not a signal;
# it is a mirror reflecting back as absence whatever nobody wrote to it.
#
# WHAT SURVIVES is what nobody maintains because it exists for another reason:
# issue AGE (a free timestamp), and the issue's own prose naming what blocks
# it, written because the filer needed to say it. So OLDEST-first as before
# #150, but skipped -- not down-ranked -- while a "Depends on #N" is open.
#
# BLIND, not silently wrong. A dependency this script cannot resolve (`gh`
# unreachable, rate-limited, the named issue deleted) is treated as OPEN and
# said on stderr per issue -- never a suggestion built on unverified state.
#
# CLAIMED ISSUES ARE SKIPPED (#663). An assignee is the only claim that
# crosses hosts -- registry-lock.sh's human-busy marker lives under $HOME, so
# a session on mandark and a runner on monkey never see each other's. It meets
# the bar above: written by the ACT of claiming, not by a triage process
# asking anyone to remember. bin/tempo.sh:213 already subtracts assigned
# issues, so only the picker still disagreed. Nothing assigns today, so until
# a claim is real this skip excludes nothing.
#
# NOT a scheduler. Prints a ranked list and exits 0. Never edits a label,
# never claims an issue, never invokes anything -- an agent may ignore the
# suggestion entirely. (Zach, 2026-08-12: sequencing stays agent judgement
# "for now". The "candidate, not the answer" hedge that stood here went stale
# when #177 adopted this into scheduler.conf's own BATCH_PROMPT.)
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

Issues with a GitHub assignee are skipped: somebody has claimed them.

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

OPEN_JSON="$("$GH_BIN" issue list --repo "$REPO" --state open --limit 200 --json number,title,createdAt,body,assignees 2>/dev/null)"
if [ -z "$OPEN_JSON" ] || ! jq -e . >/dev/null 2>&1 <<<"$OPEN_JSON"; then
  echo "BLIND: could not read $REPO's open issue queue (gh unreachable, unauthenticated, or empty output)" >&2
  exit 6
fi

# Dependency state cache: "repo#n" -> "open" | "closed" | "blind"
declare -A DEP_STATE

dep_state() {
  local repo="$1" n="$2" key="$1#$2"
  if [ -n "${DEP_STATE[$key]+x}" ]; then
    printf '%s' "${DEP_STATE[$key]}"
    return 0
  fi
  local st
  st="$("$GH_BIN" issue view "$n" --repo "$repo" --json state -q '.state' 2>/dev/null)"
  case "$st" in
    OPEN)   DEP_STATE[$key]="open" ;;
    CLOSED) DEP_STATE[$key]="closed" ;;
    *)      DEP_STATE[$key]="blind" ;;  # unreadable -- fail closed, not open-by-default
  esac
  printf '%s' "${DEP_STATE[$key]}"
}

DEP_REF_RE='(depends on|blocked by)[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+'  # optional owner/repo before #N; empty slug means $REPO

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
  assignee="$(jq -r '(.assignees // []) | map(.login) | join(", ")' <<<"$row")"
  i=$((i + 1))

  if [ -n "$assignee" ]; then
    echo "SKIP  #$num  claimed by $assignee -- ${title:0:60}" >&2
    continue
  fi

  blocker=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if grep -qiE '(depends on|blocked by)' <<<"$line" && ! grep -qiE "$DEP_REF_RE" <<<"$line"; then
      blocker="unparseable dependency: ${line:0:70}"  # blind, not absent -- fail closed
      break
    fi
  done <<<"$body"

  if [ -z "$blocker" ]; then
    while IFS= read -r match; do
      [ -n "$match" ] || continue
      rest="$(sed -E 's/^(depends on|blocked by)[[:space:]]+//I' <<<"$match")"
      slug="${rest%%#*}"
      dep="${rest##*#}"
      [ -n "$slug" ] || slug="$REPO"
      [ "$slug" != "$REPO" ] || [ "$dep" != "$num" ] || continue  # an issue cannot depend on itself
      state="$(dep_state "$slug" "$dep")"
      if [ "$state" != "closed" ]; then
        if [ "$slug" = "$REPO" ]; then
          blocker="#$dep ($state)"
        else
          blocker="$slug#$dep ($state)"
        fi
        break
      fi
    done < <(grep -oiE "$DEP_REF_RE" <<<"$body")
  fi

  if [ -n "$blocker" ]; then
    echo "SKIP  #$num  waiting on $blocker -- ${title:0:60}" >&2
    continue
  fi

  echo "#$num	$created	$title"
  printed=$((printed + 1))
done

[ "$printed" -gt 0 ] || echo "(nothing eligible: every open issue is claimed or names a still-open dependency, or the queue is empty)"
exit 0
