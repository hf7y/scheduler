#!/usr/bin/env bash
set -uo pipefail  # HERMETIC: a throwaway git repo under mktemp, stub gh from fixtures
HERE="$(cd "$(dirname "$0")" && pwd)"
U="$HERE/../bin/unlanded-work-check.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "unlanded-work-check-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

git -C "$W" init -q -b main --bare origin.git
git -C "$W" clone -q "$W/origin.git" "$W/repo"
REPO="$W/repo"
git -C "$REPO" config user.email t@t.example
git -C "$REPO" config user.name unlanded-witness
echo a > "$REPO/a.txt"; git -C "$REPO" add a.txt; git -C "$REPO" commit -q -m init
git -C "$REPO" push -q origin HEAD:main
git -C "$W/origin.git" symbolic-ref HEAD refs/heads/main
git -C "$REPO" remote set-head origin -a >/dev/null 2>&1

cat > "$W/gh" <<'STUB'  # GH_DEFAULT_BRANCH answers repo view; GH_PR_COUNT="b=n ..." answers pr list
#!/usr/bin/env bash
if [ "$1 $2" = "repo view" ]; then
  echo "${GH_DEFAULT_BRANCH:-main}"
  exit 0
fi
if [ "$1 $2" = "pr" ]; then :; fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  head=""
  prev=""
  for a in "$@"; do
    [ "$prev" = "--head" ] && head="$a"
    prev="$a"
  done
  for pair in $GH_PR_COUNT; do
    b="${pair%%=*}"; n="${pair#*=}"
    if [ "$b" = "$head" ]; then echo "$n"; exit 0; fi
  done
  echo 0
  exit 0
fi
echo "stub gh: unexpected args: $*" >&2
exit 1
STUB
chmod +x "$W/gh"

run() { GH_DEFAULT_BRANCH="${1:-main}" GH_PR_COUNT="${2:-}" UNLANDED_GH_BIN="$W/gh" bash "$U" "$REPO" 2>&1; }

echo "-- 1. a genuinely clean repo"
out="$(run main '')"; rc=$?
[ "$rc" -eq 0 ] && ok "a repo with origin/HEAD correct and no stray branches is clean" || bad "exited $rc: $out"

echo "-- 2. stale cached origin/HEAD"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop 2>/dev/null \
  || git -C "$REPO" update-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
out="$(run main '')"; rc=$?
[ "$rc" -eq 2 ] && ok "a stale cached origin/HEAD is caught (rc=$rc)" || bad "exited $rc, want 2: $out"
grep -q "DRIFT" <<<"$out" && ok "the stale-HEAD case is reported as DRIFT" || bad "no DRIFT line: $out"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

echo "-- 3. a branch with commits and no PR at all"
git -C "$REPO" checkout -q -b stray-branch
echo b > "$REPO/b.txt"; git -C "$REPO" add b.txt; git -C "$REPO" commit -q -m "never opened a PR"
git -C "$REPO" checkout -q main
out="$(run main '')"; rc=$?
[ "$rc" -eq 2 ] && ok "a branch with commits and no PR is caught (rc=$rc)" || bad "exited $rc, want 2: $out"
grep -q "UNLANDED: branch 'stray-branch'" <<<"$out" && ok "names the stray branch" || bad "did not name it: $out"

echo "-- 4. same branch, but a PR (CLOSED) names it -> not flagged"
out="$(run main 'stray-branch=1')"; rc=$?
[ "$rc" -eq 0 ] && ok "a branch a PR names in ANY state is not flagged (squash-merge case)" || bad "exited $rc, want 0: $out"

echo "-- 5. a salvage/* branch is excluded even with no PR"
git -C "$REPO" branch -D stray-branch >/dev/null 2>&1
git -C "$REPO" checkout -q -b salvage/crash-recovery-1
echo c > "$REPO/c.txt"; git -C "$REPO" add c.txt; git -C "$REPO" commit -q -m "dirty workspace snapshot"
git -C "$REPO" checkout -q main
out="$(run main '')"; rc=$?
[ "$rc" -eq 0 ] && ok "a salvage/* branch is excluded from the unlanded check" || bad "exited $rc, want 0: $out"

echo "-- 6. the checked-out branch itself is never flagged"
git -C "$REPO" branch -D salvage/crash-recovery-1 >/dev/null 2>&1
git -C "$REPO" checkout -q -b in-progress
echo d > "$REPO/d.txt"; git -C "$REPO" add d.txt; git -C "$REPO" commit -q -m "still being worked on"
out="$(run main '')"; rc=$?
[ "$rc" -eq 0 ] && ok "the currently checked-out branch is never flagged mid-work" || bad "exited $rc, want 0: $out"
git -C "$REPO" checkout -q main

printf '\nunlanded-work-check-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
