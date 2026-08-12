#!/usr/bin/env bash
# usage-gate.sh -- the pacing brain's sensor + decision.
#
# Reads your LIVE, account-wide usage from Anthropic's own usage endpoint and
# decides whether background jobs may run right now, so autonomous work fills
# the quota you're leaving on the table without pushing you toward the cap.
# Model: drive each window's utilisation along a straight "even-burn" line
# from the window start to 100% at its reset; RUN when actual util is BELOW
# that line (slack going to waste), HOLD when at/over it (you're already on
# pace to spend it) or above a safety ceiling.
#
# Signal (2026-08-11, TOKEN-FREE as of this change -- see "WHY THE PROBE
# CHANGED" below): a plain authenticated GET to
#   https://api.anthropic.com/api/oauth/usage
# returns `five_hour`/`seven_day` objects (`utilization` 0-100, `resets_at`
# ISO8601) plus a `limits[]` breakdown with a `severity` per window (matched
# by `kind`: "session" = 5h, "weekly_all" = 7d). Same OAuth bearer token the
# gate already resolves below, reused for a read instead of a spend. These
# are ACCOUNT-WIDE (web, Slack, every machine, jobs), so jobs pace against
# YOUR own usage too -- exactly the requirement. Anthropic enforces a rolling
# 5-hour AND a 7-day window; we honour BOTH and defer to the tighter.
#
# WHY THE PROBE CHANGED: the previous signal was a real `POST /v1/messages`
# call (model=$USAGE_PROBE_MODEL, max_tokens=1, "~23 tokens") whose only
# purpose was reading the `anthropic-ratelimit-unified-*` response headers --
# it spent real quota, from the SAME weekly budget it exists to protect, on
# every gate check (4-24+ times/day across hosts under the paced-runner
# schedule). senechal's claudequota plasmoid already reads this exact
# five_hour/seven_day shape from /api/oauth/usage with zero token cost (see
# hf7y/senechal remedies/claudequota-*.sh and contents/scripts/claude-quota-json)
# -- this change ports that endpoint here so the gate stops taxing the thing
# it measures. `schedule/_runner.mandark.conf`'s own retirement note already
# names this cost explicitly ("still called usage-gate.sh, spending a quota
# probe against the SHARED weekly budget for work it could not do") --  this
# change removes the spend itself rather than working around it by disabling
# hosts.
#
# DRAFT / NOT YET LIVE-VERIFIED (2026-08-11) -- read before merging. What IS
# confirmed: the endpoint, auth (same bearer token), and the utilization/
# resets_at shape -- all checked with a live `curl` against this account
# during the senechal session that found this bug (48%/54% five_hour, 27%/28%
# seven_day, matching the widget). What is NOT yet confirmed:
#   1. The `severity` field's full vocabulary. Only "normal" has been
#      observed live. The old header-based `status` had a documented
#      "rejected" value that hard-blocked; this account has never actually
#      been rejected during testing, so there is no live example of what
#      `limits[].severity` says when it would. The block condition below
#      (`severity not in ("normal", "warning")`) is a conservative GUESS,
#      not a verified port -- confirm against Anthropic's docs for this field
#      (linked from the `spend.disclaimer` URL in the response body) or by
#      finding a session that actually got throttled, before trusting it to
#      gate real dispatch.
#   2. Behaviour under the live paced-runner loop across hosts (dexter,
#      monkey) -- only run ad hoc from a shell so far, not through
#      bin/usage-paced-runner.sh or a real cron tick.
#   3. tests/usage-gate-token-witness.sh still targets the token-resolution
#      code, which is untouched, so it should still pass -- but there is no
#      behavioural test for the probe/parse itself (the same gap the token
#      witness's own header names: "would need to stand up a fake
#      api.anthropic.com"). Consider adding one against a canned JSON body
#      before merging.
# Opened as a DRAFT PR for exactly this reason -- the token-cost bug and the
# fix's shape are both solid, but a later pass should close 1-3 before this
# starts gating real dispatch.
#
# Output: key=val lines + a human summary. Exit code is the verdict:
#   0 = RUN   (every window below its burn-line by >= MIN_SLACK, below CEILING)
#   1 = HOLD  (on/over pace, at ceiling, or a window's severity looks blocking)
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
LEGACY_SCHED_DIR="/home/zach/Documents/Projects/scheduler/schedule"
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

