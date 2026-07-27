#!/usr/bin/env bash
# usage-gate.sh -- the pacing brain's sensor + decision.
#
# Reads your LIVE, account-wide usage from Anthropic's unified rate-limit
# headers and decides whether background jobs may run right now, so autonomous
# work fills the quota you're leaving on the table without pushing you toward
# the cap. Model: drive each window's utilisation along a straight "even-burn"
# line from the window start to 100% at its reset; RUN when actual util is
# BELOW that line (slack going to waste), HOLD when at/over it (you're already
# on pace to spend it) or above a safety ceiling.
#
# Signal: one ~23-token Haiku probe returns headers
#   anthropic-ratelimit-unified-{5h,7d}-{utilization,reset,status}
#   anthropic-ratelimit-unified-representative-claim   (which window binds)
# These are ACCOUNT-WIDE (web, Slack, every machine, jobs), so jobs pace
# against YOUR own usage too -- exactly the requirement. Anthropic enforces a
# rolling 5-hour AND a 7-day window; we honour BOTH and defer to the tighter.
#
# Output: key=val lines + a human summary. Exit code is the verdict:
#   0 = RUN   (every window below its burn-line by >= MIN_SLACK, below CEILING)
#   1 = HOLD  (on/over pace, at ceiling, or a window is 'rejected')
#   2 = ERROR (probe failed / unparseable)  -> callers MUST treat as HOLD
#
# Rush-before-reset (human policy, 2026-07-20): within USAGE_RUSH_BEFORE_RESET_MIN
# minutes of the 7-DAY window's own reset, the even-burn "on-pace" hold is
# dropped entirely (on BOTH windows) -- unused weekly quota doesn't roll
# over, so preserving slack in the final stretch is waste, not caution.
# CEILING and a 'rejected' status still block, same as always -- this only
# removes the pacing-preference hold, not the real safety limits. Expect
# (and accept) the 5h window hitting its ceiling early under this policy;
# it recovers on its own regardless, unlike the weekly budget.
#
# Knobs (each settable in a conf file OR the environment -- see "Where the
# knobs come from" below):
#   USAGE_CEILING     (0.85)  never run above this utilisation on any window
#   USAGE_MIN_SLACK   (0.02)  require this much room below the burn-line to run
#   USAGE_PROBE_MODEL (claude-haiku-4-5-20251001)
#   USAGE_RUSH_BEFORE_RESET_MIN (120)  see "Rush-before-reset" above
# Env-only (per-invocation display, never worth persisting in a conf):
#   USAGE_GATE_QUIET  (0)     1 = print only "RUN"/"HOLD"/"ERROR"
#   USAGE_CONF_DIR            override where _usage*.conf are looked up
#   USAGE_HOST                override the short hostname used for _usage.<host>.conf
#
# Where the knobs come from (2026-07-26) -- ONE source, resolved PER FIELD,
# highest precedence first:
#   1. explicit env            `USAGE_CEILING=0.9 bin/usage-gate.sh` -- always
#                              wins, so one-off tests/overrides keep working.
#   2. schedule/_usage.<host>.conf   per-host override. Two hosts (mandark,
#                              dexter) now share ONE account budget, so a
#                              per-host ceiling is a real want, not
#                              hypothetical -- see DESIGN-NOTES.md
#                              "multi-machine parallelism". Same host-scoped
#                              convention schedule/_paced.<host>.conf uses.
#   3. schedule/_usage.conf    the shared base, and the normal place to set
#                              these -- edit it and the next tick picks it up,
#                              no `sync-crontab.sh --apply`, nothing retyped
#                              onto a crontab line.
#   4. the built-in defaults below (also the fallback for a copy install whose
#                              repo can't be located at all).
# RETIRES: putting `USAGE_CEILING=...` in `schedule/_runner.conf`'s RUNNER_ENV
# (which interpolates it onto the generated crontab line). That path still
# physically works -- it is plain env, so it lands at precedence 1 -- but it is
# no longer the documented way, because it needs `--apply` to take effect and
# ends up stored on a crontab line instead of in a conf. See _runner.conf's
# own comment. Don't set the same knob in both places.
#
# A conf value that isn't a number in range is a hard ERROR (exit 2 -> every
# caller treats that as HOLD), naming the file and the value: a typo'd ceiling
# should stop background dispatch loudly, not silently pace against 0.
set -uo pipefail

QUIET="${USAGE_GATE_QUIET:-0}"
CREDS="$HOME/.claude/.credentials.json"

emit_error() { [ "$QUIET" = "1" ] && echo "ERROR" || echo "verdict=ERROR reason=$1"; exit 2; }

