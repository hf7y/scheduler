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
# The fourth assertion block is the regression that this contract's own
# rollout caused and that must never come back: the rule bullets are
# `- **A. ...**`-shaped, which is exactly the shape `bin/questions-lint.sh`
# treats as an ENTRY, so the amended header produced 4 findings on a file
# holding one real question. A check that cries wolf per project, forever,
# is worse than no check -- so the lint learned that pre-`## ` preamble is
# header prose. Its fail-open guard is asserted right alongside, because
# "went quiet" and "found nothing" must stay distinguishable.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

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

echo "== 4. bin/questions-lint.sh: header prose is not an entry, and it did not go blind"
mkdir -p "$TMP/lint/questions" "$TMP/lint/lib"
cp "$ROOT/lib/check-witness.sh" "$TMP/lint/lib/" 2>/dev/null
run_lint() { SCHED_ROOT="$TMP/lint" bash "$ROOT/bin/questions-lint.sh" 2>&1; }

# (a) the generated file: one real question, and the rule bullets above the
#     first `## ` heading must be invisible to the lint.
rm -f "$TMP/lint/questions"/*.md
printf '# Questions\n\n- **A. Direction, not instruction.** header prose\n- **D. No clean-check reports.** header prose\n\n## Open\n\n- **Does header prose still lint clean?**  `q-abc123` 2026-07-29, via witness\n' \
  > "$TMP/lint/questions/witnessproj.md"
out="$(run_lint)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "generated header lints clean (was 4 false findings)"
else bad "generated header still produces findings (rc=$rc): $out"; fi
if printf '%s' "$out" | grep -q 'across 1 entr'; then
  ok "the one real question is still counted as an entry"
else
  bad "entry count wrong -- the lint may be skipping the whole file: $out"
fi

# (b) FAIL-OPEN GUARD: a legacy file with entries and NO heading at all must
#     still be linted from line 1. This is the assertion that keeps the fix
#     above from turning into "the check went quiet."
rm -f "$TMP/lint/questions"/*.md
printf '# Questions\n\n- **2026-07-01 (nightly): a hand-written entry**\n' \
  > "$TMP/lint/questions/headingless.md"
out="$(run_lint)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'leads with a date'; then
  ok "headingless legacy file is still linted from line 1"
else
  bad "hand-written entry in a headingless file was NOT flagged (rc=$rc): $out"
fi

# (c) header prose AND a real hand-written entry under `## Open`: skip the
#     prose, still catch the entry.
rm -f "$TMP/lint/questions"/*.md
printf '# Questions\n\n- **A. Direction, not instruction.** header prose\n\n## Open\n\n- **2026-07-01 (nightly): a hand-written entry**\n' \
  > "$TMP/lint/questions/withheading.md"
out="$(run_lint)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'leads with a date'; then
  ok "entry under \`## Open\` is still flagged when header prose precedes it"
else
  bad "hand-written entry under \`## Open\` was NOT flagged (rc=$rc): $out"
fi
if printf '%s' "$out" | grep -q 'across 1 entr'; then
  ok "the header-prose bullet is not counted as an entry"
else
  bad "header-prose bullet is still being counted as an entry: $out"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
