#!/usr/bin/env bash
# answer-reader-witness.sh -- bin/scheduler-run MUST read any answer relayed
# into lib/answer-registry.sh since this project's last ledger row, and bake
# it into PROMPT before the agent starts.
#
# THE GAP THIS CLOSES (hf7y/scheduler#149 build item 2). `scheduler questions
# <proj>` posts Zach's answer as a GitHub comment (and, since this issue's
# first build item, records it as a typed row) -- but a comment on a tracker
# is exactly as unread as `<!-- DEFERRED -->` was before route-deliveries.sh:
# a claim the write side enforces and the read side never checks. Evidence
# in #149: one question re-posed 100 minutes after its answer; the same
# question answered three separate times. This makes the read MECHANICAL,
# the same way MILESTONE-QUEUE and the ceiling breadcrumb are -- baked into
# the prompt, not left for the agent to rediscover on its own initiative.
#
# WITNESS-FIRST, PER STANDING RULE 5: bin/scheduler-run is one of the three
# dispatch-path files that may never change un-witnessed. This file is
# written to observe the NEW behaviour and FAILS against the code as it
# stood before this change.
#
# HERMETICITY: full. Same fixture shape as tests/milestone-queue-witness.sh --
# a copy of bin/scheduler-run, a stub sweep-loop-common.sh that just prints
# PROMPT, and a stub freeze-check.sh. lib/answer-registry.sh and
# lib/run-ledger.sh are the REAL libraries (pure, no network), pointed at
# tempfiles via ANSWER_REGISTRY_FILE/RUN_LEDGER_FILE so nothing touches the
# live estate.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"
cp "$ROOT/lib/answer-registry.sh" "$FX/lib/answer-registry.sh"
cp "$ROOT/lib/run-ledger.sh" "$FX/lib/run-ledger.sh"

mkconf() {  # $1=name $2=repo_url, rest=lines
  local name="$1" url="$2"; shift 2
  { echo "REPO_URL=\"$url\""; printf '%s\n' "$@"; } > "$FX/schedule/$name.conf"
}

export ANSWER_REGISTRY_FILE="$TMP/answers.tsv"
export RUN_LEDGER_FILE="$TMP/ledger.tsv"
# shellcheck disable=SC1091
source "$ROOT/lib/answer-registry.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/run-ledger.sh"

run() { ( cd "$FX" && bash bin/scheduler-run "$1" "$2" 2>"$TMP/err" ); }

echo "== case 1: an answer recorded since the last ledger row is delivered"
: > "$ANSWER_REGISTRY_FILE"; : > "$RUN_LEDGER_FILE"
ledger_append proj batch 0 DONE "bar met"
sleep 1
answer_registry_record proj 42 relay "Use the staging-uploads bucket."
mkconf proj "https://github.com/hf7y/proj.git" 'BATCH_JOB_NAME="proj-batch"' \
  'BATCH_PROMPT="ORIGINAL BRIEF."'
out="$(run proj batch)"
case "$out" in
  *"Use the staging-uploads bucket."*"ORIGINAL BRIEF."*) ok "the answer text is prepended ahead of the conf's own brief" ;;
  *) bad "answer text missing or wrongly ordered: [$out]" ;;
esac
case "$out" in *"#42"*) ok "names which issue it answered" || bad "answer block doesn't name the issue" ;; esac
case "$out" in *"before"*|*"BEFORE"*|*"first"*|*"FIRST"*) ok "tells the agent to act on it before anything else" ;;
              *) bad "no urgency framing in the delivered block: [$out]" ;; esac

echo "== case 2: an answer already covered by the last ledger row is NOT redelivered"
: > "$ANSWER_REGISTRY_FILE"; : > "$RUN_LEDGER_FILE"
answer_registry_record old-proj 7 relay "This was answered ages ago."
sleep 1
ledger_append old-proj batch 0 DONE "already saw it"
mkconf old-proj "https://github.com/hf7y/old-proj.git" 'BATCH_JOB_NAME="old-batch"' \
  'BATCH_PROMPT="ORIGINAL BRIEF."'
out="$(run old-proj batch)"
case "$out" in
  "ORIGINAL BRIEF.") ok "a stale answer (older than the last dispatch) is not re-delivered" ;;
  *) bad "a stale answer was redelivered: [$out]" ;;
esac

echo "== case 3: a project with no ledger history yet still gets its answers"
: > "$ANSWER_REGISTRY_FILE"; : > "$RUN_LEDGER_FILE"
answer_registry_record fresh-proj 3 relay "First answer this project has ever gotten."
mkconf fresh-proj "https://github.com/hf7y/fresh-proj.git" 'BATCH_JOB_NAME="fresh-batch"' \
  'BATCH_PROMPT="ORIGINAL BRIEF."'
out="$(run fresh-proj batch)"
case "$out" in
  *"First answer this project has ever gotten."*) ok "a never-dispatched project still receives its answer (no ledger row to compare against)" ;;
  *) bad "answer missing for a project with no ledger history: [$out]" ;;
esac

echo "== case 4: no unread answers means the prompt is untouched"
: > "$ANSWER_REGISTRY_FILE"; : > "$RUN_LEDGER_FILE"
mkconf quiet "https://github.com/hf7y/quiet.git" 'BATCH_JOB_NAME="quiet-batch"' \
  'BATCH_PROMPT="ORIGINAL BRIEF."'
out="$(run quiet batch)"
[ "$out" = "ORIGINAL BRIEF." ] && ok "no answers -- the prompt is exactly the conf's own brief" \
  || bad "prompt was altered with nothing to deliver: [$out]"

echo "== case 5: an unreadable registry fails OPEN -- dispatch still happens"
unset ANSWER_REGISTRY_FILE
( cd "$FX" && ANSWER_REGISTRY_FILE="/nonexistent-dir-$$/registry.tsv" RUN_LEDGER_FILE="$TMP/ledger.tsv" \
    bash bin/scheduler-run quiet batch >"$TMP/out5" 2>"$TMP/err5" )
rc=$?
export ANSWER_REGISTRY_FILE="$TMP/answers.tsv"
[ "$rc" -eq 0 ] && ok "dispatch still exits 0 when the registry cannot be read" \
  || bad "dispatch exited $rc when the registry was unreadable"

echo "== case 6: answered questions for ANOTHER project never leak into this one"
: > "$ANSWER_REGISTRY_FILE"; : > "$RUN_LEDGER_FILE"
answer_registry_record other-proj 9 relay "This belongs to a different project entirely."
mkconf leaktest "https://github.com/hf7y/leaktest.git" 'BATCH_JOB_NAME="leak-batch"' \
  'BATCH_PROMPT="ORIGINAL BRIEF."'
out="$(run leaktest batch)"
case "$out" in
  *"different project entirely"*) bad "another project's answer leaked into this prompt: [$out]" ;;
  *) ok "another project's answer is not delivered here" ;;
esac

echo
echo "answer-reader-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
