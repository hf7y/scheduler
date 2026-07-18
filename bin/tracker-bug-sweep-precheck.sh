#!/usr/bin/env bash
# Reusable PRECHECK_CMD gate for any Tier-1 bug-sweep wrapper on the shared
# engine (lib/sweep-loop-common.sh). Wire it in per project:
#
#   PRECHECK_CMD="<this-script> <TRACKER_URL> <SIG_FILE> [QUERY]"
#
# The engine skips the `claude -p` invocation entirely (zero model cost)
# whenever this exits non-zero.
#
# THE INSIGHT (why this exists, repeatable across projects):
#   A Tier-1 sweep fires every 15 min, but the tracked report set changes
#   rarely. Measured on chezz 2026-07-17: 76 runs, exactly ONE produced a
#   fix; 57 found "0 new" yet each still spun up a full claude invocation
#   (~105 min of model time that day, ~99% of it wasted). This gate turns
#   every quiet cycle into a single curl -- claude runs ONLY when the open
#   report set actually changed since the last run that acted on it. Pair
#   it with the engine's MODEL knob (run the mechanical sweep on a cheaper
#   model): precheck cuts HOW OFTEN claude runs, MODEL cuts what each run
#   costs.
#
# Args:
#   $1 TRACKER_URL  Apps Script /exec base (required)
#   $2 SIG_FILE     where to persist the last-seen signature (required;
#                   conventionally $STATE_DIR/last_open_reports.sig, i.e.
#                   ~/.local/share/<JOB_NAME>/last_open_reports.sig)
#   $3 QUERY        the read query that defines "the set this sweep acts
#                   on" -- default "scope=bugs&status=open&type=bug".
#                   Pass type=all for a sweep that also triages features
#                   (e.g. vkv-inventory). Quote it in PRECHECK_CMD so the
#                   '&' survives eval.
#
# Fails SAFE: any fetch/parse problem falls through to a real run rather
# than silently going dark.
#
# Optional heartbeat (OFF by default): set env PRECHECK_HEARTBEAT=1 to also
# POST a sweep-status ping each cycle, so a project whose page shows "last
# swept ..." stays fresh even on skipped runs. ONLY enable this for a
# tracker that special-cases {type:"sweep-status"} server-side (chezz's
# Code.gs does). vkv-inventory's tracker does NOT -- it recorded such POSTs
# as phantom "anonymous" bug rows -- so leave it off there. When in doubt,
# leave it off: the gate itself never writes anything.
set -uo pipefail

URL="${1:?precheck: TRACKER_URL (arg 1) required}"
SIG_FILE="${2:?precheck: SIG_FILE (arg 2) required}"
QUERY="${3:-scope=bugs&status=open&type=bug}"
mkdir -p "$(dirname "$SIG_FILE")"

reports="$(curl -sL --max-time 30 "$URL?$QUERY&limit=200" 2>/dev/null)"

# Fetch failed or isn't a JSON array -> don't skip; let the real run decide.
if [ -z "$reports" ] || [ "${reports:0:1}" != "[" ]; then
  echo "precheck: tracker fetch failed/unparseable -- not skipping (running claude)"
  exit 0
fi

# Signature = "<count>:<sha1 of sorted report timestamps>". Changes when a
# report is filed OR resolved anywhere in the queried set; stable otherwise.
sig="$(printf '%s' "$reports" | python3 -c '
import json,sys,hashlib
d=json.load(sys.stdin)
ts=sorted(str(x.get("timestamp","")) for x in d)
print(f"{len(ts)}:"+hashlib.sha1("|".join(ts).encode()).hexdigest())
' 2>/dev/null)"
count="${sig%%:*}"

# Optional heartbeat -- only when explicitly enabled AND the tracker is
# known to special-case sweep-status (see header). A real claude run
# re-posts its own accurate counts afterward.
if [ "${PRECHECK_HEARTBEAT:-0}" = "1" ]; then
  curl -sL --max-time 30 "$URL" -X POST -H "Content-Type: text/plain" \
    --data-raw "{\"type\":\"sweep-status\",\"fetched\":${count:-0},\"fixed\":0,\"reclassified\":0,\"leftOpen\":${count:-0}}" \
    >/dev/null 2>&1 || true
fi

# Empty sig (python missing/failed) -> fail safe, run claude.
if [ -z "$sig" ]; then
  echo "precheck: could not compute signature -- not skipping (running claude)"
  exit 0
fi

prev="$(cat "$SIG_FILE" 2>/dev/null || echo "")"
if [ "$sig" = "$prev" ]; then
  echo "precheck: open-report set unchanged ($count open, query='$QUERY') -- skipping claude this run"
  exit 1
fi

printf '%s' "$sig" > "$SIG_FILE"
echo "precheck: open-report set changed (was '${prev:-none}', now '$sig') -- running claude"
exit 0
