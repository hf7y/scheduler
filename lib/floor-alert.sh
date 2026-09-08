#!/usr/bin/env bash
# floor-alert.sh -- ping Zach once via send_zach on a floor transition (#672); sourced, entry point floor_alert_maybe_ping PROJECT WALL STATE_DIR [PERSIST_H].

floor_alert_decide() {
  local wall="$1" state_file="$2" every_h="${3:-12}" prev_wall='' prev_at='' now
  now="$(date +%s)"
  if [ -r "$state_file" ]; then
    IFS=$'\t' read -r prev_wall prev_at < "$state_file"
  fi
  if [ "$wall" != "$prev_wall" ]; then
    printf 'TRANSITION\n'
    return 0
  fi
  case "$prev_at" in
    ''|*[!0-9]*) printf 'TRANSITION\n'; return 0 ;;
  esac
  if [ $(( (now - prev_at) / 3600 )) -ge "$every_h" ]; then
    printf 'PERSIST\n'
  else
    printf 'NONE\n'
  fi
}

floor_alert_mark_sent() {
  printf '%s\t%s\n' "$1" "$(date +%s)" > "$2"
}

floor_alert_render() {
  printf '*%s* %s' "$1" "$2"
}

floor_alert_fit() {
  local from="$1" body="$2" max=$(( 140 - ${#1} - 3 ))
  [ "$max" -ge 0 ] || max=0
  printf '%s' "${body:0:$max}"
}

floor_alert_send_zach() {
  local message="$1" from="${2:-scheduler}" url hdr sid payload out status
  for url in ${FLOOR_ALERT_DOOR:-http://127.0.0.1:8643/mcp http://100.107.253.56:8643/mcp}; do
    hdr="$(mktemp)" || continue
    curl -s -D "$hdr" -o /dev/null --connect-timeout 3 -m 8 -X POST "$url" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"floor-alert","version":"1"}}}' \
      >/dev/null 2>&1
    sid="$(tr -d '\r' < "$hdr" | awk 'tolower($1)=="mcp-session-id:"{print $2}')"
    rm -f "$hdr"
    [ -n "$sid" ] || continue
    curl -s -o /dev/null --connect-timeout 3 -m 8 -X POST "$url" -H "mcp-session-id: $sid" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null 2>&1
    payload="$(printf '%s' "$message" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" || continue
    out="$(curl -s --connect-timeout 3 -m 15 -X POST "$url" -H "mcp-session-id: $sid" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"send_zach\",\"arguments\":{\"message\":$payload,\"from_agent\":\"$from\"}}}" 2>/dev/null)"
    status="$(printf '%s' "$out" | python3 -c '
import json, sys
raw = sys.stdin.read()
lines = [l[6:] for l in raw.splitlines() if l.startswith("data: ")] or [raw]
try:
    r = json.loads(lines[-1])["result"]["content"][0]["text"]
    print(json.loads(r).get("status", ""))
except Exception:
    print("")
' 2>/dev/null)"
    [ "$status" = sent ] && return 0
  done
  return 1
}

floor_alert_maybe_ping() {
  local project="$1" wall="$2" state_dir="$3" every_h="${4:-${FLOOR_ALERT_PERSIST_H:-12}}"
  local state_file="$state_dir/floor-alert-$project" decision from body
  mkdir -p "$state_dir" 2>/dev/null || return 1
  decision="$(floor_alert_decide "$wall" "$state_file" "$every_h")"
  [ "$decision" = NONE ] && return 0
  from="${FLOOR_ALERT_FROM:-scheduler}"
  body="$(floor_alert_fit "$from" "$project at tempo floor ($wall); holding, not paging again for ${every_h}h")"
  floor_alert_send_zach "$body" "$from" || return 1
  floor_alert_mark_sent "$wall" "$state_file"
}
