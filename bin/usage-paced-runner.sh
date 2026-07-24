#!/usr/bin/env bash
# usage-paced-runner.sh -- the pacing dispatcher (replaces the fixed nightly clock).
#
# Driven by a frequent cron tick. On each tick:
#   1. Take a global flock. If a cycle is already running, exit at once -- only
#      ONE tick's worth of dispatching runs at a time, so usage climbs in
#      controlled steps, never two ticks stacking concurrently.
#   2. Ask usage-gate.sh whether there is spare weekly quota. HOLD -> log + exit
#      (cheap: a ~23-token probe). ERROR -> treat as HOLD (fail safe).
#   3. RUN -> pick the NEXT enabled participant (round-robin via a pointer file)
#      and run ONE cycle of it. Then RE-CHECK the gate (live headers reflect the
#      tokens that cycle just spent) and, if still RUN, dispatch the next one in
#      rotation -- up to PACED_MAX_PER_TICK -- before giving the tick back.
#
# Why loop instead of one-and-done: a single dispatch per cron tick caps
# throughput at (participants per hour) regardless of how much slack the gate
# reports, so a lot of quota went unused between ticks even under heavy slack.
# Looping drains whatever slack actually exists, tick by tick, while the gate
# (re-probed each iteration, not assumed) still owns the real stop condition --
# this only removes the artificial one-per-tick ceiling, not the safety logic.
#
# Participants come from schedule/_paced.conf (name|enabled|command). Each
# participant command is a self-contained wrapper with its own lock + logging.
#
# Env knobs (forwarded to usage-gate.sh): USAGE_CEILING, USAGE_MIN_SLACK,
# USAGE_PROBE_MODEL. Plus:
#   PACED_CONF        (schedule/_paced.conf beside this script's repo)
#   USAGE_GATE        (~/.local/bin/usage-gate.sh)
#   PACED_FORCE       (0)  1 = skip the gate and run the next participant now (testing)
#   PACED_MAX_PER_TICK (8) hard cap on dispatches in one tick, so a single cron
#                      firing can't monopolize the flock indefinitely if the
#                      gate keeps reporting RUN (e.g. a probe stuck reporting
#                      stale slack). The next tick simply continues rotation.
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
# Format: name|enabled|command, with an OPTIONAL weight inserted as a third
# field (name|enabled|weight|command) -- realisateur is expected to set this,
# scheduler only enforces it mechanically (see docs/priority-weight.md).
# Weight is a positive integer >=1; omitted/invalid defaults to 1. A weight-N
# participant gets N turns in the rotation for every 1 turn a weight-1
# participant gets (implemented by literally repeating it N times in the
# rotation pool below), so ties still resolve by plain round-robin order.
names=(); cmds=()
if [ ! -f "$PACED_CONF" ]; then log "no participants conf at $PACED_CONF"; exit 1; fi
while IFS='|' read -r name enabled rest; do
  case "$name" in ''|\#*) continue ;; esac          # skip blank / comment lines
  [ "${enabled// /}" = "1" ] || continue
  name="${name// /}"
  rest="${rest#"${rest%%[![:space:]]*}"}"   # trim leading whitespace
  weight=1
  case "$rest" in
    [0-9]*'|'*)
      maybe_weight="${rest%%|*}"
      if [[ "$maybe_weight" =~ ^[0-9]+$ ]] && [ "$maybe_weight" -ge 1 ]; then
        weight="$maybe_weight"
        rest="${rest#*|}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
      fi
      ;;
  esac
  cmd="$rest"
  for ((_w=0; _w<weight; _w++)); do
    names+=("$name"); cmds+=("$cmd")
  done
done < "$PACED_CONF"

n="${#names[@]}"
if [ "$n" -eq 0 ]; then log "no enabled participants -- nothing to dispatch"; exit 0; fi

MAX_PER_TICK="${PACED_MAX_PER_TICK:-8}"

# --- dispatch loop --------------------------------------------------------
# Each iteration re-checks the gate against LIVE headers -- the previous
# cycle's spend has already landed by the time we re-probe -- so this stops
# as soon as the account is genuinely on-pace/at-ceiling, not after a fixed
# count. MAX_PER_TICK is just a runaway backstop, not the normal stop reason.
dispatched=0
while [ "$dispatched" -lt "$MAX_PER_TICK" ]; do
  if [ "${PACED_FORCE:-0}" = "1" ]; then
    log "PACED_FORCE=1 -- skipping usage gate"
  else
    verdict="$("$USAGE_GATE" 2>/dev/null)"; rc=$?
    summary="$(printf '%s\n' "$verdict" | grep -E '^verdict=|^# ' | tr '\n' ' ')"
    if [ "$rc" -ne 0 ]; then
      log "HOLD (gate rc=$rc) $summary"
      break
    fi
    log "RUN  $summary"
  fi

  # pick next enabled participant (round-robin)
  last=-1; [ -f "$PTR" ] && last="$(cat "$PTR" 2>/dev/null || echo -1)"
  case "$last" in ''|*[!0-9-]*) last=-1 ;; esac
  idx=$(( (last + 1) % n ))

  name="${names[$idx]}"; cmd="${cmds[$idx]}"
  echo "$idx" > "$PTR"

  # resolve the command's program (first token) to check it exists
  prog="${cmd%% *}"
  if [ ! -x "$prog" ] && ! command -v "$prog" >/dev/null 2>&1; then
    log "SKIP $name -- command not runnable: $cmd"
    dispatched=$((dispatched + 1))
    continue
  fi

  log "DISPATCH [$idx/$n] $name -> $cmd"
  start=$(date +%s)
  # shellcheck disable=SC2086
  if $cmd; then rc=0; else rc=$?; fi
  log "DONE $name rc=$rc ($(( $(date +%s) - start ))s)"
  dispatched=$((dispatched + 1))
done

if [ "$dispatched" -ge "$MAX_PER_TICK" ]; then
  log "PACED_MAX_PER_TICK ($MAX_PER_TICK) reached -- yielding tick, rotation continues next tick"
fi
exit 0
