#!/usr/bin/env bash
# Witness for lib/autonomy-merge.sh -- the squash-merge predicate bug from
# hf7y/scheduler#146.
#
# `ahead=$(git rev-list --count "$default_branch..$branch")` is right for
# ff/no-ff integration and STRUCTURALLY WRONG for squash-merge: a squash
# merge puts a new commit on default_branch whose diff equals the branch's
# cumulative diff but does not contain the branch's own commits as
# ancestors, so `ahead` never returns to 0 for a branch that already
# landed. Observed live on realisateur@monkey: the same already-shipped
# branch got re-merged and CRITICALed on a non-fast-forward push every 2h,
# four dispatches straight.
#
# Case 2 is the one that must never go green by accident: a fix that makes
# EVERY branch look "already landed" (e.g. by breaking the ahead-count check
# itself) would pass case 1 too if case 1 didn't exist.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/autonomy-merge.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# shellcheck source=../lib/autonomy-merge.sh
. "$LIB"
type autonomy_sweep_repo >/dev/null 2>&1 \
  || { echo "lib did not define autonomy_sweep_repo"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fresh() {
  cd "$TMP" || exit 1   # never rm -rf the shell's own cwd
  rm -rf "$TMP/origin.git" "$TMP/work" "$TMP/squasher"
  git init -q --bare -b main "$TMP/origin.git"
  git clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
  cd "$TMP/work" || exit 1
  echo base > file.txt
  git add file.txt && git commit -q -m base && git push -q -u origin main
}

echo "== 1. REGRESSION: a branch genuinely ahead still gets merged and pushed"
fresh
git -C "$TMP/work" checkout -q -b feature
echo hello > "$TMP/work/x.txt"
git -C "$TMP/work" add x.txt && git -C "$TMP/work" commit -q -m "add x"
git -C "$TMP/work" checkout -q main
out="$(autonomy_sweep_repo "$TMP/work" main high "" test 2>&1)"
echo "$out" | grep -q "MERGED and PUSHED" && ok "genuinely-ahead branch was merged and pushed" \
  || bad "genuinely-ahead branch was NOT merged: $out"
git -C "$TMP/origin.git" cat-file -e "refs/heads/main:x.txt" 2>/dev/null \
  && ok "x.txt reached origin/main" || bad "x.txt never reached origin"

echo "== 2. THE ONE THAT MUST NOT GO GREEN BY ACCIDENT: squash-merged branch is skipped, not re-merged"
fresh
git -C "$TMP/work" checkout -q -b feature
echo hello > "$TMP/work/x.txt"
git -C "$TMP/work" add x.txt && git -C "$TMP/work" commit -q -m "add x, unsquashed"
git -C "$TMP/work" checkout -q main

# Simulate GitHub's squash merge: a THIRD clone lands the same net diff as
# ONE new commit on origin/main, with no ancestry relationship to `feature`
# at all -- exactly what a squash-and-merge produces.
git clone -q "$TMP/origin.git" "$TMP/squasher" 2>/dev/null
echo hello > "$TMP/squasher/x.txt"
git -C "$TMP/squasher" add x.txt
git -C "$TMP/squasher" commit -q -m "add x (#1)"
git -C "$TMP/squasher" push -q origin main
squash_sha="$(git -C "$TMP/squasher" rev-parse main)"

out="$(autonomy_sweep_repo "$TMP/work" main high "" test 2>&1)"
echo "$out" | grep -q "already landed" && ok "squash-landed branch recognized and skipped" \
  || bad "squash-landed branch was NOT recognized: $out"
echo "$out" | grep -q "MERGED and PUSHED" && bad "squash-landed branch was re-merged anyway: $out" \
  || ok "squash-landed branch was not re-merged"
echo "$out" | grep -q "CRITICAL" && bad "the false-positive CRITICAL fired: $out" \
  || ok "no CRITICAL fired"
[ "$(git -C "$TMP/origin.git" rev-parse main)" = "$squash_sha" ] \
  && ok "origin/main unchanged -- no extra merge commit pushed on top of the squash" \
  || bad "origin/main moved past the squash commit"

echo "== 3. a branch with SOME of its content already squashed in, plus real new work, still merges the new part"
fresh
git -C "$TMP/work" checkout -q -b feature
echo hello > "$TMP/work/x.txt"
git -C "$TMP/work" add x.txt && git -C "$TMP/work" commit -q -m "add x"
echo world > "$TMP/work/y.txt"
git -C "$TMP/work" add y.txt && git -C "$TMP/work" commit -q -m "add y, never squashed"
git -C "$TMP/work" checkout -q main

git clone -q "$TMP/origin.git" "$TMP/squasher" 2>/dev/null
echo hello > "$TMP/squasher/x.txt"
git -C "$TMP/squasher" add x.txt
git -C "$TMP/squasher" commit -q -m "add x (#1)"
git -C "$TMP/squasher" push -q origin main

out="$(autonomy_sweep_repo "$TMP/work" main high "" test 2>&1)"
echo "$out" | grep -q "MERGED and PUSHED" \
  && ok "branch with a real un-landed commit on top of a squashed one still merges" \
  || bad "branch with genuine new work was wrongly skipped: $out"
git -C "$TMP/origin.git" cat-file -e "refs/heads/main:y.txt" 2>/dev/null \
  && ok "y.txt (the un-landed part) reached origin/main" || bad "y.txt never reached origin"

cd /
echo
echo "autonomy-merge-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
