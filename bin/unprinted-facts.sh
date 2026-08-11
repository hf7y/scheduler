#!/usr/bin/env bash
# unprinted-facts.sh -- step 2 of the scheduler sprint: the inventory of
# facts scheduler ALREADY KNOWS that no view prints.
#
# Why this is a script and not a list in FOCUS.md: the sprint's step 3
# (an absence-surface in `scheduler` noargs) is supposed to be designed
# against evidence, and a prose inventory is a measurement taken once,
# on one night, that then decays into a claim. This re-derives it.
#
# Each row is one FACT the machinery records somewhere on disk. The
# verdict column is the whole point:
#
#   PRINTED   <view>  -- some view a human actually opens shows this
#   UNPRINTED         -- recorded on disk, read by nothing
#   BLIND             -- not recorded anywhere; scheduler cannot answer it
#                        today even in principle. These are the expensive
#                        ones, and they are the ones the proposed bar
#                        ("if it cannot know, it says BLIND, never
#                        silence") is actually about.
#
# Exit status is 0 whatever it finds -- this is a measurement, not a gate.
set -uo pipefail

SHARE="$HOME/.local/share"
REGISTRY="$SHARE/scheduler-registry"
REPORTS="$HOME/reports"

U=0; P=0; B=0
row() { # row <verdict> <fact> <evidence>
  case "$1" in
    UNPRINTED) U=$((U+1)) ;;
    PRINTED)   P=$((P+1)) ;;
    BLIND)     B=$((B+1)) ;;
  esac
  printf '  %-10s %-42s %s\n' "$1" "$2" "$3"
}

now=$(date +%s)
age() { # age <epoch> -> "3d" / "4h" / "12m"
  local s=$(( now - $1 ))
  if   [ "$s" -lt 3600 ];  then echo "$((s/60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s/3600))h"
  else echo "$((s/86400))d"; fi
}

echo "unprinted-facts -- $(date -Is)"
echo "  (verdicts are hand-assigned against bin/scheduler's views and re-checked by reading them;"
echo "   the EVIDENCE column is probed live every run)"
echo

echo "== per-job run outcomes (source: ~/.local/share/<job>/sweep.log)"
last_bad=""; stale_state=""; disagree=""
for log in "$SHARE"/*/sweep.log; do
  [ -f "$log" ] || continue
  job="$(basename "$(dirname "$log")")"
  last="$(grep '^=== ' "$log" | tail -1)"
  status="$(sed 's/^=== //; s/ 2026-.*//' <<<"$last")"
  lts="$(grep -o '2026-[0-9-]*T[0-9:]*' <<<"$last" | tail -1)"
  case "$status" in
    done|"") ;;
    *) last_bad="$last_bad$job=$status($lts) " ;;
  esac
  # A state dir whose newest run is ancient while the project still files
  # reports = the real runner moved (another OS account, another host) and
  # this copy is orphaned. vkv-inventory is the live instance: runs under
  # svc-vaporwave, so THIS dir's last record is a FAILED run from 07-20.
  lepoch="$(date -d "$lts" +%s 2>/dev/null || echo 0)"
  [ "$lepoch" -gt 0 ] && [ $(( now - lepoch )) -gt $((5*86400)) ] \
    && stale_state="$stale_state$job($(age "$lepoch")) "
done
row UNPRINTED "last run's OUTCOME per job" "${last_bad:-all 'done' right now}"
row UNPRINTED "state dir orphaned by a moved runner" "${stale_state:-none}"
# Not fully blind, and saying so precisely matters: `scheduler status <p>`
# reads a CRON_ACCOUNT job's state via `sudo -n -u` and prints BLIND when it
# cannot (bin/scheduler:2590, 2026-07-28). The glance does neither -- it
# reads $HOME's paths for every project, so a job that runs elsewhere is
# scored on an orphaned local state dir. That is the gap, not the account.
row UNPRINTED "CRON_ACCOUNT jobs' real state, in the GLANCE" "status handles it (prints BLIND); glance reads \$HOME regardless"

fails="$(grep -l '^=== FAILED' "$SHARE"/*/sweep.log 2>/dev/null | wc -l)"
failn="$(grep -h -c '^=== FAILED' "$SHARE"/*/sweep.log 2>/dev/null | paste -sd+ | bc 2>/dev/null)"
row UNPRINTED "count of FAILED runs, ever" "${failn:-?} across ${fails:-0} job(s)"

skipn="$(grep -h -c '^=== skipped' "$SHARE"/*/sweep.log 2>/dev/null | paste -sd+ | bc 2>/dev/null)"
row UNPRINTED "dispatches that did nothing (skipped/*)" "${skipn:-?} run records -- precheck, expiry, deferral"

