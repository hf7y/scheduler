#!/usr/bin/env bash
set -uo pipefail  # a `claude -p` run that survives a session-limit death; PR body has caveats, hf7y/scheduler#339

SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"; [ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF_REAL")" && pwd)"

CLAUDE_BIN="${CLAUDE_SUPERVISED_BIN:-claude}"
MAX_RESUMES="${CLAUDE_SUPERVISED_MAX_RESUMES:-6}"
RESET_BUFFER_SEC="${CLAUDE_SUPERVISED_RESET_BUFFER_SEC:-60}"
LOG="${CLAUDE_SUPERVISED_LOG:-/dev/stderr}"

usage() {
  cat <<'EOF'
usage: claude-supervised.sh [--session-id UUID] [--no-claim] -- <claude -p args...>

--session-id UUID   resume handle (generated via python3+uuid if omitted)
--no-claim          do not hold lib/usage-claim.sh's claim for the run
EOF
}

SESSION_ID=""; USE_CLAIM=1; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --no-claim) USE_CLAIM=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; ARGS=("$@"); break ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[ "${#ARGS[@]}" -gt 0 ] || { usage >&2; exit 2; }

if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null)"
  [ -n "$SESSION_ID" ] || { echo "claude-supervised: need python3 or --session-id" >&2; exit 2; }
fi

log() { printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG"; }

parse_reset_epoch() {  # <text> -- "resets 11:40pm (UTC)" -> next epoch at that clock time, or empty
  local hhmm h m ampm epoch now
  hhmm="$(printf '%s\n' "$1" | grep -oE 'resets [0-9]{1,2}:[0-9]{2}(am|pm)' | head -1)"
  [ -n "$hhmm" ] || return 1
  hhmm="${hhmm#resets }"
  ampm="${hhmm: -2}"; hhmm="${hhmm%??}"
  h="${hhmm%%:*}"; m="${hhmm##*:}"
  h="${h#0}"; m="${m#0}"; [ -n "$h" ] || h=0; [ -n "$m" ] || m=0
  [ "$ampm" = pm ] && [ "$h" -ne 12 ] && h=$((h + 12))
  [ "$ampm" = am ] && [ "$h" -eq 12 ] && h=0
  epoch="$(date -u -d "today ${h}:${m}" +%s 2>/dev/null)" || return 1
  now="$(date -u +%s)"
  [ "$epoch" -le "$now" ] && { epoch="$(date -u -d "tomorrow ${h}:${m}" +%s 2>/dev/null)" || return 1; }
  printf '%s\n' "$epoch"
}

run_once() {  # $1 = first|resume
  if [ "$1" = resume ]; then
    "$CLAUDE_BIN" -p --resume "$SESSION_ID" "${ARGS[@]}" 2>&1
  else
    "$CLAUDE_BIN" -p --session-id "$SESSION_ID" "${ARGS[@]}" 2>&1
  fi
}

supervise() {
  local attempt=0 out rc reset_epoch now wait_s
  while :; do
    if [ "$attempt" -eq 0 ]; then out="$(run_once first)"; rc=$?
    else out="$(run_once resume)"; rc=$?
    fi
    printf '%s\n' "$out" | grep -qi 'hit your session limit' || { printf '%s\n' "$out"; return "$rc"; }
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$MAX_RESUMES" ]; then
      log "GIVE-UP session=$SESSION_ID after $MAX_RESUMES resume(s), still hitting the session limit"
      printf '%s\n' "$out"; return 1
    fi
    reset_epoch="$(parse_reset_epoch "$out")"
    if [ -z "$reset_epoch" ]; then
      log "GIVE-UP session=$SESSION_ID -- limit hit but no reset time parsed: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 300)"
      printf '%s\n' "$out"; return 1
    fi
    now="$(date -u +%s)"
    wait_s=$((reset_epoch - now + RESET_BUFFER_SEC))
    [ "$wait_s" -lt 0 ] && wait_s=0
    log "WAIT session=$SESSION_ID attempt=$attempt resumes_at=$(date -u -d "@$reset_epoch" -Is) sleeping=${wait_s}s"
    sleep "$wait_s"
    log "RESUME session=$SESSION_ID attempt=$attempt"
  done
}

if [ "$USE_CLAIM" = 1 ] && [ -r "$SELF_DIR/../lib/usage-claim.sh" ]; then
  . "$SELF_DIR/../lib/usage-claim.sh"
  usage_claim_acquire "claude-supervised(session=$SESSION_ID)"
  arc=$?
  if [ "$arc" -eq 3 ]; then
    echo "REFUSED: quota claim already held -- $(usage_claim_status)" >&2
    exit 3
  fi
  [ "$arc" -eq 0 ] && trap usage_claim_release EXIT
fi

supervise
exit $?
