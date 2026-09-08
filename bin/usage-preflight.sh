#!/usr/bin/env bash
set -uo pipefail  # run BEFORE hand-spawning claude; PR body has constant provenance/caveats, hf7y/scheduler#339

SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"; [ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF_REAL")" && pwd)"
GATE="${USAGE_GATE:-$SELF_DIR/usage-gate.sh}"

usage() {
  cat <<'EOF'
usage: usage-preflight.sh --agents N --minutes M [--effort max|default|low]
       usage-preflight.sh --points P

--agents N       how many subagents/turns you are about to fan out
--minutes M      how long you expect to let it run
--effort E       max (default), default, or low -- a multiplier on the
                  per-agent-minute constant, see file header
--points P       skip the agents model: P points (0-100 scale) of expected
                  utilisation, applied to both windows directly

exit: 0 both windows can fund it, 1 REFUSED (named which window, by how much),
      2 usage/gate-unreadable
EOF
}

AGENTS=""; MINUTES=""; EFFORT="max"; POINTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agents) AGENTS="$2"; shift 2 ;;
    --minutes) MINUTES="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --points) POINTS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

PP_MAX="${USAGE_PREFLIGHT_PP_PER_AGENT_MIN_MAX:-0.35}"
FRAC_DEFAULT="${USAGE_PREFLIGHT_EFFORT_DEFAULT_FRAC:-0.4}"
FRAC_LOW="${USAGE_PREFLIGHT_EFFORT_LOW_FRAC:-0.15}"

if [ -n "$POINTS" ]; then
  case "$POINTS" in ''|*[!0-9.]*) echo "usage-preflight: --points must be a number" >&2; exit 2 ;; esac
  PROJECTED_PP="$POINTS"
  BASIS="--points $POINTS given directly"
else
  [ -n "$AGENTS" ] && [ -n "$MINUTES" ] || { usage >&2; exit 2; }
  case "$AGENTS$MINUTES" in *[!0-9.]*) echo "usage-preflight: --agents/--minutes must be numbers" >&2; exit 2 ;; esac
  case "$EFFORT" in
    max) FRAC=1 ;;
    default) FRAC="$FRAC_DEFAULT" ;;
    low) FRAC="$FRAC_LOW" ;;
    *) echo "usage-preflight: --effort must be max, default or low" >&2; exit 2 ;;
  esac
  PROJECTED_PP="$(awk -v a="$AGENTS" -v m="$MINUTES" -v r="$PP_MAX" -v f="$FRAC" 'BEGIN{printf "%.2f", a*m*r*f}')"
  BASIS="$AGENTS agent(s) x ${MINUTES}min x effort=$EFFORT (~${PROJECTED_PP}pp modelled, see file header)"
fi

OUT="$("$GATE" 2>&1)"; GRC=$?
[ "$GRC" -le 1 ] || { echo "usage-preflight: BLIND -- usage-gate.sh could not read live quota:"; echo "$OUT"; exit 2; }

CEILING="$(printf '%s\n' "$OUT" | grep -m1 -oE 'ceiling=[0-9.]+' | cut -d= -f2)"
[ -n "$CEILING" ] || { echo "usage-preflight: BLIND -- no ceiling in gate output"; exit 2; }

echo "usage-preflight: $BASIS"
echo "usage-preflight: current --"
printf '%s\n' "$OUT" | grep -E '^window=|^# '

REFUSE=0
while IFS= read -r line; do
  w="$(printf '%s' "$line" | grep -oE 'window=[0-9a-z]+' | cut -d= -f2)"
  util="$(printf '%s' "$line" | grep -oE 'util=[0-9.]+' | cut -d= -f2)"
  [ -n "$w" ] && [ -n "$util" ] || continue
  proj="$(awk -v u="$util" -v p="$PROJECTED_PP" 'BEGIN{printf "%.3f", u + p/100}')"
  over="$(awk -v p="$proj" -v c="$CEILING" 'BEGIN{print (p>=c)?1:0}')"
  echo "usage-preflight: $w projects to ${proj} (ceiling ${CEILING})"
  if [ "$over" = 1 ]; then
    echo "usage-preflight: REFUSED -- $w window would reach ${proj}, at/over ceiling ${CEILING}."
    REFUSE=1
  fi
done <<EOF
$(printf '%s\n' "$OUT" | grep '^window=')
EOF

[ "$REFUSE" = 0 ] && echo "usage-preflight: OK -- both windows can fund this launch."
exit "$REFUSE"