# THREE PLACES A TOKEN CAN LIVE, and until 2026-08-03 this read only one of
# them -- the one that does NOT work on an unattended host.
#
#   1. $CLAUDE_CODE_OAUTH_TOKEN        exported in the environment
#   2. ~/.claude/settings.json .env    written from `claude setup-token`
#   3. ~/.claude/.credentials.json     the interactive OAuth login
#
# (3) was the only one supported, and it is the login that EXPIRES and that a
# headless host cannot perform. `monkey` -- the self-dev host stood up this
# date, one unix user per project, no browser -- authenticates with a
# long-lived setup-token in (2), because that is the only shape `claude`
# itself reads with no session bus and no env inherited through cron.
#
# So the gate held every dispatch at `verdict=ERROR reason=no_token` on a host
# where `claude -p` worked perfectly. The ecosystem's unattended-auth story
# and its quota gate disagreed about where a credential lives, and the gate
# was the half that got to decide. Same class as conf_field reading a conf
# two ways: one fact, two readers.
#
# Order is deliberate: an explicitly exported token wins, because a caller
# that set it meant it.
TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}"
TOKEN_SRC="env"
if [ -z "$TOKEN" ]; then
  SETTINGS="$HOME/.claude/settings.json"
  TOKEN=$(python3 -c "import json,sys;print(json.load(open('$SETTINGS')).get('env',{}).get('CLAUDE_CODE_OAUTH_TOKEN',''))" 2>/dev/null) || TOKEN=""
  TOKEN_SRC="settings.json"
fi
if [ -z "$TOKEN" ]; then
  TOKEN=$(python3 -c "import json;print(json.load(open('$CREDS'))['claudeAiOauth']['accessToken'])" 2>/dev/null) || TOKEN=""
  TOKEN_SRC="credentials.json"
fi
# no_token still means "found nowhere", which is what the old reason meant --
# callers and logs that match on it keep working.
[ -n "$TOKEN" ] || emit_error no_token

# TOKEN-FREE PROBE (2026-08-11): a plain GET, no model, no spend -- see the
# header comment's "WHY THE PROBE CHANGED". $MODEL/$USAGE_PROBE_MODEL is
# resolved above for backward compatibility (a conf/env setting it should not
# start erroring) but is no longer used for anything; keeping the knob alive
# is cheap, deleting it isn't free for anyone who set it. Body captured to a
# tempfile rather than a variable so a huge/garbled response can't blow up
# `$()` command substitution the way the old header-only capture never risked.
BODY_FILE="$(mktemp)"; trap 'rm -f "$BODY_FILE"' EXIT
CODE=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' --max-time 15 \
  https://api.anthropic.com/api/oauth/usage \
  -H "authorization: Bearer $TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "accept: application/json" 2>/dev/null) \
  || emit_error curl_failed

# ###########################################################################
# FALL BACK TO THE PAID PROBE WHEN THE FREE ONE IS REFUSED
# ###########################################################################
#
# /api/oauth/usage answers for an INTERACTIVE OAuth credential and 403s for a
# `claude setup-token` token. Those are different credential types and the
# estate holds both:
#
#   mandark      ~/.claude/.credentials.json   interactive   -> 200
#   monkey/*     settings.json CLAUDE_CODE_OAUTH_TOKEN       -> 403
#
# hf7y/scheduler#110 swapped the paid POST /v1/messages probe for this GET on
# the strength of a live check that was real but ran on mandark only
# (senechal/.scheduler/FOCUS.md, 2026-08-04). Merged 2026-08-11T22:56Z; the
# five armed accounts pulled main, every gate returned
# `verdict=ERROR reason=no_usage_fields http_code=403`, ERROR is treated as
# HOLD by design, and ALL SELF-DEV DISPATCH STOPPED at the 00:00 tick with
# nothing saying why. Verified with one token against both endpoints:
# v1/messages 200, api/oauth/usage 403.
#
# So the free probe is right where it works and wrong as the only path. On a
# 401/403 -- the credential-shaped refusals, not a network fault -- fall back
# to the ~23-token Haiku probe that has always worked. Cost is unchanged on
# every host that can use the free endpoint, and dispatch survives on the ones
# that cannot.
#
# NOT a silent fallback: the reason is carried into the verdict line so a
# reader can see which probe answered and stop wondering why one host spends
# tokens and another does not.
PROBE_VIA=oauth-usage
case "$CODE" in
  401|403)
    PROBE_VIA="v1-messages-fallback(${CODE})"
    CODE=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' --max-time 15 \
      -X POST https://api.anthropic.com/v1/messages \
      -H "authorization: Bearer $TOKEN" \
      -H "anthropic-version: 2023-06-01" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "content-type: application/json" \
      -d "{\"model\":\"$USAGE_PROBE_MODEL\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
      -D "$BODY_FILE.hdr" 2>/dev/null) || emit_error curl_failed_fallback
    # The paid probe reports usage in HEADERS, not the body. Rewrite the body
    # into the same five_hour/seven_day shape the parser below already reads,
    # so the fallback changes where the numbers come FROM and nothing else.
    python3 - "$BODY_FILE.hdr" "$BODY_FILE" <<'HDR'
import re, sys, json
hdr, out = sys.argv[1], sys.argv[2]
try:
    text = open(hdr, errors="replace").read()
except OSError:
    text = ""
def g(name):
    m = re.search(r'^%s:\s*(.+?)\s*$' % re.escape(name), text, re.I | re.M)
    return m.group(1) if m else None
def pct(v):
    try: return float(v) * (100.0 if float(v) <= 1.0 else 1.0)
    except (TypeError, ValueError): return None
