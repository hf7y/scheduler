#!/usr/bin/env bash
# verdict.sh -- tell NOT-DONE from GAVE-UP, and act differently on each.
#
# THE PROBLEM, from this host's own run log on 2026-07-29:
#
#   12:41:02 DONE scheduler rc=1 (659s)
#   13:05:12 DONE scheduler rc=0 (309s)
#   14:08:57 DONE scheduler rc=1 (533s)
#
# `rc` is the only outcome signal the runner has, and it conflates at least
# three different states: the agent hit --max-turns with work still to do; the
# agent concluded the bar cannot be met from here; the wrapper itself broke.
# Those want OPPOSITE responses. Truncated means dispatch it again -- the run
# was progress, it just ran out of room. Gave-up means dispatch it again is a
# waste of the whole ecosystem's quota, forever, and nobody will notice because
# rc=1 looks like the truncation case.
#
# An ecosystem that cannot tell those apart has no negative feedback: it either
# retries forever (no braking) or backs off on truncation (brakes on progress).
#
# THE RULE, and it is the whole design:
#
#   ABSENCE OF A VERDICT IS NEVER "GAVE UP".
#
# A run that is killed, truncated, crashed, or simply silent leaves no verdict,
# and that classifies as NOT-DONE -- re-dispatch, metabolism untouched. Only an
# agent's OWN explicit IMPOSSIBLE reduces metabolism. This asymmetry is
# deliberate: the failure mode of the opposite default is an ecosystem that
# shuts itself down because a machine rebooted mid-run.
#
# STATE
#   $STATE_ROOT/scheduler-verdict/<participant>    KEY=VALUE, one per line
#
# Keyed on the ROTATION PARTICIPANT NAME, not on the wrapper filename. The
# expires_at convention derives its path from the wrapper basename, which is
# fine there and wrong here: `scheduler-run realisateur batch` and
# `scheduler-run crt batch` share a basename, so two participants would write
# each other's verdicts and each would act on the other's. The participant
# name is what the rotation, the log line, and the agent's own brief all
# already agree on.
#
# The file is CONSUMED at dispatch (`clear`), so a verdict can never outlive
# the run that wrote it. That is the `expires_at` lesson from
# lib/deadman-switch.sh, applied before it can bite: a stale stamp that reads
# as current is worse than no stamp.
#
# USAGE
#   verdict.sh set <job> <CONTINUE|DONE|IMPOSSIBLE> "<one-line reason>"
#   verdict.sh set <job> BLOCKED "<one-line reason>" [issue]
#   verdict.sh get <job>                 # print the record, exit 0 if present
#   verdict.sh classify <job> <rc>       # print NOT-DONE|DONE|GAVE-UP; see below
#   verdict.sh clear <job>               # consume (call at dispatch)
#   verdict.sh --selftest
#
# BLOCKED's optional [issue] (bare number, cwd-resolved; or `owner/repo#N`)
# labels that issue `needs-human` -- the consumer tempo.sh already reads
# (TEMPO_BLOCKED_LABELS) but nothing ever fed, per hf7y/scheduler#149.
# Best-effort: a `gh` failure is reported but does not fail the write.
#
# BLOCKED also refuses a reason under 6 words -- "waiting on a human" is a
# deferral, not a blocker (#522).
#
# classify exit codes, for the runner to branch on:
#   0  DONE     -- bar met; stop dispatching, this is success
#   1  NOT-DONE -- truncated/silent/CONTINUE; re-dispatch, metabolism unchanged
#   3  GAVE-UP  -- explicit IMPOSSIBLE; reduce metabolism and FILE IT
#   4  BLOCKED  -- cannot proceed without something OUTSIDE this run (a
#                  credential, a human, another project). LENGTHEN the interval;
#                  do NOT give up. Distinct from NOT-DONE because "made
#                  progress, ran out of room" and "cannot proceed at all" want
#                  opposite responses, and until 2026-08-12 both were 1.
set -uo pipefail

