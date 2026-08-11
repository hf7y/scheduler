#!/usr/bin/env bash
# blockers-liveness-check.sh -- offline-first liveness audit for scheduled projects
# (every enabled project must have a report younger than STALE_HOURS or dispatch
# infrastructure is silently orphaned).
#
# Catches the class of failure the aedile/vkv-inventory 2026-07-25 silent
# orphaning exhibited: a project disabled with an unverified "migrated"
# claim sat zero-dispatch for 4 days undetected. This script catches the
# mechanical half: "when did this project last report back?" every morning
# glance shouts if the answer is "I don't know, it never filed one" or "not
# for more than 2 days."
#
# Zero AI cost, same offline-first discipline as blockers-freshness-check.sh.
# Findings are SIGNALS, not verdicts -- a human (or an /ideate pass) decides
# whether it's truly stale or expected quiet.

set -uo pipefail

SCHED_ROOT="${SCHED_ROOT:-/home/zach/Documents/Project Archive/scheduler}"
REPORTS_ROOT="${REPORTS_ROOT:-/home/zach/reports}"
STALE_HOURS="${STALE_HOURS:-48}"  # 2 days

today="$(date '+%Y-%m-%d %H:%M:%S')"
now_epoch="$(date +%s)"
stale_threshold_seconds=$((STALE_HOURS * 3600))

echo "blockers-liveness-check -- $today (STALE_HOURS=$STALE_HOURS)"
echo "(offline-first: no claude calls -- findings are SIGNALS, not verdicts.)"
echo ""

# Read enabled projects from _paced*.conf files (mandark + dexter configs)
# Extract project names (strip tier suffixes like -sweep, -batch, etc.)
declare -a enabled_projects
for paced_conf in "$SCHED_ROOT"/schedule/_paced*.conf; do
  [ -f "$paced_conf" ] || continue
  while IFS='|' read -r entry enabled rest; do
    # Skip comments and empty lines
    [[ "$entry" =~ ^[[:space:]]*# ]] && continue
    entry="$(echo "$entry" | xargs)"  # trim whitespace
    [ -z "$entry" ] && continue

    enabled="$(echo "$enabled" | xargs)"  # trim whitespace
    if [ "$enabled" = "1" ]; then
      # Strip known tier suffixes (-sweep, -batch, -bug-sweep, -nightly-batch, etc)
      # to get project name (all tiers of a project share one report directory)
      project="$entry"
      project="${project%-sweep}"
      project="${project%-batch}"
      project="${project%-bug-sweep}"
      project="${project%-nightly-batch}"

      # Add to list if not already there
      if ! printf '%s\n' "${enabled_projects[@]:-}" | grep -q "^$project\$"; then
        enabled_projects+=("$project")
      fi
    fi
  done < "$paced_conf"
done

if [ ${#enabled_projects[@]} -eq 0 ]; then
  echo "WARNING: no enabled projects found in $SCHED_ROOT/schedule/_paced*.conf" >&2
  exit 1
fi

stale_count=0
missing_count=0
recent_count=0

for project in "${enabled_projects[@]}"; do
  report_dir="$REPORTS_ROOT/$project"
  latest_report="$report_dir/LATEST.md"

  if [ ! -f "$latest_report" ]; then
    echo "STALE [$project]: no report file found"
    ((missing_count++))
    ((stale_count++))
    continue
  fi

  # Get the timestamp of LATEST.md
  report_mtime="$(stat -c '%Y' "$latest_report" 2>/dev/null || echo "")"
  if [ -z "$report_mtime" ]; then
    echo "UNKNOWN [$project]: cannot read report timestamp" >&2
    continue
  fi

  age_seconds=$((now_epoch - report_mtime))

  if [ "$age_seconds" -gt "$stale_threshold_seconds" ]; then
    age_hours=$((age_seconds / 3600))
    age_days=$((age_hours / 24))
    echo "STALE [$project]: report is $age_days days old"
    ((stale_count++))
  else
    age_hours=$((age_seconds / 3600))
    echo "OK [$project]: report is current ($age_hours hours ago)"
    ((recent_count++))
  fi
done

echo ""
echo "Summary: $recent_count current, $stale_count stale (including $missing_count missing)"

if [ "$stale_count" -gt 0 ]; then
  echo "ALERT: $stale_count project(s) with stale or missing reports" >&2
  exit 1
fi

exit 0