five = pct(g("anthropic-ratelimit-unified-5h-utilization"))
seven = pct(g("anthropic-ratelimit-unified-7d-utilization"))
doc = {}
if five is not None:
    doc["five_hour"] = {"utilization": five, "resets_at": g("anthropic-ratelimit-unified-5h-reset")}
if seven is not None:
    doc["seven_day"] = {"utilization": seven, "resets_at": g("anthropic-ratelimit-unified-7d-reset")}
open(out, "w").write(json.dumps(doc))
HDR
    rm -f "$BODY_FILE.hdr"
    ;;
esac

# Decision core in python: parse the usage body, compute burn-lines, pick
# verdict. USAGE_RUSH_BEFORE_RESET_MIN is passed EXPLICITLY: python reads it
# from its own environment, so before conf support it only ever arrived when
# a caller had exported it -- a conf/shell-var value would have been silently
# ignored.
CEILING="$CEILING" MIN_SLACK="$MIN_SLACK" HTTP_CODE="$CODE" QUIET="$QUIET" \
USAGE_RUSH_BEFORE_RESET_MIN="$RUSH_MIN" \
KNOB_SRC="ceiling:$CEILING_SRC,min_slack:$MIN_SLACK_SRC,rush_min:$RUSH_MIN_SRC,probe:$PROBE_VIA" \
python3 - "$BODY_FILE" <<'PY'
import json, os, sys, time
from datetime import datetime

body_path = sys.argv[1]
ceiling  = float(os.environ["CEILING"])
min_slack= float(os.environ["MIN_SLACK"])
quiet    = os.environ.get("QUIET") == "1"
code     = os.environ.get("HTTP_CODE", "?")
now      = time.time()

def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None

def parse_iso(s):  # "2026-08-11T20:00:00.734421+00:00" -> epoch seconds
    if not s: return None
    try: return datetime.fromisoformat(s).timestamp()
    except (TypeError, ValueError): return None

try:
    j = json.load(open(body_path, "r", errors="replace"))
except (json.JSONDecodeError, OSError):
    j = None

# WINDOWS: (label, json key for the util/reset pair, `limits[].kind` for its
# severity entry, window length in seconds).
WINDOWS = (("5h", "five_hour", "session", 5*3600), ("7d", "seven_day", "weekly_all", 7*86400))

if not isinstance(j, dict) or not any(k in j for _, k, _, _ in WINDOWS):
    print("ERROR" if quiet else f"verdict=ERROR reason=no_usage_fields http_code={code}")
    sys.exit(2)

limits_by_kind = {
    e["kind"]: e for e in (j.get("limits") or []) if isinstance(e, dict) and e.get("kind")
}

# Rush-before-reset (human policy, 2026-07-20): unused WEEKLY quota is lost
# at the 7d reset, it doesn't roll over -- so preserving even-burn slack in
# the final stretch before that reset is pure waste, not caution. Once the
# 7d window is within RUSH_MIN of its own reset, drop "on-pace" as a hold
# reason on BOTH windows (still respect "ceiling"/a blocking severity --
# those are real API limits, not pacing preference) and just run flat-out
# until one of those actually blocks. This deliberately accepts hitting the
# 5h ceiling early ("the session maxes out") -- that window refreches on its
# own on a matter of hours regardless, unlike the 7-day budget this is
# trying not to leave on the table.
RUSH_MIN = float(os.environ.get("USAGE_RUSH_BEFORE_RESET_MIN", "120"))
reset_7d = parse_iso((j.get("seven_day") or {}).get("resets_at"))
rush = reset_7d is not None and (reset_7d - now) / 60.0 <= RUSH_MIN

rows, block = [], []
for w, jkey, limkey, length in WINDOWS:
    win = j.get(jkey) or {}
    util_pct = num(win.get("utilization"))
    reset = parse_iso(win.get("resets_at"))
    if util_pct is None or reset is None:
        continue
    util = util_pct / 100.0
    # DRAFT/UNVERIFIED (see this script's header, "DRAFT / NOT YET
    # LIVE-VERIFIED" item 1): only "normal" has been observed live for this
    # field. Treating anything else as blocking is the conservative guess
    # standing in for the old header `status == "rejected"` check.
    severity = ((limits_by_kind.get(limkey) or {}).get("severity") or "normal").lower()
    # even-burn target = fraction of the window elapsed by now
    target = 1.0 - (reset - now) / length
    target = max(0.0, min(1.0, target))
    slack  = target - util               # >0 => behind pace => room to run
    reasons = []
    if severity not in ("normal", "warning"): reasons.append(f"severity:{severity}")
    if util >= ceiling:                       reasons.append("ceiling")
    if slack < min_slack and not rush:        reasons.append("on-pace")
    if reasons: block.append((w, reasons))
    rows.append((w, util, target, slack, reset, severity))

# tightest = least slack; that's the binding window
rows.sort(key=lambda r: r[3])
binding = rows[0][0] if rows else "?"
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
