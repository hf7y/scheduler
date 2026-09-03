#!/usr/bin/env bash
# interchange-probe.sh -- does one repo's work get filed into another repo's
# tracker and picked up there? Reads every roster tracker live; stores nothing.
#
# RUNNER: tests/interchange-probe-witness.sh
set -uo pipefail

CLI_NAME='interchange-probe.sh'
GH_BIN="${INTERCHANGE_GH_BIN:-gh}"
WINDOW_H="${INTERCHANGE_WINDOW_HOURS:-168}"

usage() {
  cat <<EOF
usage: $CLI_NAME [--window-hours N]

Counts issues closed in the window whose body cites another roster repo's
issue or PR -- work filed by one repo and finished by another.

  --window-hours N   rolling window, default $WINDOW_H

exit: 0 OK (at least one)  1 DOWN (none)  2 usage  6 BLIND (a tracker unreadable)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --window-hours) shift; WINDOW_H="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$CLI_NAME: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$WINDOW_H" =~ ^[0-9]+$ ]] && [ "$WINDOW_H" -gt 0 ] || { echo "$CLI_NAME: --window-hours wants a positive integer" >&2; exit 2; }

SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" || SELF_REAL="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd "$(dirname "$SELF_REAL")/.." && pwd)"
CONF_DIR="${TEMPO_CONF_DIR:-$REPO_ROOT/schedule}"

source "$REPO_ROOT/lib/blind-witness.sh"

declare -A SLUG_OF
for conf in "$CONF_DIR"/*.conf; do
  base="$(basename "$conf" .conf)"
  case "$base" in _*) continue ;; esac
  url="$(grep -E '^[[:space:]]*REPO_URL[[:space:]]*=' "$conf" | tail -n1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//; s#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##')"
  [ -n "$url" ] && SLUG_OF["$base"]="$url"
done
[ "${#SLUG_OF[@]}" -gt 0 ] || blind "no $CONF_DIR/*.conf names a tracker"

T0_ISO="$(date -u -d "@$(( $(date +%s) - WINDOW_H * 3600 ))" +%Y-%m-%dT%H:%M:%SZ)"
NAMES="$(printf '%s\n' "${!SLUG_OF[@]}" | paste -sd'|')"

CLOSED=0; CROSS_CLOSED=0; CROSS_OPEN=0
for p in "${!SLUG_OF[@]}"; do
  slug="${SLUG_OF[$p]}"
  json="$("$GH_BIN" issue list --repo "$slug" --state all --limit 300 \
    --json number,state,createdAt,closedAt,url,title,body 2>/dev/null)"
  [ -n "$json" ] && jq -e . >/dev/null 2>&1 <<<"$json" || blind "could not read $slug"
  while IFS=$'\t' read -r state url cited title; do
    [ -n "$url" ] || continue
    if [ "$state" = CLOSED ]; then
      CLOSED=$((CLOSED+1)); CROSS_CLOSED=$((CROSS_CLOSED+1))
      printf 'CLOSED  filed-by=%-16s %s  %s\n' "$cited" "$url" "${title:0:52}"
    else
      CROSS_OPEN=$((CROSS_OPEN+1))
      printf 'OPEN    filed-by=%-16s %s  %s\n' "$cited" "$url" "${title:0:52}"
    fi
  done < <(jq -r --arg t0 "$T0_ISO" --arg self "$p" --arg names "$NAMES" '
    .[]
    | select((.state=="OPEN" and .createdAt > $t0) or (.closedAt // "") > $t0)
    | . as $i
    | [ ((.body // "") | [ scan("(?:hf7y/)?(" + $names + ")#[0-9]+") ] | flatten
        | map(select(. != $self)) | unique | join(",")) ] as $c
    | select($c[0] != "")
    | [ $i.state, $i.url, $c[0], $i.title ] | @tsv' <<<"$json")
done

FACTS="window_h=$WINDOW_H since=$T0_ISO cross_closed=$CROSS_CLOSED cross_open=$CROSS_OPEN repos=${#SLUG_OF[@]}"
if [ "$CROSS_CLOSED" -gt 0 ]; then
  printf 'verdict=OK %s\n' "$FACTS"
  exit 0
fi
printf 'verdict=DOWN %s reason=no_cross_filed_issue_was_closed_in_window\n' "$FACTS"
exit 1
