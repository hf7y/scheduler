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
# Participants come from a participants conf (name|enabled|command), chosen
# PER HOST -- see "which participants file" below. Each participant command is
# a self-contained wrapper with its own lock + logging.
#
# Env knobs (forwarded to usage-gate.sh): USAGE_CEILING, USAGE_MIN_SLACK,
# USAGE_PROBE_MODEL. Plus:
#   PACED_CONF        (explicit participants file; otherwise host-resolved)
#   PACED_HOST        (short hostname; overrides which host-scoped conf is picked)
#   USAGE_GATE        (~/.local/bin/usage-gate.sh)
#   PACED_FORCE       (0)  1 = skip the gate and run the next participant now (testing)
#   PACED_MAX_PER_TICK (8) hard cap on dispatches in one tick, so a single cron
#                      firing can't monopolize the flock indefinitely if the
#                      gate keeps reporting RUN (e.g. a probe stuck reporting
#                      stale slack). The next tick simply continues rotation.
set -uo pipefail

JOB_NAME="scheduler-paced-runner"

# Resolve symlinks BEFORE taking dirname: this script is normally invoked as
# ~/.local/bin/usage-paced-runner.sh, a symlink into the repo. Plain
# `dirname "${BASH_SOURCE[0]}"` would yield ~/.local/bin and never find the
# repo's schedule/ directory.
SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"
[ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF_REAL")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." 2>/dev/null && pwd)"
: "${REPO_ROOT:=}"   # empty is fine -- the checks below just fall through

STATE_DIR="$HOME/.local/share/$JOB_NAME"
LOG="$STATE_DIR/run.log"
LOCK="$STATE_DIR/run.lock"
PTR="$STATE_DIR/rotation.idx"

USAGE_GATE="${USAGE_GATE:-$HOME/.local/bin/usage-gate.sh}"
[ -x "$USAGE_GATE" ] || USAGE_GATE="$SELF_DIR/usage-gate.sh"
NODE_BIN_DIR="${NODE_BIN_DIR:-/home/zach/.nvm/versions/node/v25.2.1/bin}"

# mandark reaches `claude` through nvm; dexter has a native binary in
# ~/.local/bin and no nvm at all. Prepend the node dir only when it exists,
# and always APPEND ~/.local/bin (cron's default PATH omits it) -- appending
# can add a resolution but can never shadow one that already worked.
[ -d "$NODE_BIN_DIR" ] && export PATH="$NODE_BIN_DIR:$PATH"
export PATH="$PATH:$HOME/.local/bin"
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

# --- pull before dispatch (2026-07-24) ---------------------------------------
# This repo is shared RUNNING CODE across two hosts now, not just shared
# config -- mandark and dexter each execute this script and lib/*.sh straight
# out of their own checkout on a */5 cron tick, with no human in the loop.
# A commit pushed from one host has zero effect on the other's behavior until
# that checkout is updated. Runs inside the flock (one pull per host per tick,
# never overlapping with a dispatch already in flight) and BEFORE the
# participants-file resolution below, so a freshly pulled host-scoped conf
# (e.g. a brand new schedule/_paced.<host>.conf) takes effect the same tick
# it lands, not one tick later.
#
# Fail-loud-not-block, same philosophy as the usage gate's ERROR->HOLD: a
# pull that can't happen cleanly (dirty tree, diverged history, no network)
# is logged loudly and the tick proceeds on whatever is already checked
# out -- one stale tick beats a dispatcher that stops ticking entirely
# because of a merge conflict only a human can resolve. --ff-only refuses to
# fabricate a merge commit unattended; a real divergence (this host has local
# commits origin doesn't) is left exactly as found, for a human/session pull
# to sort out, same as the mandark/dexter divergence QUESTIONS.md already
# flagged the same day this was built.
if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/.git" ]; then
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
    log "PULL skip -- $REPO_ROOT has uncommitted changes"
  elif ! timeout 20 git -C "$REPO_ROOT" fetch --quiet origin main 2>>"$LOG"; then
    log "PULL skip -- fetch failed or timed out (network/auth?)"
  elif git -C "$REPO_ROOT" merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
    : # already up to date (or ahead) -- nothing to log every 5 minutes
  elif git -C "$REPO_ROOT" merge --ff-only origin/main --quiet 2>>"$LOG"; then
    log "PULL fast-forwarded to $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  else
    log "PULL WARNING -- $REPO_ROOT diverged from origin/main, code here may be stale (needs a human/session merge, not auto-resolved)"
  fi
fi