echo
echo "== the LAST RUN column's own honesty (glance reads reports/<p>/LATEST.md mtime)"
for rp in "$REPORTS"/*/LATEST.md; do
  [ -e "$rp" ] || continue
  proj="$(basename "$(dirname "$rp")")"
  job="$(ls -d "$SHARE/$proj"-*batch "$SHARE/$proj"-*sweep 2>/dev/null | head -1)"
  [ -n "$job" ] && [ -f "$job/sweep.log" ] || continue
  rts="$(stat -c %Y "$rp" 2>/dev/null || echo 0)"
  lts="$(grep -o '2026-[0-9-]*T[0-9:]*' <<<"$(grep '^=== ' "$job/sweep.log" | tail -1)" | tail -1)"
  lep="$(date -d "$lts" +%s 2>/dev/null || echo 0)"
  [ "$rts" -gt 0 ] && [ "$lep" -gt 0 ] || continue
  d=$(( rts > lep ? rts - lep : lep - rts ))
  [ "$d" -gt 3600 ] && disagree="$disagree$proj(${d}s) "
done
row UNPRINTED "report mtime vs the run log disagreeing" "${disagree:-none over 1h}"

echo
echo "== right now (source: ~/.local/share/scheduler-registry/)"
active="$(ls "$REGISTRY"/*.active 2>/dev/null | xargs -r -n1 basename | sed 's/\.active$//' | paste -sd' ')"
# Liveness-checked, not just "a marker file exists" -- a marker whose pid is
# gone is exactly the stale-sensor failure this inventory is measuring, so
# counting files here would have been the same mistake one level up.
inter=""; stale_marker=""
for m in "$REGISTRY"/*.interactive; do
  [ -f "$m" ] || continue
  p="$(basename "$m" .interactive)"
  pid="$(sed -n 's/^pid=//p' "$m" | head -1)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then inter="$inter$p "
  else stale_marker="$stale_marker$p "; fi
done
row UNPRINTED "which jobs are running THIS SECOND" "${active:-none}"
row UNPRINTED "which projects a human has open" "${inter:-none} (live pids; read only by check-project-busy)"
row UNPRINTED "interactive markers left by dead pids" "${stale_marker:-none}"

echo
echo "== the dispatcher's own log (source: ~/.local/share/scheduler-paced-runner/run.log)"
RL="$SHARE/scheduler-paced-runner/run.log"
if [ -f "$RL" ]; then
  pullskip="$(grep -c 'PULL skip' "$RL" 2>/dev/null)"
  lastdisp="$(grep -n 'DISPATCH\|DONE ' "$RL" 2>/dev/null | tail -1 | cut -c1-90)"
  holdstreak="$(tail -400 "$RL" | grep -c 'HOLD (gate')"
  row UNPRINTED "deployed code stopped pulling new commits" "${pullskip:-0} PULL skip(s) -- a stray untracked file is enough"
  # The LIFETIME count above cannot tell a blip from a freeze -- which is the
  # whole of #61. The dispatcher now keeps the CONSECUTIVE count as state; read
  # it rather than re-deriving it from the log, so there is one definition.
  PB="$SHARE/scheduler-paced-runner/pull-block.state"
  if [ -f "$PB" ]; then
    read -r pb_n pb_reason _ < "$PB" 2>/dev/null || true
    row UNPRINTED "is the pull frozen RIGHT NOW" "${pb_n:-?} consecutive blocked tick(s), cause: ${pb_reason:-unknown} -- deployed code here is STALE"
  else
    row UNPRINTED "is the pull frozen RIGHT NOW" "no -- last pull attempt advanced or was already current"
  fi
  row UNPRINTED "consecutive gate HOLDs (dispatch drought)" "${holdstreak:-0} in the last 400 log lines"
  row UNPRINTED "when the last actual dispatch was" "${lastdisp:-none found in run.log}"
else
  row UNPRINTED "the dispatcher's run.log" "MISSING at $RL -- itself unreported anywhere"
fi
row PRINTED "current gate verdict + burn-line" "scheduler pacing show"

echo
echo "== already carried by a view (kept here so the fold is measured, not assumed)"
row PRINTED "open questions / blockers per project" "scheduler (glance) columns"
row PRINTED "expired jobs (dead-man switch)" "glance footer"
row PRINTED "unpushed commits in a dedicated clone" "glance footer"
row PRINTED "branches awaiting review" "glance footer"
row PRINTED "FOCUS backlog size + next item + ETA" "glance NEXT UP / ETA"

echo
echo "== BLIND -- nothing on disk answers these"
row BLIND "was a dispatch DUE and did not happen?" "no expected-vs-actual record exists anywhere"
row BLIND "did each cron line fire at all?" "crontab is a schedule; nothing logs a non-firing tick"
row BLIND "runs on other HOSTS (dexter, mandark)" "no cross-host state channel exists at all"

echo
TOTAL=$((U+P+B))
echo "  $TOTAL facts: $P printed, $U recorded-but-unprinted, $B blind."
echo "  The fold is lossy: the views carry $P of $TOTAL. Everything under UNPRINTED"
echo "  already exists on this disk and costs nothing but a reader."
