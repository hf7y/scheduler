#!/usr/bin/env bash
# token-usage.sh -- REAL token/quota burn per project + total, read straight
# out of Claude Code's own session transcripts (~/.claude/projects/*.jsonl).
# Unlike scheduler's glance ETA column (a wall-clock-gap projection), this is
# not an estimate: every assistant turn logs its own input/output/cache
# token counts, and this just sums them. Repeatable -- rerun any time for a
# fresh snapshot; each run also appends one line per project to a history
# file so the NEXT run can report a real tokens/hour rate since last time,
# not just a cumulative total.
#
# Usage: bin/token-usage.sh [--days N] [--no-quota] [--no-snapshot]
#   --days N        only sum transcript turns from the last N days
#                    (default: all-time cumulative)
#   --no-quota      skip the live usage-gate.sh probe at the bottom (that
#                    one step needs network + a valid OAuth token; the token
#                    totals above it are pure local file reads)
#   --no-snapshot   don't append to the history file / don't print a
#                    since-last-run rate (useful for a one-off --days query)
#
# What "per project" means: every registered project (schedule/*.conf) is
# mapped to every ~/.claude session directory that's actually it --
#   - its main working copy (PROJECT_REPO_PATH)
#   - every $HOME/.local/share/<name>/{repo,worktree} state dir whose
#     <name> is exactly the project or starts with "<project>-" (covers
#     every tier's disposable clone/worktree -- nightly-batch, bug-sweep,
#     and the scheduler's own extra self-jobs like scheduler-paced-dev --
#     without hardcoding job names project by project)
# summed across ALL .jsonl transcripts found there. This counts whatever
# actually happened in that directory -- an autonomous batch run or you
# working in it interactively -- both are real spend against your quota,
# so both count; the columns don't try to separate them.
#
# History file: $HOME/.local/share/scheduler-token-usage/history.tsv
# (timestamp, project, cumulative input/output/cache_create/cache_read
# tokens, turn count, session count -- one row per project per run).
set -uo pipefail

SCHED_ROOT="/home/zach/Documents/Project Archive/scheduler"
CLAUDE_PROJECTS="$HOME/.claude/projects"
HIST_DIR="$HOME/.local/share/scheduler-token-usage"
HIST_FILE="$HIST_DIR/history.tsv"
USAGE_GATE="$SCHED_ROOT/bin/usage-gate.sh"

DAYS=""
DO_QUOTA=1
DO_SNAPSHOT=1
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:?--days needs a number}"; shift 2 ;;
    --no-quota) DO_QUOTA=0; shift ;;
    --no-snapshot) DO_SNAPSHOT=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#!\?//; s/^ //'; exit 0 ;;
    *) echo "token-usage.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

mkdir -p "$HIST_DIR"

encode_path() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }

projects_list="$(for conf in "$SCHED_ROOT"/schedule/*.conf; do
  b="$(basename "$conf" .conf)"; [[ "$b" == _* ]] && continue; echo "$b"
done)"

pairs_file="$(mktemp)"; trap 'rm -f "$pairs_file"' EXIT

# main working copy, per project
for conf in "$SCHED_ROOT"/schedule/*.conf; do
  b="$(basename "$conf" .conf)"
  [[ "$b" == _* ]] && continue
  repo_path="$(awk -F'"' '/^PROJECT_REPO_PATH=/{print $2; exit}' "$conf")"
  if [ -n "$repo_path" ] && [ -d "$CLAUDE_PROJECTS/$(encode_path "$repo_path")" ]; then
    printf '%s\t%s\n' "$b" "$CLAUDE_PROJECTS/$(encode_path "$repo_path")" >> "$pairs_file"
  fi
done

# every disposable-clone/worktree state dir whose name is "<project>" or
# starts with "<project>-" -- longest match wins so e.g. a hypothetical
# "foo" and "foo-bar" project can't both silently claim "foo-bar-nightly".
for statedir in "$HOME/.local/share"/*/; do
  name="$(basename "$statedir")"
  best=""
  while IFS= read -r p; do
    if [ "$name" = "$p" ] || [[ "$name" == "$p"-* ]]; then
      [ "${#p}" -gt "${#best}" ] && best="$p"
    fi
  done <<< "$projects_list"
  [ -n "$best" ] || continue
  for sub in repo worktree; do
    d="${statedir}${sub}"
    [ -d "$d" ] || continue
    enc="$(encode_path "$d")"
    [ -d "$CLAUDE_PROJECTS/$enc" ] && printf '%s\t%s\n' "$best" "$CLAUDE_PROJECTS/$enc" >> "$pairs_file"
  done
done

sort -u -o "$pairs_file" "$pairs_file"

if [ ! -s "$pairs_file" ]; then
  echo "token-usage.sh: found no matching ~/.claude/projects/* session dirs -- nothing to report" >&2
  exit 1
fi

NOW_ISO="$(date -Is)"
DAYS="$DAYS" NOW_ISO="$NOW_ISO" HIST_FILE="$HIST_FILE" DO_SNAPSHOT="$DO_SNAPSHOT" \
python3 - "$pairs_file" <<'PY'
import json, os, sys, glob, time
from datetime import datetime, timezone