# --- which participants file? (host-scoped, 2026-07-24) ---------------------
# Two hosts now run this dispatcher out of ONE git-tracked repo (mandark and
# dexter -- see DESIGN-NOTES.md "multi-machine parallelism"). A single shared
# schedule/_paced.conf can't express that: the hosts pin different projects,
# and that file already has an AUTOMATED writer (weight-audit.sh rewrites
# weights and commits them), so aiming both hosts at one file means two
# machines rewriting the same lines. So each host MAY own its own file:
#
#   schedule/_paced.<short-hostname>.conf   this host's rotation, if present
#   schedule/_paced.conf                    shared/default, used otherwise
#
# A host only ever writes its OWN file, so two hosts cannot fight over one set
# of lines by construction -- they're different paths, not different edits to
# one path. A host with no host-scoped file reads _paced.conf exactly as
# before, which is what mandark still does today: this change is a no-op there
# until someone adds a _paced.mandark.conf.
#   List registered hosts:  ls schedule/_paced.*.conf
LEGACY_PACED_CONF="/home/zach/Documents/Project Archive/scheduler/schedule/_paced.conf"
PACED_HOST="${PACED_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}"
if [ -n "${PACED_CONF:-}" ]; then
  PACED_CONF_SRC="explicit PACED_CONF"
elif [ -f "$REPO_ROOT/schedule/_paced.$PACED_HOST.conf" ]; then
  PACED_CONF="$REPO_ROOT/schedule/_paced.$PACED_HOST.conf"
  PACED_CONF_SRC="host-scoped for $PACED_HOST"
elif [ -f "$REPO_ROOT/schedule/_paced.conf" ]; then
  PACED_CONF="$REPO_ROOT/schedule/_paced.conf"
  PACED_CONF_SRC="shared (no _paced.$PACED_HOST.conf)"
else
  # Last resort: a copied-not-symlinked install whose repo we can't locate.
  PACED_CONF="$LEGACY_PACED_CONF"
  PACED_CONF_SRC="legacy absolute path (repo not found from $SELF_DIR)"
fi

# --- load enabled participants -------------------------------------------------
# Format: name|enabled|command, with an OPTIONAL weight inserted as a third
# field (name|enabled|weight|command) -- realisateur is expected to set this,
# scheduler only enforces it mechanically (see docs/priority-weight.md).
# Weight is a positive integer >=1; omitted/invalid defaults to 1. A weight-N
# participant gets N turns in the rotation for every 1 turn a weight-1
# participant gets (implemented by literally repeating it N times in the
# rotation pool below), so ties still resolve by plain round-robin order.
names=(); cmds=()
if [ ! -f "$PACED_CONF" ]; then
  log "FATAL no participants conf at $PACED_CONF [$PACED_CONF_SRC] host=$PACED_HOST"
  exit 1
fi
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
if [ "$n" -eq 0 ]; then
  # Loud on purpose: on a freshly-registered host this is the difference
  # between "correctly idle" and "silently pointed at the wrong file".
  log "no enabled participants in $PACED_CONF [$PACED_CONF_SRC] host=$PACED_HOST -- nothing to dispatch"
  exit 0
fi

# Log the resolved rotation only when it CHANGES, not every tick (a tick fires
# every 5 min; the RUN/HOLD line is already per-tick). A host silently moving
# between participants files -- e.g. its host-scoped conf being added, renamed
# or deleted underneath it -- is exactly the drift that would otherwise be
# invisible, so make the transition itself the log event.
ROTATION_SIG="$STATE_DIR/rotation.sig"
sig="host=$PACED_HOST conf=$PACED_CONF [$PACED_CONF_SRC] slots=$n :: ${names[*]}"
if [ "$sig" != "$(cat "$ROTATION_SIG" 2>/dev/null || true)" ]; then
  log "ROTATION $sig"
  printf '%s' "$sig" > "$ROTATION_SIG"
fi

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

  # Dead-man-switch awareness (2026-07-26, FOCUS.md EXPIRY_DAYS finding 2):
  # an expired participant used to consume a full dispatch slot and record
  # as a normal DISPATCH/DONE pair -- this runner had no expires_at
  # awareness at all, so expired jobs no-op'd visibly only in their own
  # sweep.log. The job's state dir is derived from the wrapper filename by
  # the same <job>-loop.sh convention the wrappers themselves use
  # (chezz-nightly-batch-loop.sh -> ~/.local/share/chezz-nightly-batch);
  # a command that doesn't match the convention (scheduler-dev-cycle.sh)
  # has no expires_at at the derived path and dispatches exactly as
  # before -- fail-open, never fail-blocked. Belt-and-braces with
  # lib/sweep-loop-common.sh's own pre-clone check (which exits 3): this
  # skip saves the dispatch slot, that one saves the clone if a job
  # expires between here and its own check, or arrives via cron instead.
  # Counts toward MAX_PER_TICK like the not-runnable SKIP above, so an
  # all-expired rotation still terminates the tick loop.
  job_state="$HOME/.local/share/$(basename "$prog" | sed 's/-loop\.sh$//')"
  if [ -f "$job_state/expires_at" ]; then
    expires_at="$(cat "$job_state/expires_at" 2>/dev/null)"
    if [ -n "$expires_at" ] && [[ "$(date -Is)" > "$expires_at" ]]; then
      log "SKIP $name -- EXPIRED $expires_at (dead-man switch; renew: rm $job_state/expires_at, next run re-stamps now+EXPIRY_DAYS)"
      dispatched=$((dispatched + 1))
      continue
    fi
  fi

  log "DISPATCH [$idx/$n] $name -> $cmd (host=$PACED_HOST conf=$PACED_CONF)"
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
