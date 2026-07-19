#!/usr/bin/env bash
# usage-paced-runner.sh -- the pacing dispatcher (replaces the fixed nightly clock).
#
# Driven by a frequent cron tick. On each tick:
#   1. Take a global flock. If a cycle is already running, exit at once -- only
#      ONE participant cycle runs at a time, so usage climbs in controlled steps.
#   2. Ask usage-gate.sh whether there is spare weekly quota. HOLD -> log + exit
#      (cheap: a ~23-token probe). ERROR -> treat as HOLD (fail safe).
#   3. RUN -> pick the NEXT enabled participant (round-robin via a pointer file)
#      and run ONE cycle of it. Then exit; the next tick continues the rotation.
#
# Participants come from schedule/_paced.conf (name|enabled|command). Each
# participant command is a self-contained wrapper with its own lock + logging.
#
# Env knobs (forwarded to usage-gate.sh): USAGE_CEILING, USAGE_MIN_SLACK,
# USAGE_PROBE_MODEL. Plus:
#   PACED_CONF   (schedule/_paced.conf beside this script's repo)
#   USAGE_GATE   (~/.local/bin/usage-gate.sh)
#   PACED_FORCE  (0)  1 = skip the gate and run the next participant now (testing)
set -uo pipefail

JOB_NAME="scheduler-paced-runner"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
PTR="$STATE_DIR/rotation.idx"

PACED_CONF="${PACED_CONF:-/home/zach/Documents/Project Archive/scheduler/schedule/_paced.conf}"
USAGE_GATE="${USAGE_GATE:-$HOME/.local/bin/usage-gate.sh}"
[ -x "$USAGE_GATE" ] || USAGE_GATE="$SELF_DIR/usage-gate.sh"
NODE_BIN_DIR="${NODE_BIN_DIR:-/home/zach/.nvm/versions/node/v25.2.1/bin}"

export PATH="$NODE_BIN_DIR:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

mkdir -p "$STATE_DIR"

exec 200>"$LOCK"
if ! flock -n 200; then
  # a cycle is already in progress -- serialize, don't stack
  exit 0
fi
[ -f "$LOG" ] && { tail -n 4000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }

log() { echo "$(date -Is) $*" >> "$LOG"; }

# --- load enabled participants -------------------------------------------------
names=(); cmds=()
if [ ! -f "$PACED_CONF" ]; then log "no participants conf at $PACED_CONF"; exit 1; fi
while IFS='|' read -r name enabled cmd; do
  case "$name" in ''|\#*) continue ;; esac          # skip blank / comment lines
  [ "${enabled// /}" = "1" ] || continue
  name="${name// /}"; cmd="${cmd#"${cmd%%[![:space:]]*}"}"   # trim
  names+=("$name"); cmds+=("$cmd")
done < "$PACED_CONF"

n="${#names[@]}"
if [ "$n" -eq 0 ]; then log "no enabled participants -- nothing to dispatch"; exit 0; fi

# --- gate ---------------------------------------------------------------------
if [ "${PACED_FORCE:-0}" = "1" ]; then
  log "PACED_FORCE=1 -- skipping usage gate"
else
  verdict="$("$USAGE_GATE" 2>/dev/null)"; rc=$?
  summary="$(printf '%s\n' "$verdict" | grep -E '^verdict=|^# ' | tr '\n' ' ')"
  if [ "$rc" -ne 0 ]; then
    log "HOLD (gate rc=$rc) $summary"
    exit 0
  fi
  log "RUN  $summary"
fi

# --- pick next enabled participant (round-robin) ------------------------------
last=-1; [ -f "$PTR" ] && last="$(cat "$PTR" 2>/dev/null || echo -1)"
case "$last" in ''|*[!0-9-]*) last=-1 ;; esac
idx=$(( (last + 1) % n ))

name="${names[$idx]}"; cmd="${cmds[$idx]}"
echo "$idx" > "$PTR"

# resolve the command's program (first token) to check it exists
prog="${cmd%% *}"
if [ ! -x "$prog" ] && ! command -v "$prog" >/dev/null 2>&1; then
  log "SKIP $name -- command not runnable: $cmd"
  exit 0
fi

log "DISPATCH [$idx/$n] $name -> $cmd"
start=$(date +%s)
# shellcheck disable=SC2086
if $cmd; then rc=0; else rc=$?; fi
log "DONE $name rc=$rc ($(( $(date +%s) - start ))s)"
exit 0
