#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's append_verdict_closeout().
#
# THE BUG THIS EXISTS TO PREVENT, observed live on monkey 2026-08-06:
# bin/usage-paced-runner.sh logged, every tick for weeks,
#
#   NO-VERDICT vim-arcade -- ran with no verdict written (its brief asks
#   for one). Treated as NOT-DONE and re-dispatched; metabolism untouched.
#
# and vim-arcade's ~/.local/share/scheduler-verdict/ did not exist at all.
# The brief did NOT ask for one: the only verdict instruction in the whole
# ecosystem was a paragraph pasted by hand into schedule/bibliothecaire.conf's
# BATCH_PROMPT. The runner's contract was real; nothing mechanized it.
#
# So the assertion here is not "the text is present somewhere" -- that was
# true of bibliothecaire's conf all along and bought nothing. It is that the
# ENGINE puts it there, for a participant whose conf says nothing, and that
# the command it hands the agent is one that actually runs.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Sourcing the whole engine would run a real job (clone, claude, push), so
# lift just the one function out of it -- same technique as
# notify-timeout-witness.sh. An extraction that stops matching is a FAILURE,
# not a pass by absence.
awk '/^append_verdict_closeout\(\) \{$/,/^\}$/' "$LIB" > "$TMP/fn.sh"
grep -q 'verdict\.sh\|VERDICT_BIN' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract append_verdict_closeout() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

VERDICT_BIN="$ROOT/bin/verdict.sh"

echo "== 1. a batch brief that says nothing about verdicts gets the closeout"
# vim-arcade's real conf: BATCH_PROMPT is a bare slash command that resolves
# inside the project's OWN repo, which this repo cannot edit.
TIER="nightly-batch"; PROJECT_KEY="vim-arcade"; PROMPT="/nightly-batch"
append_verdict_closeout > "$TMP/out"; OUT="$(cat "$TMP/out")"
[ "$PROMPT" != "/nightly-batch" ] \
  && ok "prompt was rewritten (the whole point -- it used to pass through untouched)" \
  || bad "prompt unchanged: the engine still asks for nothing"
grep -q 'verdict\.sh set vim-arcade' <<<"$PROMPT" \
  && ok "names the exact command, with THIS participant's name" \
  || bad "closeout does not contain 'verdict.sh set vim-arcade'"
for v in CONTINUE DONE IMPOSSIBLE; do
  grep -q "$v" <<<"$PROMPT" && ok "explains $v" || bad "never mentions $v"
done
grep -q 'appended to the brief' <<<"$OUT" \
  && ok "says so in the run log (a silent prompt rewrite is unreviewable)" \
  || bad "rewrote the prompt without logging it"
grep -q '^/nightly-batch' <<<"$PROMPT" \
  && ok "the conf's own brief is still first and intact" \
  || bad "clobbered the conf's brief instead of appending to it"

echo "== 2. the command it hands the agent REALLY WORKS"
# The failure this catches is the one that makes a guard worthless: a brief
# that confidently instructs the agent to run something that errors out. Run
# the extracted command line for real, against a throwaway STATE_ROOT.
CMD="$(grep -m1 'verdict\.sh set' <<<"$PROMPT")"
[ -n "$CMD" ] || bad "no verdict.sh command line in the prompt to run"
CMD="${CMD/<VERDICT>/DONE}"
CMD="${CMD/\"<one line, what you actually did>\"/\"witness run\"}"
if STATE_ROOT="$TMP/state" bash -c "$CMD" >/dev/null 2>&1; then
  ok "the pasted command line executes clean"
else
  bad "the command the brief tells the agent to run FAILS: $CMD"
fi
if [ -f "$TMP/state/scheduler-verdict/vim-arcade" ]; then
  ok "and it lands at the path bin/verdict.sh's classifier reads"
  grep -q '^VERDICT=DONE$' "$TMP/state/scheduler-verdict/vim-arcade" \
    && ok "with the verdict the agent asked for" || bad "wrong contents"
  OUTC="$(STATE_ROOT="$TMP/state" "$ROOT/bin/verdict.sh" classify vim-arcade 0)"
  [ "$OUTC" = "DONE" ] \
    && ok "and classify() reads it back as DONE -- the runner would finally see it" \
    || bad "classify said '$OUTC'"
else
  bad "no verdict file written -- the closeout points somewhere nothing reads"
fi

echo "== 3. a conf that already carries its own verdict wording is left alone"
# schedule/bibliothecaire.conf, step 6. Its wording is more specific than the
# generic block; appending a second copy would give one prompt two overlapping
# instructions.
TIER="nightly-batch"; PROJECT_KEY="bibliothecaire"
PROMPT='Work the queue. Before stopping: $HOME/Documents/Projects/scheduler/bin/verdict.sh set bibliothecaire <VERDICT> "..."'
BEFORE="$PROMPT"
append_verdict_closeout > "$TMP/out"; OUT="$(cat "$TMP/out")"
[ "$PROMPT" = "$BEFORE" ] && ok "prompt untouched" || bad "double-instructed a conf that already asked"
grep -q 'skipped' <<<"$OUT" && ok "and says WHY it skipped" || bad "skipped silently"

echo "== 4. sweep tier gets nothing"
# The verdict file is keyed on the rotation participant name and consumed at
# dispatch; a sweep run writing under the same key between paced ticks would
# hand the batch run someone else's verdict.
TIER="bug-sweep"; PROJECT_KEY="chezz"; PROMPT="sweep the tracker"
append_verdict_closeout >/dev/null
[ "$PROMPT" = "sweep the tracker" ] \
  && ok "bug-sweep brief unchanged" \
  || bad "sweep tier would write under the batch participant's key"

echo "== 5. a missing verdict.sh is LOUD, not a confidently broken brief"
TIER="batch"; PROJECT_KEY="ghost"; PROMPT="do the thing"
VERDICT_BIN="$TMP/nope/verdict.sh"
append_verdict_closeout > "$TMP/out"; OUT="$(cat "$TMP/out")"
[ "$PROMPT" = "do the thing" ] \
  && ok "does not paste a path to a command that is not there" \
  || bad "told the agent to run a nonexistent command"
grep -q 'WARNING' <<<"$OUT" && ok "warns in the run log" || bad "silently did nothing"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
