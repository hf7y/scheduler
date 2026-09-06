#!/usr/bin/env bash
# route-deliveries.sh -- tell a repo when something it was waiting on landed.
#
# THE GAP THIS FILLS (hf7y/scheduler#299). `<!-- DEFERRED -->` is enforced at
# WRITE time by gh-sign and read by NOTHING. Measured 2026-08-25: five files
# under bin/ mention the block and all five write it. So a dependency is
# declared, machine-readable, pointing the right way -- and never delivered.
# hf7y/crt#67 named hf7y/apms-2173#13 in exactly that block, crt shipped the
# queue, and apms was never told; a human found the mismatch by reading both
# repos an hour later.
#
# PULL, NOT PUSH, and that is the whole design. A closing repo would have to
# find and write into every repo waiting on it -- cross-repo writes, and a
# judgement about scope it does not have. Instead each project checks ITS OWN
# blocked issues on ITS OWN tick, using ITS OWN credential. Idempotent, needs
# no new permission, and a project that never runs simply never learns -- which
# is correct, because nothing was waiting on it either.
#
# NOTIFY AND UNBLOCK (Zach, 2026-08-25, choosing among three options in #299):
# comment what landed, and drop the `deferred` label so the signal is visible
# to the run and to a human. It does NOT close, reopen, or re-scope anything --
# deciding what the unblocked work now is belongs to the run, not to this.
# CLONE-FREE BY CONSTRUCTION, because per-account clones are being retired
# (Zach, 2026-08-25: "clones need to get retired in v2"). This script resolves
# schedule/<project>.conf relative to ITSELF, reads the tracker over `gh`, and
# touches no working tree -- so it runs identically from a clone today and from
# the verb build after clones go. It is carried on `bashified` for that reason.
#
# ITS CALLER IS THE PART THAT IS NOT CLONE-FREE YET: bin/scheduler-run is not
# carried (hf7y/scheduler#130, alongside usage-gate.sh and sync-crontab.sh), so
# on a host with no checkout nothing invokes this. That gap is #130's, not a
# new one -- this adds one more script waiting on it rather than pretending
# otherwise.
set -uo pipefail

CLI_NAME='route-deliveries.sh'
CLI_SUMMARY='tell this project when an issue it was waiting on has closed'
CLI_USAGE='  route-deliveries.sh <project> [--check|--apply]

  --check   report what would be routed; writes nothing (default)
  --apply   comment on each unblocked issue and drop its `deferred` label'
CLI_FLAGS='--check --apply'
CLI_POSITIONAL='<project>'
CLI_EXITS='  0  nothing to route, or routed successfully
  2  usage error
  4  no schedule/<project>.conf, or it names no REPO_URL
  6  BLIND -- gh could not read the tracker. Never a silent "nothing to do".'

MODE=--check; PROJECT=''
for a in "$@"; do
  case "$a" in
    --check|--apply) MODE="$a" ;;
    -h|--help) printf '%s -- %s\n\nusage:\n%s\n' "$CLI_NAME" "$CLI_SUMMARY" "$CLI_USAGE"; exit 0 ;;
    -*) echo "$CLI_NAME: unknown flag $a" >&2; exit 2 ;;
    *) PROJECT="$a" ;;
  esac
done
[ -n "$PROJECT" ] || { echo "$CLI_NAME: name a project" >&2; exit 2; }

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONF="$HERE/../schedule/$PROJECT.conf"
[ -f "$CONF" ] || { echo "$CLI_NAME: no $CONF" >&2; exit 4; }
# shellcheck disable=SC1090
REPO_URL="$(. "$CONF" >/dev/null 2>&1; printf '%s' "${REPO_URL:-}")"
[ -n "$REPO_URL" ] || { echo "$CLI_NAME: $CONF names no REPO_URL" >&2; exit 4; }
SLUG="${REPO_URL#*github.com/}"; SLUG="${SLUG%.git}"

command -v gh >/dev/null 2>&1 || { echo "$CLI_NAME: BLIND -- gh is not on PATH" >&2; exit 6; }

# The marker makes this idempotent WITHOUT a state file: a second run sees its
# own previous comment and skips. A state file on one account's disk would be
# invisible to every other account and would re-notify after any reprovision.
marker() { printf 'routed-delivery:%s' "$1"; }

# ONE round trip in, ONE round trip out (#580) -- comments come back with
# the issues here, and every dependency ref resolves in one graphql call below.
issues="$(gh issue list -R "$SLUG" --state open --limit 100 --json number,body,labels,comments 2>/dev/null)" \
  || { echo "$CLI_NAME: BLIND -- could not read $SLUG's open issues" >&2; exit 6; }

