#!/usr/bin/env bash
# thermostat-probe.sh -- does agent work move the derived pace, or only a
# human editing a config? Re-reads the tracker and the dispatch ledger every
# run; stores nothing.
#
# RUNNER: tests/thermostat-probe-witness.sh
set -uo pipefail

CLI_NAME='thermostat-probe.sh'
GH_BIN="${THERMOSTAT_GH_BIN:-gh}"
WINDOW_H="${THERMOSTAT_WINDOW_HOURS:-24}"
MONKEY="${THERMOSTAT_HOST:-monkey}"

usage() {
  cat <<EOF
usage: $CLI_NAME <project> [--window-hours N]

Compares the pace tempo.sh would derive at the start of a config-quiet window
against the pace it derives now, alongside the project's dispatch turn count.

  --window-hours N   rolling window, default $WINDOW_H

exit: 0 OK (pace and turns both moved)  1 DOWN (either stood still)
      2 usage  6 BLIND (tracker, ledger or git history unreadable)
EOF
}

PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window-hours) shift; WINDOW_H="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CLI_NAME: unknown flag $1" >&2; exit 2 ;;
    *) PROJECT="$1" ;;
  esac
  shift
done
[ -n "$PROJECT" ] || { usage >&2; exit 2; }
[[ "$WINDOW_H" =~ ^[0-9]+$ ]] && [ "$WINDOW_H" -gt 0 ] || { echo "$CLI_NAME: --window-hours wants a positive integer" >&2; exit 2; }

blind() { printf 'verdict=BLIND project=%s reason=%s\n' "$PROJECT" "$1"; exit 6; }

SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" || SELF_REAL="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd "$(dirname "$SELF_REAL")/.." && pwd)"
CONF_DIR="${TEMPO_CONF_DIR:-$REPO_ROOT/schedule}"
CONF="$CONF_DIR/$PROJECT.conf"
[ -r "$CONF" ] || blind "no readable $CONF"

SLUG="$(grep -E '^[[:space:]]*REPO_URL[[:space:]]*=' "$CONF" | tail -n1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//; s#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##')"
[ -n "$SLUG" ] || blind "$CONF sets no REPO_URL"

NOW="$(date +%s)"
T0=$(( NOW - WINDOW_H * 3600 ))
T0_ISO="$(date -u -d "@$T0" +%Y-%m-%dT%H:%M:%SZ)"

# The window is only evidence if no knob moved inside it, and that is read out
# of git rather than asserted.
CONF_PATHS=(schedule/_tempo.conf schedule/ROSTER "schedule/$PROJECT.conf")
for f in "$CONF_DIR"/_tempo.*.conf; do [ -e "$f" ] && CONF_PATHS+=("schedule/$(basename "$f")"); done
TOUCHED="$(git -C "$REPO_ROOT" log --since="$T0_ISO" --format=%h -- "${CONF_PATHS[@]}" 2>/dev/null)" \
  || blind "git history unreadable in $REPO_ROOT"
[ -z "$TOUCHED" ] || blind "config_changed_in_window commits=$(tr '\n' ',' <<<"$TOUCHED")"

ISSUES="$("$GH_BIN" issue list --repo "$SLUG" --state all --limit 500 \
  --json number,state,createdAt,closedAt,labels 2>/dev/null)"
[ -n "$ISSUES" ] && jq -e . >/dev/null 2>&1 <<<"$ISSUES" || blind "could not read $SLUG's issues"

