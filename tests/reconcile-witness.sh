#!/usr/bin/env bash
# Witness for reconcile_prior_cycles() -- exercises the two real failure
# modes it was written against, plus the three ways it must decline.
# Runs against throwaway git repos, never the real scheduler checkout.
set -uo pipefail

SRC="/home/zach/Documents/Project Archive/scheduler/bin/scheduler-dev-cycle.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Pull the function's own bytes out of the script under test, so the test
# exercises shipped code rather than a copy that can drift from it.
FUNC="$(awk '/^reconcile_prior_cycles\(\) \{/,/^\}/' "$SRC")"
[ -n "$FUNC" ] || { echo "could not extract function"; exit 1; }
eval "$FUNC"

# merge_mode() is a collaborator of the function under test -- take its real
# bytes too rather than reimplementing it, or the test drifts from the code.
MM="$(grep '^merge_mode() {' "$SRC")"
[ -n "$MM" ] || { echo "could not extract merge_mode"; exit 1; }
eval "$MM"
# Guard against the harness bug this test already caught once: an undefined
# collaborator made every case fall down the merge_mode="" path and two
# cases PASSED for the wrong reason.
type merge_mode >/dev/null 2>&1 || { echo "merge_mode not defined"; exit 1; }

JOB_NAME="test-job"
notify-send() { :; }   # never fire a real desktop notification from a test

# Build: a bare "origin", a clone, and a paced/<date> branch holding work
# that main does not have. Mirrors the real 2026-07-26 shape.
new_fixture() {
  local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/repo" 2>/dev/null
  cd "$d/repo" || exit 1
  git config user.email t@t; git config user.name t
  echo base > f.txt; git add f.txt; git commit -qm base
  git push -q origin main 2>/dev/null || { git branch -M main; git push -q origin main; }
  SCHED_REPO="$d/repo"
  STATE_DIR="$d/state"; mkdir -p "$STATE_DIR"
  MERGE_MODE_FILE="$STATE_DIR/merge_mode"
  LOG="$d/log"
}
stranded_branch() {  # $1 = branch, $2 = file to add (unique -> no conflict)
  git checkout -q -b "$1"
  echo "$2" > "$2"; git add "$2"; git commit -qm "work on $1"
  git checkout -q main
}

echo "== 1. stranded unmerged branch, clean tree -> merged AND pushed"
new_fixture t1
stranded_branch paced/2026-07-25 alpha.txt
out="$(reconcile_prior_cycles 2>&1)"
git merge-base --is-ancestor paced/2026-07-25 main 2>/dev/null \
  && ok "branch is now an ancestor of main" || bad "branch NOT merged"
[ "$(git rev-list --count origin/main..main)" -eq 0 ] \
  && ok "pushed: main level with origin" || bad "not pushed (main still ahead)"
grep -q "MERGED paced/2026-07-25" <<<"$out" && ok "reported the merge" || bad "no merge line: $out"

echo "== 2. merged locally but never pushed (the CRITICAL dead end) -> pushed"
new_fixture t2
echo more >> f.txt; git commit -qam "local-only commit"   # main ahead, unpushed
[ "$(git rev-list --count origin/main..main)" -eq 1 ] || bad "fixture wrong"
out="$(reconcile_prior_cycles 2>&1)"
[ "$(git rev-list --count origin/main..main)" -eq 0 ] \
  && ok "the unpushed commit reached origin" || bad "still unpushed"
grep -q "ahead of origin/main -- pushing" <<<"$out" && ok "named the retry" || bad "no push line: $out"

echo "== 3. dirty tree -> declines, and says nothing is orphaned"
new_fixture t3
stranded_branch paced/2026-07-25 beta.txt
echo dirt > uncommitted.txt   # a human mid-edit
out="$(reconcile_prior_cycles 2>&1)"
grep -q "SKIPPED" <<<"$out" && ok "skipped on a dirty tree" || bad "did not skip: $out"
grep -q "Retried next cycle" <<<"$out" && ok "states it will retry" || bad "no retry promise"
git merge-base --is-ancestor paced/2026-07-25 main 2>/dev/null \
  && bad "merged into a dirty tree -- must not" || ok "left the tree alone"

echo "== 4. conflicting branch -> aborts, main UNCHANGED, marker written once"
new_fixture t4
git checkout -q -b paced/2026-07-25
echo theirs > f.txt; git commit -qam "conflicting edit"
git checkout -q main
echo ours > f.txt; git commit -qam "our edit"; git push -q origin main
before="$(git rev-parse main)"
out="$(reconcile_prior_cycles 2>&1)"
[ "$(git rev-parse main)" = "$before" ] && ok "main unchanged after conflict" || bad "main MOVED on conflict"
[ -z "$(git status --porcelain)" ] && ok "no merge left in progress" || bad "conflicted tree left behind"
grep -q "CONFLICT merging paced/2026-07-25" <<<"$out" && ok "reported the conflict" || bad "silent conflict: $out"
[ -f "$STATE_DIR/conflict-paced-2026-07-25" ] && ok "marker written" || bad "no marker"
out2="$(reconcile_prior_cycles 2>&1)"
grep -q "CONFLICT" <<<"$out2" && ok "still reports every cycle (debt stays visible)" || bad "went silent on 2nd run"

echo "== 5. merge_mode=branch (manual pause) -> does not reconcile"
new_fixture t5
stranded_branch paced/2026-07-25 gamma.txt
echo branch > "$MERGE_MODE_FILE"
out="$(reconcile_prior_cycles 2>&1)"
git merge-base --is-ancestor paced/2026-07-25 main 2>/dev/null \
  && bad "merged despite the manual pause" || ok "honoured merge_mode=branch"
grep -q "BY CHOICE" <<<"$out" && ok "distinguishes paused from broken" || bad "no by-choice line"

echo "== 6. multiple stranded branches -> both recovered, oldest first"
new_fixture t6
stranded_branch paced/2026-07-25 delta.txt
stranded_branch paced/2026-07-26 epsilon.txt
out="$(reconcile_prior_cycles 2>&1)"
git merge-base --is-ancestor paced/2026-07-25 main 2>/dev/null \
  && git merge-base --is-ancestor paced/2026-07-26 main 2>/dev/null \
  && ok "both branches recovered" || bad "not all recovered"
[ "$(grep -c 'MERGED paced/' <<<"$out")" -eq 2 ] && ok "reported both" || bad "wrong merge count"
o25="$(grep -n 'attempting merge' <<<"$out" | grep -c '')"
[ "$o25" -eq 2 ] && ok "attempted both" || bad "attempted $o25"

echo "== 7. REGRESSION: summary must not contradict a conflict it just reported"
# An earlier draft printed "nothing to reconcile" immediately after two
# CONFLICT lines, because the all-clear keyed only on merged_any/ahead.
new_fixture t7
git checkout -q -b paced/2026-07-25
echo theirs > f.txt; git commit -qam "conflicting edit"
git checkout -q main
echo ours > f.txt; git commit -qam "our edit"; git push -q origin main
out="$(reconcile_prior_cycles 2>&1)"
grep -q "CONFLICT" <<<"$out" && ok "conflict reported" || bad "no conflict line"
grep -q "nothing to reconcile" <<<"$out" \
  && bad "claimed 'nothing to reconcile' despite a conflict" \
  || ok "no false all-clear"
grep -q "STILL STRANDED" <<<"$out" && ok "summary names the stranded branch" || bad "no stranded summary"

echo
echo "==== reconcile witness: $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