STATE_ROOT="${STATE_ROOT:-$HOME/.local/share}"
VERDICT_GH_BIN="${VERDICT_GH_BIN:-gh}"

die() { echo "verdict: $*" >&2; exit 2; }
vfile() { echo "$STATE_ROOT/scheduler-verdict/$1"; }

# Best-effort; never fails the caller.
label_needs_human() {
  local issue="$1" args=(issue edit)
  case "$issue" in
    */*'#'*) args+=("${issue##*#}" --repo "${issue%#*}") ;;
    *)       args+=("$issue") ;;
  esac
  args+=(--add-label needs-human)
  if "$VERDICT_GH_BIN" "${args[@]}" >/dev/null 2>&1; then
    echo "verdict: labeled $issue needs-human"
  else
    echo "verdict: could not label $issue needs-human (gh failed -- label it by hand)" >&2
  fi
}

cmd_set() {
  local job="$1" v="$2" reason="${3:-}" issue="${4:-}"
  [ -n "$job" ] || die "set needs a job name"
  case "$v" in
    CONTINUE|DONE|BLOCKED|IMPOSSIBLE) ;;
    *) die "verdict must be CONTINUE, DONE, BLOCKED or IMPOSSIBLE -- got '$v'" ;;
  esac
  if [ -n "$issue" ] && [ "$v" != "BLOCKED" ]; then
    die "an issue argument is only for BLOCKED (it labels the issue needs-human) -- got verdict '$v'"
  fi
  # An IMPOSSIBLE with no reason is not a finding, it is a shrug. It brakes
  # the whole ecosystem, so it must say what it probed.
  if [ "$v" = "IMPOSSIBLE" ] && [ -z "$reason" ]; then
    die "IMPOSSIBLE requires a reason -- name the probe that proves it. This claim slows every project down."
  fi
  # BLOCKED CARRIES A MANDATORY REASON, for the same purpose as IMPOSSIBLE's and
  # one further one. A blocked run that does not name its blocker is a shrug
  # that slows the project down -- and the reason is also the KEY the ledger
  # compares to detect the same blocker twice, which is the signal Zach asked
  # for (hf7y/scheduler#63: "agents who encounter the same blocker twice in a
  # row need a way to slow metabolism"). Without it, two different blockages
  # and one repeated blockage are indistinguishable.
  if [ "$v" = "BLOCKED" ] && [ -z "$reason" ]; then
    die "BLOCKED requires a reason -- name what you are waiting on (a credential, a human, another project). It is compared against the last one to detect the same blocker twice."
  fi
  # A short reason is a deferral wearing BLOCKED's label, not a blocker (#522).
  if [ "$v" = "BLOCKED" ] && [ "$(wc -w <<<"$reason")" -lt 6 ]; then
    die "BLOCKED reason reads as a deferral, not a blocker -- name what you TRIED and the EXACT wall (the command you ran, the error it returned, the permission you lack). Got: '$reason'"
  fi
  local d; d="$(dirname "$(vfile "$job")")"
  mkdir -p "$d" || die "cannot create $d"
  {
    echo "VERDICT=$v"
    echo "REASON=${reason//$'\n'/ }"
    echo "AT=$(date -Is)"
    echo "HOST=$(hostname)"
  } > "$(vfile "$job")" || die "cannot write $(vfile "$job")"
  echo "verdict: $job = $v"
  [ "$v" = "BLOCKED" ] && [ -n "$issue" ] && label_needs_human "$issue"
  return 0
}

cmd_get() {
  local f; f="$(vfile "$1")"
  [ -f "$f" ] || { echo "verdict: no verdict recorded for $1" >&2; return 1; }
  cat "$f"
}

cmd_clear() {
  local f; f="$(vfile "$1")"
  [ -f "$f" ] && rm -f "$f" && echo "verdict: consumed $1's previous verdict"
  return 0
}

# The classifier. Takes the job and the wrapper's rc; prints one word.
cmd_classify() {
  local job="$1" rc="${2:-0}" f v
  f="$(vfile "$job")"

  if [ ! -f "$f" ]; then
    # No verdict. Truncated, killed, crashed, or silent -- all NOT-DONE.
    # This is the load-bearing branch: it must never say GAVE-UP.
    echo "NOT-DONE"
    return 1
  fi

  v="$(grep -m1 '^VERDICT=' "$f" 2>/dev/null | cut -d= -f2-)"
  case "$v" in
    DONE)       echo "DONE";     return 0 ;;
    CONTINUE)   echo "NOT-DONE"; return 1 ;;
    BLOCKED)    echo "BLOCKED";  return 4 ;;
    IMPOSSIBLE) echo "GAVE-UP";  return 3 ;;
    *)
      # A corrupt verdict is not a licence to brake. Degrade to NOT-DONE,
      # loudly -- fail loud, but fail toward retrying rather than toward
      # shutting the ecosystem down on a malformed file.
      echo "NOT-DONE"
      echo "verdict: malformed VERDICT='$v' in $f -- treating as NOT-DONE" >&2
      return 1
      ;;
  esac
}

cmd_selftest() {
  local t rc out fails=0
  t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  STATE_ROOT="$t"

  # Every branch must be OBSERVED FIRING. A classifier never seen rejecting
  # anything is indistinguishable from one that cannot -- see stamp-agent.sh.
  out="$(cmd_classify j 1)"; rc=$?
  [ "$out" = "NOT-DONE" ] && [ $rc -eq 1 ] || { echo "FAIL: absent verdict + rc=1 must be NOT-DONE (got $out/$rc)"; fails=1; }

  out="$(cmd_classify j 0)"; rc=$?
  [ "$out" = "NOT-DONE" ] && [ $rc -eq 1 ] || { echo "FAIL: absent verdict + rc=0 must be NOT-DONE (got $out/$rc)"; fails=1; }

  cmd_set j CONTINUE "still going" >/dev/null
  out="$(cmd_classify j 1)"; rc=$?
  [ "$out" = "NOT-DONE" ] && [ $rc -eq 1 ] || { echo "FAIL: CONTINUE must be NOT-DONE (got $out/$rc)"; fails=1; }

  cmd_set j DONE "bar met" >/dev/null
  out="$(cmd_classify j 0)"; rc=$?
  [ "$out" = "DONE" ] && [ $rc -eq 0 ] || { echo "FAIL: DONE must be DONE (got $out/$rc)"; fails=1; }

  cmd_set j IMPOSSIBLE "probed X, it cannot work" >/dev/null
  out="$(cmd_classify j 1)"; rc=$?
  [ "$out" = "GAVE-UP" ] && [ $rc -eq 3 ] || { echo "FAIL: IMPOSSIBLE must be GAVE-UP (got $out/$rc)"; fails=1; }

  # A DONE/IMPOSSIBLE verdict must not survive its run.
  cmd_clear j >/dev/null
  out="$(cmd_classify j 1)"; rc=$?
  [ "$out" = "NOT-DONE" ] && [ $rc -eq 1 ] || { echo "FAIL: cleared verdict must fall back to NOT-DONE (got $out/$rc)"; fails=1; }

  # IMPOSSIBLE without a reason must be refused.
  if ( cmd_set j IMPOSSIBLE "" >/dev/null 2>&1 ); then
    echo "FAIL: reasonless IMPOSSIBLE was accepted"; fails=1
  fi

  # A stub gh stands in so labeling never touches a real tracker.
  local stubdir="$t/stub"; mkdir -p "$stubdir"
  cat > "$stubdir/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_CALLS_LOG"
[ "${GH_SHOULD_FAIL:-0}" = 1 ] && exit 1
exit 0
STUB
  chmod +x "$stubdir/gh"
  VERDICT_GH_BIN="$stubdir/gh"
  export GH_CALLS_LOG="$t/gh-calls.log"; : > "$GH_CALLS_LOG"

  out="$(cmd_set j BLOCKED "ran gh api PATCH, auto-mode classifier refused it" 458 2>&1)"
  grep -q 'gh issue edit 458 --add-label needs-human' "$GH_CALLS_LOG" \
    || { echo "FAIL: bare issue number did not call gh issue edit 458 --add-label needs-human"; fails=1; }
  grep -q 'labeled 458 needs-human' <<<"$out" || { echo "FAIL: BLOCKED-with-issue did not report the label"; fails=1; }

  : > "$GH_CALLS_LOG"
  cmd_set j BLOCKED "asked for a credential nobody has granted yet" "hf7y/other#12" >/dev/null 2>&1
  grep -q 'gh issue edit 12 --repo hf7y/other --add-label needs-human' "$GH_CALLS_LOG" \
    || { echo "FAIL: owner/repo#N form did not resolve to --repo hf7y/other issue 12"; fails=1; }

  : > "$GH_CALLS_LOG"
  out="$(GH_SHOULD_FAIL=1 cmd_set j BLOCKED "tried the merge, host credential is still missing" 999 2>&1)"; rc=$?
  [ $rc -eq 0 ] || { echo "FAIL: a gh failure must not fail the verdict write itself (rc=$rc)"; fails=1; }
  grep -q 'could not label 999 needs-human' <<<"$out" || { echo "FAIL: gh failure was not reported"; fails=1; }
  unset VERDICT_GH_BIN GH_CALLS_LOG

  if ( cmd_set j BLOCKED "waiting on a human" >/dev/null 2>&1 ); then
    echo "FAIL: a 4-word BLOCKED reason (deferral, not a blocker) was accepted"; fails=1
  fi
  if ( cmd_set j BLOCKED "needs a decision" >/dev/null 2>&1 ); then
    echo "FAIL: 'needs a decision' with no attempt named was accepted"; fails=1
  fi
  if ! ( cmd_set j BLOCKED "ran the deploy script and it hit a permission wall" >/dev/null 2>&1 ); then
    echo "FAIL: a 9-word reason naming an attempt was refused"; fails=1
  fi

  # An issue argument makes no sense outside BLOCKED (it is not a reason).
  if ( cmd_set j DONE "bar met" "458" >/dev/null 2>&1 ); then
    echo "FAIL: an issue argument was accepted on a non-BLOCKED verdict"; fails=1
  fi

  # A malformed file degrades toward retry, not toward braking.
  mkdir -p "$t/scheduler-verdict"; printf 'VERDICT=BANANA\n' > "$t/scheduler-verdict/j"
  out="$(cmd_classify j 1 2>/dev/null)"; rc=$?
  [ "$out" = "NOT-DONE" ] && [ $rc -eq 1 ] || { echo "FAIL: malformed verdict must degrade to NOT-DONE (got $out/$rc)"; fails=1; }

  [ "$fails" -eq 0 ] && echo "selftest OK (16 cases; every classify branch, the BLOCKED needs-human labeling, and the deferral-reason refusal observed firing, incl. all refusals)"
  return "$fails"
}

case "${1:---help}" in
  set)       shift; cmd_set "${1:-}" "${2:-}" "${3:-}" "${4:-}" ;;
  get)       shift; cmd_get "${1:-}" ;;
  clear)     shift; cmd_clear "${1:-}" ;;
  classify)  shift; cmd_classify "${1:-}" "${2:-0}" ;;
  --selftest) cmd_selftest ;;
  -h|--help) sed -n '/^# verdict.sh/,/^set -uo/p' "${BASH_SOURCE[0]}" | sed '$d' ;;
  *) die "unknown subcommand '$1' -- see --help" ;;
esac
