#!/usr/bin/env bash
# Witness for the QUESTIONS.md ANSWER CONTRACT (rules A-D, 2026-07-29).
#
# What the contract is: a `> ` reply is the most authoritative input this
# system takes, and until 2026-07-29 it was the only one with NO admission
# control -- ideas are parked by default, machine-state claims are
# re-probed rather than quoted, and an answer was simply obeyed. The
# failure that names the gap is a question asked from a STALE PREMISE, so
# a correct reply directs action at a world that no longer exists. Rules
# A-D authorize the actor to notice that, without demoting the answer.
#
# Why a witness and not just prose: the rules are prose, and prose decays.
# Two copies of them exist in this repo and they must not drift -- the body
# `scheduler ask` writes into the GitHub issue it opens (the copy the person
# answering actually reads), and `examples/nightly-batch.md.template`'s
# answer-processing step (where the rules bind at run time). A rule dropped
# from either is a silent hole, so absence here is a FAILURE, never a pass.
#
# The contract used to have a third home, `examples/QUESTIONS.md.template`,
# copied into every new project by `scheduler ask`. #66 (2026-08-07) retired
# that channel and hf7y/realisateur#293 deleted the file; section 3 below now
# asserts the REFUSAL that replaced the copy, because a re-grown QUESTIONS.md
# in a repo that had none is the exact failure the sunset exists to stop.
#
# A fourth assertion block used to cover bin/questions-lint.sh's own entry-
# parsing regression; that tool was retired with the rest of the QUESTIONS.md
# machinery (hf7y/scheduler#234) and its coverage retired with it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# Assert a file exists AND contains a pattern. A missing file is a FAIL,
# not a skip -- the whole point is that a dropped copy is loud.
has() {  # $1 = file, $2 = grep -E pattern, $3 = label
  if [ ! -f "$1" ]; then bad "$3 -- file missing entirely: $1"; return; fi
  if grep -qEi -- "$2" "$1"; then ok "$3"; else bad "$3 -- not found in $1"; fi
}

echo "== 1. canonical text: the issue body \`scheduler ask\` writes"
CANON="$ROOT/bin/scheduler"
has "$CANON" 'direction, not instruction'                  "A -- answers are direction, not instruction"
has "$CANON" 'CURRENT state'                               "A -- re-derive from current state"
has "$CANON" 're-probe the premise'                        "B -- re-probe the premise"
has "$CANON" 'reversib'                                    "B -- splits by reversibility"
has "$CANON" 'irreversible'                                "B -- names the irreversible half"
has "$CANON" 'standing direction'                          "C -- extract the standing direction"
has "$CANON" 'no clean-check reports|NO OUTPUT'            "D -- no clean-check reports"

echo "== 2. run-time binding: examples/nightly-batch.md.template"
NB="$ROOT/examples/nightly-batch.md.template"
has "$NB" 'direction, not instruction'                     "A -- present in the answer-processing step"
has "$NB" 're-probe the premise'                           "B -- present in the answer-processing step"
has "$NB" 'REVERSIBLE'                                     "B -- reversible half named"
has "$NB" 'IRREVERSIBLE'                                   "B -- irreversible half named"
has "$NB" 'standing direction'                             "C -- present in the answer-processing step"
has "$NB" 'clean-check'                                    "D -- present in the answer-processing step"

echo '== 3. `scheduler ask` REFUSES the retired file channel'
# Real invocation, not a grep of the source: what matters is that a project
# still configured for the markdown channel gets nothing written. Before
# hf7y/realisateur#293 this call CREATED $GEN, re-growing a retired file in a
# repo that had none. PROJECT_REPO_PATH is deliberately not a git repo.
mkdir -p "$TMP/root/schedule" "$TMP/proj"
ln -s "$ROOT/bin" "$TMP/root/bin"
ln -s "$ROOT/lib" "$TMP/root/lib"
printf 'scheduler|1|3\n' > "$TMP/root/schedule/_paced.conf"
{ echo "PROJECT_REPO_PATH=\"$TMP/proj\""; echo 'SCHEDULER_SUBDIR=".scheduler"'; } \
  > "$TMP/root/schedule/witnessproj.conf"
GEN="$TMP/proj/.scheduler/QUESTIONS.md"
SCHED_ROOT="$TMP/root" SCHEDULER_ASK_VIA="questions-contract-witness" \
  "$ROOT/bin/scheduler" ask witnessproj "Does a file-channel project still get a QUESTIONS.md?" \
  > "$TMP/ask.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then ok "\`scheduler ask\` exits non-zero on a file-channel project"
else bad "\`scheduler ask\` exited 0 on a file-channel project -- output: $(head -3 "$TMP/ask.out")"; fi
if [ ! -e "$GEN" ]; then ok "no QUESTIONS.md was created"
else bad "\`scheduler ask\` re-grew a retired file at $GEN"; fi
if grep -qi 'retired' "$TMP/ask.out"; then ok "the refusal says why (retired channel)"
else bad "the refusal does not explain itself: $(head -3 "$TMP/ask.out")"; fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