read -r OPEN_NOW BLOCKED_NOW OPEN_THEN BLOCKED_THEN CLOSED_IN <<<"$(jq -r \
  --arg t0 "$T0_ISO" --arg lbl "${TEMPO_BLOCKED_LABELS:-needs-human}" '
  ($lbl|split(",")) as $B
  | (map(select(.state=="OPEN"))) as $now
  | (map(select(.createdAt <= $t0 and (.state=="OPEN" or (.closedAt // "9") > $t0)))) as $then
  | def blocked: map(select([.labels[].name] as $l | $B | any(. as $b | $l | index($b)))) | length;
  [ ($now|length), ($now|blocked), ($then|length), ($then|blocked),
    (map(select(.state=="CLOSED" and (.closedAt // "") > $t0))|length) ] | @tsv' <<<"$ISSUES")"

case "$OPEN_NOW$BLOCKED_NOW$OPEN_THEN$BLOCKED_THEN$CLOSED_IN" in ''|*[!0-9]*) blind "could not count $SLUG's issues" ;; esac

BASE_MIN="${TEMPO_BASE_MIN:-120}"; PIVOT="${TEMPO_PIVOT_ISSUES:-12}"
MIN_MIN="${TEMPO_MIN_MIN:-20}"; MAX_MIN="${TEMPO_MAX_MIN:-1440}"
want() {
  local a="$1" div w
  [ "$a" -lt 0 ] && a=0
  div=$a; [ "$div" -lt 1 ] && div=1
  w=$(( (BASE_MIN * PIVOT + div / 2) / div ))
  [ "$w" -lt "$MIN_MIN" ] && w="$MIN_MIN"
  [ "$w" -gt "$MAX_MIN" ] && w="$MAX_MIN"
  printf '%s' "$w"
}
ACT_NOW=$(( OPEN_NOW - BLOCKED_NOW )); ACT_THEN=$(( OPEN_THEN - BLOCKED_THEN ))
WANT_NOW="$(want "$ACT_NOW")"; WANT_THEN="$(want "$ACT_THEN")"

LEDGER="/home/$PROJECT/.local/share/scheduler-paced-runner/ledger.tsv"
if [ -n "${THERMOSTAT_LEDGER_FILE:-}" ]; then
  ROWS="$(cat "$THERMOSTAT_LEDGER_FILE" 2>/dev/null)" || blind "unreadable $THERMOSTAT_LEDGER_FILE"
else
  ROWS="$(ssh -n -o BatchMode=yes "$MONKEY" "sudo -n cat $LEDGER" 2>/dev/null)" \
    || blind "unreadable ledger $MONKEY:$LEDGER"
fi
[ -n "$ROWS" ] || blind "empty ledger for $PROJECT -- no turn number to read"

read -r TURNS_NOW TURNS_THEN <<<"$(awk -F'\t' -v p="$PROJECT" -v t0="$T0_ISO" '
  $4==p && $7!="COOLDOWN" && $7!="BLOCKED-HOLD" { n++; if ($1 < t0) b++ }
  END { printf "%d %d\n", n+0, b+0 }' <<<"$ROWS")"

FACTS="project=$PROJECT repo=$SLUG window_h=$WINDOW_H since=$T0_ISO"
FACTS="$FACTS actionable=$ACT_THEN->$ACT_NOW want_min=$WANT_THEN->$WANT_NOW"
FACTS="$FACTS turns=$TURNS_THEN->$TURNS_NOW closed_in_window=$CLOSED_IN"

if [ "$WANT_THEN" != "$WANT_NOW" ] && [ "$TURNS_NOW" -gt "$TURNS_THEN" ]; then
  printf 'verdict=OK %s\n' "$FACTS"
  exit 0
fi
reason=pace_and_turns_stood_still
[ "$WANT_THEN" != "$WANT_NOW" ] && reason=turns_stood_still
[ "$TURNS_NOW" -gt "$TURNS_THEN" ] && reason=pace_stood_still
if [ "$WANT_THEN" = "$WANT_NOW" ] && { [ "$WANT_NOW" = "$MAX_MIN" ] || [ "$WANT_NOW" = "$MIN_MIN" ]; }; then
  reason="$reason,clamped_at_$WANT_NOW"
fi
printf 'verdict=DOWN %s reason=%s\n' "$FACTS" "$reason"
exit 1