pairs_path = sys.argv[1]
days = os.environ.get("DAYS", "")
now_iso = os.environ["NOW_ISO"]
hist_file = os.environ["HIST_FILE"]
do_snapshot = os.environ.get("DO_SNAPSHOT", "1") == "1"

def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None

now_dt = parse_ts(now_iso) or datetime.now(timezone.utc)
cutoff = None
if days:
    cutoff = now_dt.timestamp() - float(days) * 86400

# project -> set of dirs
proj_dirs = {}
with open(pairs_path) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        proj, d = line.split("\t", 1)
        proj_dirs.setdefault(proj, set()).add(d)

FIELDS = ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")

results = {}
for proj, dirs in proj_dirs.items():
    tot = {k: 0 for k in FIELDS}
    turns = 0
    sessions = set()
    last_seen = None
    for d in dirs:
        for jf in glob.glob(os.path.join(d, "*.jsonl")):
            try:
                fh = open(jf, "r", errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if rec.get("type") != "assistant":
                        continue
                    ts = parse_ts(rec.get("timestamp", "")) if rec.get("timestamp") else None
                    if cutoff is not None:
                        if ts is None or ts.timestamp() < cutoff:
                            continue
                    usage = (rec.get("message") or {}).get("usage")
                    if not usage:
                        continue
                    sessions.add(jf)
                    for k in FIELDS:
                        tot[k] += int(usage.get(k) or 0)
                    turns += 1
                    if ts is not None and (last_seen is None or ts > last_seen):
                        last_seen = ts
    tot["total"] = sum(tot[k] for k in FIELDS)
    results[proj] = dict(tot=tot, turns=turns, sessions=len(sessions), last_seen=last_seen)

# ---- history: read prior snapshot per project (most recent row before now) ----
prior = {}
if os.path.exists(hist_file):
    with open(hist_file) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 8:
                continue
            ts, proj, inp, outp, cc, cr, turns_h, sessions_h = parts
            tsdt = parse_ts(ts)
            if tsdt is None:
                continue
            row = dict(ts=tsdt, total=int(inp) + int(outp) + int(cc) + int(cr))
            if proj not in prior or tsdt > prior[proj]["ts"]:
                prior[proj] = row

def fmt(n):
    return f"{n:,}"

def fmt_dur_hours(hrs):
    if hrs < 1:
        return f"{hrs*60:.0f}m"
    if hrs < 48:
        return f"{hrs:.1f}h"
    return f"{hrs/24:.1f}d"

label = f"last {days} day(s)" if days else "all-time"
print(f"token-usage.sh -- {label}, as of {now_iso}")
print()
hdr = f"  {'PROJECT':<16} {'TURNS':>7} {'SESS':>5} {'TOTAL TOKENS':>14} {'SINCE LAST RUN':>16} {'RATE':>12}  LAST ACTIVITY"
print(hdr)

grand_total = 0
grand_turns = 0
grand_sessions = 0
grand_since = 0
any_prior = False
new_rows = []

for proj in sorted(results, key=lambda p: -results[p]["tot"]["total"]):
    r = results[proj]
    t = r["tot"]
    grand_total += t["total"]
    grand_turns += r["turns"]
    grand_sessions += r["sessions"]
    since_label = "-"
    rate_label = "-"
    if proj in prior:
        any_prior = True
        delta_tok = t["total"] - prior[proj]["total"]
        delta_hrs = max((now_dt - prior[proj]["ts"]).total_seconds() / 3600.0, 1e-9)
        grand_since += delta_tok
        since_label = fmt(delta_tok)
        rate_label = f"{fmt(round(delta_tok/delta_hrs))}/hr"
    else:
        since_label = "no prior snapshot"
    last_seen = r["last_seen"].strftime("%Y-%m-%d %H:%M") if r["last_seen"] else "-"
    print(f"  {proj:<16} {r['turns']:>7} {r['sessions']:>5} {fmt(t['total']):>14} {since_label:>16} {rate_label:>12}  {last_seen}")
    new_rows.append((proj, t))

print(f"  {'-'*16} {'-'*7} {'-'*5} {'-'*14} {'-'*16} {'-'*12}")
print(f"  {'TOTAL':<16} {grand_turns:>7} {grand_sessions:>5} {fmt(grand_total):>14} {fmt(grand_since) if any_prior else '-':>16}")
print()
print("Columns: TURNS/SESS/TOTAL TOKENS = counted from local transcripts (real,")
print("not estimated); input+output+cache-create+cache-read summed together.")
print("SINCE LAST RUN/RATE need a prior snapshot from this same script -- run it")
print("again later for those to fill in.")

if do_snapshot:
    with open(hist_file, "a") as f:
        for proj, t in new_rows:
            r = results[proj]
            f.write("\t".join([
                now_iso, proj,
                str(t["input_tokens"]), str(t["output_tokens"]),
                str(t["cache_creation_input_tokens"]), str(t["cache_read_input_tokens"]),
                str(r["turns"]), str(r["sessions"]),
            ]) + "\n")
PY

if [ "$DO_QUOTA" = "1" ] && [ -x "$USAGE_GATE" ]; then
  echo
  echo "-- live account-wide quota (usage-gate.sh probe) --"
  "$USAGE_GATE" 2>/dev/null || echo "(probe failed or not logged in -- token totals above are unaffected, they're pure local file reads)"
fi
