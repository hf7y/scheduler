#!/usr/bin/env bash
# resume-hint-witness.sh -- hf7y/scheduler#297 step 3 / #345: feed a
# DERIVED-CONTINUE's PR forward into the NEXT dispatch's prompt.
#
# THE GAP: #344 made a silent run's ledger reason say
# "DERIVED-CONTINUE: open PR #N on <repo> has a failing check ..." instead of
# a generic "no-verdict: ran with no verdict written". That reason landed in
# the ledger's reason column and the tick log, but nothing downstream read
# it -- a run that left PR #14 open and red kept getting re-dispatched to
# pick a FRESH issue instead of being told to go finish #14.
#
# THE FIX, in two halves that this witness covers together (same shape as
# ceiling-breadcrumb-witness.sh covering write_/read_ceiling_breadcrumb):
#   1. bin/usage-paced-runner.sh's resume_hint_for_project() -- checks
#      whether a project's MOST RECENT ledger row is a DERIVED-CONTINUE
#      NOT-DONE, and if so prints "PR REPO" as two bare tokens (the caller
#      exports these into the dispatched job's environment).
#   2. lib/sweep-loop-common.sh's read_resume_hint() -- turns those two env
#      vars into a prompt prefix, the same reading-order slot as
#      read_ceiling_breadcrumb.
#
# Must NOT change dispatch behaviour or the ledger's own vocabulary -- this is
# context recovery only, same non-goal as the ceiling breadcrumb.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
SWEEP_LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "resume-hint-witness"

# --- half 1: resume_hint_for_project() in bin/usage-paced-runner.sh --------

BLOCK="$TMP/resume-hint.sh"
awk '/^resume_hint_for_project\(\) \{$/,/^\}$/' "$RUNNER" > "$BLOCK"
grep -q 'resume_hint_for_project' "$BLOCK" \
  || { echo "FAIL: could not extract resume_hint_for_project() from $RUNNER"; exit 1; }

export RUN_LEDGER_FILE="$TMP/ledger.tsv"
# shellcheck disable=SC1090
. "$ROOT/lib/run-ledger.sh"
# shellcheck disable=SC1090
. "$BLOCK"

echo "== 1. no history at all -- no hint"
out="$(resume_hint_for_project never-seen)"
[ -z "$out" ] && ok "unknown project prints nothing" || bad "expected nothing, got: $out"

echo "== 2. most recent row is DERIVED-CONTINUE NOT-DONE -- prints PR and repo"
ledger_append hasrepo batch 1 NOT-DONE "DERIVED-CONTINUE: open PR #14 on hf7y/abletim has a failing check -- next dispatch should finish it, not start fresh"
out="$(resume_hint_for_project hasrepo)"
[ "$out" = "14 hf7y/abletim" ] && ok "prints PR and repo as two bare tokens" \
  || bad "expected '14 hf7y/abletim', got: '$out'"

echo "== 3. most recent row is DERIVED-SILENT NOT-DONE -- no hint (nothing to point at)"
ledger_append silentproj batch 1 NOT-DONE "DERIVED-SILENT: no open PR on hf7y/silentproj, updated since this run started, with a failing check -- nothing to point at"
out="$(resume_hint_for_project silentproj)"
[ -z "$out" ] && ok "DERIVED-SILENT produces no hint" || bad "expected nothing, got: $out"

echo "== 4. an ordinary (non-derived) NOT-DONE reason -- no hint"
ledger_append ordinary batch 1 NOT-DONE "ran out of turns with real work left"
out="$(resume_hint_for_project ordinary)"
[ -z "$out" ] && ok "a hand-written NOT-DONE reason is not mistaken for DERIVED-CONTINUE" \
  || bad "expected nothing, got: $out"

echo "== 5. a DERIVED-CONTINUE row followed by a real DONE -- silenced, not the stale hint"
ledger_append resolved batch 1 NOT-DONE "DERIVED-CONTINUE: open PR #7 on hf7y/resolved has a failing check -- next dispatch should finish it, not start fresh"
ledger_append resolved batch 0 DONE "PR #7 merged and closed"
out="$(resume_hint_for_project resolved)"
[ -z "$out" ] && ok "the MOST RECENT row (DONE) silences an older DERIVED-CONTINUE row" \
  || bad "expected nothing (project moved on), got: $out"

echo "== 6. two different projects' rows do not cross-contaminate"
ledger_append other-one batch 1 NOT-DONE "DERIVED-CONTINUE: open PR #99 on hf7y/other-one has a failing check -- next dispatch should finish it, not start fresh"
out_a="$(resume_hint_for_project hasrepo)"
out_b="$(resume_hint_for_project other-one)"
[ "$out_a" = "14 hf7y/abletim" ] && [ "$out_b" = "99 hf7y/other-one" ] \
  && ok "each project's hint is keyed to its own rows" \
  || bad "cross-contamination: hasrepo='$out_a' other-one='$out_b'"

# --- half 2: read_resume_hint() in lib/sweep-loop-common.sh ----------------

BLOCK2="$TMP/read-resume-hint.sh"
awk '/^read_resume_hint\(\) \{$/,/^\}$/' "$SWEEP_LIB" > "$BLOCK2"
grep -q 'read_resume_hint' "$BLOCK2" \
  || { echo "FAIL: could not extract read_resume_hint() from $SWEEP_LIB"; exit 1; }
# shellcheck disable=SC1090
. "$BLOCK2"

echo "== 7. neither env var set -- PROMPT untouched"
unset SCHEDULER_RESUME_PR SCHEDULER_RESUME_REPO
PROMPT="original prompt text"
read_resume_hint
[ "$PROMPT" = "original prompt text" ] \
  && ok "PROMPT unchanged with no resume hint in the environment" \
  || bad "PROMPT was rewritten with nothing to resume: $PROMPT"

echo "== 8. only PR set, repo missing -- treated as no hint, not a partial one"
SCHEDULER_RESUME_PR=14
unset SCHEDULER_RESUME_REPO
PROMPT="original prompt text"
read_resume_hint
[ "$PROMPT" = "original prompt text" ] \
  && ok "a partial hint (PR with no repo) does not fire" \
  || bad "a partial hint fired: $PROMPT"
unset SCHEDULER_RESUME_PR

echo "== 9. both set -- prepended to PROMPT, naming PR and repo, and consumed"
SCHEDULER_RESUME_PR=14
SCHEDULER_RESUME_REPO=hf7y/abletim
PROMPT="the conf's own brief"
read_resume_hint
case "$PROMPT" in
  *"#14"*"hf7y/abletim"*"the conf's own brief")
    ok "resume instruction prepended ahead of the conf's own brief, naming PR and repo" ;;
  *) bad "resume hint not prepended correctly: $PROMPT" ;;
esac
[ -z "${SCHEDULER_RESUME_PR:-}" ] && [ -z "${SCHEDULER_RESUME_REPO:-}" ] \
  && ok "env vars unset after being read" \
  || bad "env vars survived being read: PR=${SCHEDULER_RESUME_PR:-} REPO=${SCHEDULER_RESUME_REPO:-}"

echo
echo "resume-hint-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
