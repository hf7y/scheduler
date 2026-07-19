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
# Env knobs:
#   USAGE_CEILING     (0.85)  never run above this utilisation on any window
#   USAGE_MIN_SLACK   (0.02)  require this much room below the burn-line to run
#   USAGE_PROBE_MODEL (claude-haiku-4-5-20251001)
#   USAGE_GATE_QUIET  (0)     1 = print only "RUN"/"HOLD"/"ERROR"
set -uo pipefail

CEILING="${USAGE_CEILING:-0.85}"
MIN_SLACK="${USAGE_MIN_SLACK:-0.02}"
MODEL="${USAGE_PROBE_MODEL:-claude-haiku-4-5-20251001}"
QUIET="${USAGE_GATE_QUIET:-0}"
CREDS="$HOME/.claude/.credentials.json"

emit_error() { [ "$QUIET" = "1" ] && echo "ERROR" || echo "verdict=ERROR reason=$1"; exit 2; }

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
CEILING="$CEILING" MIN_SLACK="$MIN_SLACK" HTTP_CODE="$CODE" QUIET="$QUIET" \
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
    if slack < min_slack:                  reasons.append("on-pace")
    if reasons: block.append((w, reasons))
    rows.append((w, util, target, slack, reset, status))

# tightest = least slack; that's the binding window
rows.sort(key=lambda r: r[3])
binding = rows[0][0] if rows else vals.get("representative-claim", "?")
run = (len(block) == 0) and (len(rows) > 0)
verdict = "RUN" if run else "HOLD"

if quiet:
    print(verdict); sys.exit(0 if run else 1)

print(f"verdict={verdict} binding={binding} ceiling={ceiling} min_slack={min_slack} http_code={code}")
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
