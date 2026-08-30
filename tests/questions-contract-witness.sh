#!/usr/bin/env bash
# Witness for the ANSWER CONTRACT (rules A-D, 2026-07-29).
#
# What the contract is: a reply is the most authoritative input this system
# takes, and until 2026-07-29 the only one with NO admission control -- an
# answer was simply obeyed. The failure that names the gap is a question
# asked from a STALE PREMISE, so a correct reply directs action at a world
# that no longer exists. Rules A-D authorize the actor to notice that,
# without demoting the answer.
#
# Why a witness and not prose: the rules are prose, and prose decays. They
# have ONE home now -- the issue body `scheduler ask` writes, read by both
# the person answering and the actor acting on the answer. Absence there is
# a silent hole, so it is a FAILURE here, never a pass.
#
# Two other homes are gone. `examples/QUESTIONS.md.template` was copied into
# every new project until #66 (2026-08-07) retired the channel and
# hf7y/realisateur#293 deleted it -- section 2 asserts the REFUSAL that
# replaced it, because a re-grown QUESTIONS.md in a repo that had none is the
# failure the sunset exists to stop. `examples/nightly-batch.md.template` held
# a second copy for scaffolded projects; hf7y/realisateur#744 holds that
# procedure once instead, so the six assertions pinning it went with it -- one
# copy cannot drift from itself. A fourth block covered bin/questions-lint.sh,
# retired with the rest of the QUESTIONS.md machinery (#234).
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

echo '== 2. `scheduler ask` REFUSES the retired file channel'
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