# --- conf resolution --------------------------------------------------------
# Resolve symlinks BEFORE dirname: this script is normally invoked as
# ~/.local/bin/usage-gate.sh. That install is currently a COPY, not a symlink
# (see bin/deploy-drift-check.sh), so repo-relative lookup can and does fail
# -- hence the legacy absolute fallback, same constant convention
# bin/usage-paced-runner.sh and bin/token-usage.sh already use.
LEGACY_SCHED_DIR="/home/zach/Documents/Project Archive/scheduler/schedule"
SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"
[ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF_REAL")" 2>/dev/null && pwd)" || SELF_DIR=""

if [ -n "${USAGE_CONF_DIR:-}" ]; then
  CONF_DIR="$USAGE_CONF_DIR"
elif [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/../schedule" ]; then
  CONF_DIR="$(cd "$SELF_DIR/../schedule" && pwd)"
elif [ -d "$LEGACY_SCHED_DIR" ]; then
  CONF_DIR="$LEGACY_SCHED_DIR"
else
  CONF_DIR=""
fi

GATE_HOST="${USAGE_HOST:-${PACED_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}}"

CONF_FILES=()
if [ -n "$CONF_DIR" ]; then
  # base first, host-scoped second -- later file wins, per field
  [ -f "$CONF_DIR/_usage.conf" ] && CONF_FILES+=("$CONF_DIR/_usage.conf")
  [ -f "$CONF_DIR/_usage.$GATE_HOST.conf" ] && CONF_FILES+=("$CONF_DIR/_usage.$GATE_HOST.conf")
fi

# conf_lookup <KEY> -- sets CONF_VAL/CONF_SRC from the LAST conf file that
# sets KEY. Deliberately parses rather than sources: these files only ever
# hold scalar knobs, and sourcing them into this script would let a stray
# line clobber CEILING/QUIET/TOKEN.
CONF_VAL=""; CONF_SRC=""
conf_lookup() {
  local key="$1" f line v
  CONF_VAL=""; CONF_SRC=""
  for f in ${CONF_FILES+"${CONF_FILES[@]}"}; do
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key[[:space:]]*=" "$f" 2>/dev/null | tail -n1)"
    [ -n "$line" ] || continue
    v="${line#*=}"
    v="${v%%#*}"                              # strip trailing comment
    v="${v#"${v%%[![:space:]]*}"}"            # ltrim
    v="${v%"${v##*[![:space:]]}"}"            # rtrim
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    [ -n "$v" ] || continue
    CONF_VAL="$v"; CONF_SRC="$(basename "$f")"
  done
}

# resolve_knob <KEY> <default> -- env > host conf > base conf > default.
RES_VAL=""; RES_SRC=""
resolve_knob() {
  local key="$1" def="$2"
  if [ -n "${!key:-}" ]; then RES_VAL="${!key}"; RES_SRC="env"; return; fi
  conf_lookup "$key"
  if [ -n "$CONF_VAL" ]; then RES_VAL="$CONF_VAL"; RES_SRC="$CONF_SRC"; return; fi
  RES_VAL="$def"; RES_SRC="default"
}

# require_num <KEY> <lo> <hi> -- validate RES_VAL, or ERROR naming the source.
require_num() {
  awk -v v="$RES_VAL" -v lo="$2" -v hi="$3" \
    'BEGIN{ if (v ~ /^[0-9]+(\.[0-9]+)?$/ && v+0 >= lo && v+0 <= hi) exit 0; exit 1 }' \
    || emit_error "invalid_$1=$RES_VAL(from:$RES_SRC,expected:${2}-${3})"
}

resolve_knob USAGE_CEILING 0.85
require_num USAGE_CEILING 0 1
CEILING="$RES_VAL"; CEILING_SRC="$RES_SRC"

resolve_knob USAGE_MIN_SLACK 0.02
require_num USAGE_MIN_SLACK 0 1
MIN_SLACK="$RES_VAL"; MIN_SLACK_SRC="$RES_SRC"

resolve_knob USAGE_RUSH_BEFORE_RESET_MIN 120
require_num USAGE_RUSH_BEFORE_RESET_MIN 0 10080
RUSH_MIN="$RES_VAL"; RUSH_MIN_SRC="$RES_SRC"

resolve_knob USAGE_PROBE_MODEL claude-haiku-4-5-20251001
MODEL="$RES_VAL"

command -v curl >/dev/null 2>&1 || emit_error no_curl
command -v python3 >/dev/null 2>&1 || emit_error no_python

TOKEN=$(python3 -c "import json;print(json.load(open('$CREDS'))['claudeAiOauth']['accessToken'])" 2>/dev/null) || emit_error no_token
[ -n "$TOKEN" ] || emit_error empty_token

HDR="$(mktemp)"; trap 'rm -f "$HDR"' EXIT
CODE=$(curl -sS -o /dev/null -D "$HDR" -w '%{http_code}' --max-time 30 \
  https://api.anthropic.com/v1/messages \
  -H "authorization: Bearer $TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "content-type: application/json" \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":1,\"system\":\"You are Claude Code, Anthropic's official CLI for Claude.\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" 2>/dev/null) \
  || emit_error curl_failed

# Decision core in python: parse headers, compute burn-lines, pick verdict.
# USAGE_RUSH_BEFORE_RESET_MIN is passed EXPLICITLY: python reads it from its
# own environment, so before conf support it only ever arrived when a caller
# had exported it -- a conf/shell-var value would have been silently ignored.
CEILING="$CEILING" MIN_SLACK="$MIN_SLACK" HTTP_CODE="$CODE" QUIET="$QUIET" \
USAGE_RUSH_BEFORE_RESET_MIN="$RUSH_MIN" \
KNOB_SRC="ceiling:$CEILING_SRC,min_slack:$MIN_SLACK_SRC,rush_min:$RUSH_MIN_SRC" \
python3 - "$HDR" <<'PY'
import os, re, sys, time

hdr_path = sys.argv[1]
ceiling  = float(os.environ["CEILING"])
min_slack= float(os.environ["MIN_SLACK"])
quiet    = os.environ.get("QUIET") == "1"
code     = os.environ.get("HTTP_CODE", "?")
now      = time.time()

vals = {}
pat = re.compile(r"^anthropic-ratelimit-unified-([\w-]+):\s*(.*?)\s*$", re.I)
for line in open(hdr_path, "r", errors="replace"):
    m = pat.match(line)
    if m:
        vals[m.group(1).lower()] = m.group(2).strip()

WINDOWS = (("5h", 5*3600), ("7d", 7*86400))
def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None

if not any(("%s-utilization" % w) in vals for w, _ in WINDOWS):
    print("ERROR" if quiet else f"verdict=ERROR reason=no_headers http_code={code}")
    sys.exit(2)

# Rush-before-reset (human policy, 2026-07-20): unused WEEKLY quota is lost
# at the 7d reset, it doesn't roll over -- so preserving even-burn slack in
# the final stretch before that reset is pure waste, not caution. Once the
# 7d window is within RUSH_MIN of its own reset, drop "on-pace" as a hold
# reason on BOTH windows (still respect "ceiling"/"rejected" -- those are
# real API limits, not pacing preference) and just run flat-out until one
# of those actually blocks. This deliberately accepts hitting the 5h
# ceiling early ("the session maxes out") -- that window refreches on its
# own on a matter of hours regardless, unlike the 7-day budget this is
# trying not to leave on the table.
RUSH_MIN = float(os.environ.get("USAGE_RUSH_BEFORE_RESET_MIN", "120"))
reset_7d = num(vals.get("7d-reset"))
rush = reset_7d is not None and (reset_7d - now) / 60.0 <= RUSH_MIN

rows, block = [], []
for w, length in WINDOWS:
    util   = num(vals.get(f"{w}-utilization"))
    reset  = num(vals.get(f"{w}-reset"))
    status = vals.get(f"{w}-status", "")
    if util is None or reset is None:
        continue
    # even-burn target = fraction of the window elapsed by now
    target = 1.0 - (reset - now) / length
    target = max(0.0, min(1.0, target))
    slack  = target - util               # >0 => behind pace => room to run
    reasons = []
    if status.lower() == "rejected":       reasons.append("rejected")
    if util >= ceiling:                    reasons.append("ceiling")
    if slack < min_slack and not rush:     reasons.append("on-pace")
    if reasons: block.append((w, reasons))
    rows.append((w, util, target, slack, reset, status))

# tightest = least slack; that's the binding window
rows.sort(key=lambda r: r[3])
binding = rows[0][0] if rows else vals.get("representative-claim", "?")
run = (len(block) == 0) and (len(rows) > 0)
verdict = "RUN" if run else "HOLD"

if quiet:
    print(verdict); sys.exit(0 if run else 1)

print(f"verdict={verdict} binding={binding} ceiling={ceiling} min_slack={min_slack} "
      f"http_code={code} rush={rush} knobs={os.environ.get('KNOB_SRC','?')}")
for w, util, target, slack, reset, status in rows:
    mins = int((reset - now) / 60)
    print(f"window={w} util={util:.3f} burnline={target:.3f} slack={slack:+.3f} "
          f"status={status} resets_in_min={mins}")
if block:
    print("hold_reasons=" + ";".join(f"{w}:{'/'.join(rs)}" for w, rs in block))
# one-line human summary
top = rows[0]
if run:
    print(f"# RUN -- slack available (tightest {top[0]} at {top[1]*100:.0f}% vs "
          f"burn-line {top[2]*100:.0f}%, {top[3]*100:+.0f}pts)")
else:
    print(f"# HOLD -- {binding} window {top[1]*100:.0f}% used vs burn-line "
          f"{top[2]*100:.0f}% ({', '.join(r for _,rs in block for r in rs)})")
sys.exit(0 if run else 1)
PY
