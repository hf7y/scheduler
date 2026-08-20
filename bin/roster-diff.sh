#!/usr/bin/env bash
# roster-diff.sh -- mechanical proof that schedule/ROSTER derives the SAME
# live/parked set as the files it is meant to replace. hf7y/scheduler#79's
# losslessness requirement: "write the comparison as a script that reads old
# and new and diffs the derived set -- not by eye."
#
# schedule/FREEZE was retired 2026-08-20 (hf7y/scheduler#246/#187, "kill
# freeze it's redundant") -- it is no longer one of the "old" files: deleting
# it did not merely stop the probe, it changed what dispatch actually reads,
# so comparing against it here would compare ROSTER against a file nothing
# consults anymore. What's left of "old" is _paced.<host>.conf's enabled
# column plus CRON_HOST/CRON_ACCOUNT.
#
# GUARD: does schedule/ROSTER agree with schedule/_paced.<host>.conf +
#        each schedule/<project>.conf's CRON_HOST/CRON_ACCOUNT -- same
#        projects, same account@host, same live/parked state?
# RUNNER: tests/roster-diff-witness.sh
#
# CONTRACT
#   exit 0  -- old and new derive the IDENTICAL set. Checked in BOTH
#              directions (in-old-not-new and in-new-not-old), so a roster
#              that quietly adds or drops a project is caught either way.
#   exit 1  -- disagreement. Every disagreeing project is named on stdout.
#   exit 2  -- BLIND: a required file is missing/unreadable, or a row could
#              not be parsed. Never reported as agreement.
#
# host is $ROSTER_DIFF_HOST (default monkey), the only host schedule/ROSTER
# covers today. SCHED_ROOT overrides the repo root (for the witness).
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SCHED_ROOT="${SCHED_ROOT:-$ROOT}"
HOST="${ROSTER_DIFF_HOST:-monkey}"

PACED="$SCHED_ROOT/schedule/_paced.$HOST.conf"
ROSTER="$SCHED_ROOT/schedule/ROSTER"

blind=0
blind_reasons=()
blind_at() { blind=1; blind_reasons+=("$1"); }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

report_blind() {
  echo "BLIND -- cannot say whether old and new agree:"
  printf '  %s\n' "${blind_reasons[@]}"
  exit 2
}

[ -f "$PACED" ] && [ -r "$PACED" ]   || blind_at "cannot read $PACED"
[ -f "$ROSTER" ] && [ -r "$ROSTER" ] || blind_at "cannot read $ROSTER"
[ "$blind" -eq 1 ] && report_blind

# ---------------------------------------------------------------------------
# OLD side: derive from _paced.$HOST.conf + per-project confs.
# ---------------------------------------------------------------------------
declare -A paced_enabled     # name -> "0"/"1", only set where a row exists
declare -A is_candidate      # name -> 1 for any name seen in the paced file
declare -A cron_host         # name -> CRON_HOST from schedule/<name>.conf
declare -A cron_account      # name -> CRON_ACCOUNT from schedule/<name>.conf
declare -A old_repr          # name -> "account@host|state"

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
  IFS='|' read -r name enabled _rest <<<"$line"
  name="$(trim "$name")"; enabled="$(trim "$enabled")"
  [ -n "$name" ] || continue
  paced_enabled["$name"]="$enabled"
  is_candidate["$name"]=1
done < "$PACED"

for name in "${!is_candidate[@]}"; do
  conf="$SCHED_ROOT/schedule/$name.conf"
  if [ ! -f "$conf" ] || [ ! -r "$conf" ]; then
    blind_at "candidate '$name' has no readable schedule/$name.conf to check CRON_HOST/CRON_ACCOUNT"
    continue
  fi
  h="$(grep -E '^CRON_HOST=' "$conf" 2>/dev/null | tail -1 | sed -E 's/^CRON_HOST="?([^"]*)"?.*/\1/')"
  a="$(grep -E '^CRON_ACCOUNT=' "$conf" 2>/dev/null | tail -1 | sed -E 's/^CRON_ACCOUNT="?([^"]*)"?.*/\1/')"
  cron_host["$name"]="$h"
  cron_account["$name"]="$a"
done
[ "$blind" -eq 1 ] && report_blind

for name in "${!is_candidate[@]}"; do
  en="${paced_enabled[$name]:-0}"
  ch="${cron_host[$name]:-}"
  ca="${cron_account[$name]:-}"
  state="parked"
  [ "$en" = "1" ] && [ "$ch" = "$HOST" ] && [ -n "$ca" ] && state="live"
  acct="${ca:-$name}"
  host="${ch:-$HOST}"
  old_repr["$name"]="$acct@$host|$state"
done

# ---------------------------------------------------------------------------
# NEW side: derive from schedule/ROSTER. `rate` is parsed but not compared --
# the old files carry no per-project rate to compare it against (#79: rate is
# fixed 6h by fiat for this migration, not derived).
# ---------------------------------------------------------------------------
declare -A new_repr   # name -> "account@host|state"

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
  IFS='|' read -r rname racct rrate rstate <<<"$line"
  rname="$(trim "$rname")"; racct="$(trim "$racct")"
  rrate="$(trim "${rrate:-}")"; rstate="$(trim "${rstate:-}")"
  if [ -z "$rname" ] || [ -z "$racct" ] || [ -z "$rstate" ]; then
    blind_at "schedule/ROSTER: unparsable row: $line"
    continue
  fi
  case "$rstate" in
    live|parked) ;;
    *) blind_at "schedule/ROSTER: row for '$rname' has invalid state '$rstate' (want live|parked): $line"; continue ;;
  esac
  new_repr["$rname"]="$racct|$rstate"
done < "$ROSTER"
[ "$blind" -eq 1 ] && report_blind

# ---------------------------------------------------------------------------
# Diff, both directions, every disagreement named.
# ---------------------------------------------------------------------------
disagree=0
all_names="$(printf '%s\n' "${!old_repr[@]}" "${!new_repr[@]}" | sort -u)"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  o="${old_repr[$name]:-}"
  n="${new_repr[$name]:-}"
  if [ -z "$o" ]; then
    echo "DIFF: $name -- in schedule/ROSTER (new) but not derivable from _paced.$HOST.conf/FREEZE (old)"
    disagree=1
  elif [ -z "$n" ]; then
    echo "DIFF: $name -- derived from old files (old=$o) but absent from schedule/ROSTER"
    disagree=1
  elif [ "$o" != "$n" ]; then
    echo "DIFF: $name -- old=$o  new=$n"
    disagree=1
  fi
done <<<"$all_names"

total="$(printf '%s\n' "${!old_repr[@]}" "${!new_repr[@]}" | sort -u | wc -l)"
if [ "$disagree" -eq 1 ]; then
  echo "roster-diff: DISAGREE ($total project(s) considered) -- schedule/ROSTER is not yet lossless"
  exit 1
fi
echo "roster-diff: AGREE -- $total project(s), same accounts@hosts, same live/parked state"
exit 0