declare -A ref_needed ref_alias
work=()
checked=0
# Fields are \x1f-joined and records \0-terminated, not tab/newline (as `@tsv`
# gives): tab is IFS *whitespace* even when IFS is set to nothing but tab, so
# `read` collapses an empty field adjacent to it into the next one instead of
# preserving it -- an issue with no labels loses its whole `comments` field to
# `labels` this way, `already`'s marker-grep against it always misses, and
# route-deliveries re-posts the same delivery every tick (measured on
# hf7y/crt#148, labelless, 5 duplicate comments in an hour before this fix).
# \x1f is not IFS whitespace, so an empty field between two of them survives.
while IFS=$'\x1f' read -r -d '' num body labels comments; do
  [ -n "$num" ] || continue
  # Only the DEFERRED block. A ref elsewhere in a body is prose, not a claim.
  block="$(printf '%s' "$body" | awk '/<!--[[:space:]]*DEFERRED/{f=1;next} /<!--[[:space:]]*\/DEFERRED/{f=0} f')"
  [ -n "$block" ] || continue
  while read -r ref; do
    [ -n "$ref" ] || continue
    checked=$((checked + 1))
    already=0
    printf '%s' "$comments" | grep -qF "$(marker "$ref")" && already=1
    [ "$already" -eq 0 ] && ref_needed["$ref"]=1
    work+=("$num"$'\t'"$ref"$'\t'"$already"$'\t'"$labels")
  done <<< "$(printf '%s' "$block" | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+' | sort -u)"
done < <(printf '%s' "$issues" | jq -j '.[] | (.number|tostring), "\u001f", (.body // ""), "\u001f", ([.labels[].name] | join(",")), "\u001f", ([.comments[].body] | join("\n")), "\u0000"')

declare -A state_of
if [ "${#ref_needed[@]}" -gt 0 ]; then
  q=''; i=0
  for ref in "${!ref_needed[@]}"; do
    alias="r$i"; ref_alias["$ref"]="$alias"; i=$((i + 1))
    dep_repo="${ref%#*}"; dep_num="${ref##*#}"
    owner="${dep_repo%%/*}"; name="${dep_repo#*/}"
    q+="$alias: repository(owner: \"$owner\", name: \"$name\") { issueOrPullRequest(number: $dep_num) { __typename ... on Issue { state } ... on PullRequest { state } } } "
  done
  resp="$(gh api graphql -f query="query { $q }" 2>/dev/null)" \
    || { echo "$CLI_NAME: BLIND -- could not resolve ${#ref_needed[@]} dependency ref(s) via graphql" >&2; exit 6; }
  while IFS=$'\t' read -r alias state; do
    [ -n "$alias" ] || continue
    state_of["$alias"]="$state"
  done < <(jq -r '.data // {} | to_entries[] | [.key, (.value.issueOrPullRequest.state // "")] | @tsv' <<< "$resp")
fi

routed=0
for item in "${work[@]}"; do
  IFS=$'\t' read -r num ref already labels <<< "$item"
  [ "$already" -eq 0 ] || continue
  # MERGED, not just CLOSED -- see hf7y/crt#70.
  state="${state_of[${ref_alias[$ref]:-}]:-}"
  case "$state" in CLOSED|MERGED) ;; *) continue ;; esac
  routed=$((routed + 1))
  if [ "$MODE" = --check ]; then
    printf '  WOULD ROUTE  %s#%s <- %s closed\n' "$SLUG" "$num" "$ref"
    continue
  fi
  gh issue comment "$num" -R "$SLUG" --body "**$ref is $state** — something this issue declared itself waiting on has landed.

Routed automatically by \`route-deliveries.sh\` on ${PROJECT}'s dispatch, reading this issue's own \`<!-- DEFERRED -->\` block. It says what landed, not what to do about it: whether the remaining work here is still correct is this repo's call.

<!-- $(marker "$ref") -->" >/dev/null 2>&1 \
    && printf '  ROUTED  %s#%s <- %s\n' "$SLUG" "$num" "$ref" \
    || printf '  FAILED  could not comment on %s#%s\n' "$SLUG" "$num"
  case "$labels" in
    *deferred*) gh issue edit "$num" -R "$SLUG" --remove-label deferred >/dev/null 2>&1 \
                  && printf '  -label  deferred removed from %s#%s\n' "$SLUG" "$num" ;;
  esac
done

printf '%s: %s -- %d dependency ref(s) checked, %d routed (%s)\n' \
  "$CLI_NAME" "$SLUG" "$checked" "$routed" "${MODE#--}"
