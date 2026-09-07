#!/usr/bin/env bash
set -uo pipefail  # HERMETIC: a throwaway git repo under mktemp, stub gh from fixtures
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../bin/clone-benched-check.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "clone-benched-check-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

git -C "$W" init -q -b main --bare origin.git
git -C "$W" clone -q "$W/origin.git" "$W/repo"
REPO="$W/repo"
git -C "$REPO" config user.email t@t.example
git -C "$REPO" config user.name benched-witness
echo a > "$REPO/a.txt"; git -C "$REPO" add a.txt; git -C "$REPO" commit -q -m init
git -C "$REPO" push -q origin HEAD:main

cat > "$W/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "repo view" ] && { echo main; exit 0; }
echo "stub gh: unexpected args: $*" >&2
exit 1
STUB
chmod +x "$W/gh"

run() { BENCHED_GH_BIN="$W/gh" bash "$B" "$REPO" 2>&1; }

echo "-- 1. on the default branch"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "on main is clean" || bad "exited $rc, want 0: $out"

echo "-- 2. off default, upstream still exists"
git -C "$REPO" checkout -qb feature
git -C "$REPO" push -q -u origin feature
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok "a live upstream branch is clean" || bad "exited $rc, want 0: $out"

echo "-- 3. off default, upstream merged and deleted (the wtul shape)"
git -C "$W" -C origin.git update-ref -d refs/heads/feature
out="$(run)"; rc=$?
[ "$rc" -eq 2 ] && ok "a vanished upstream is BENCHED (rc=$rc)" || bad "exited $rc, want 2: $out"
grep -q "BENCHED" <<<"$out" && ok "reported as BENCHED" || bad "no BENCHED line: $out"

echo "-- 4. off default, no upstream configured at all"
git -C "$REPO" checkout -qb orphan
out="$(run)"; rc=$?
[ "$rc" -eq 2 ] && ok "no upstream configured is BENCHED (rc=$rc)" || bad "exited $rc, want 2: $out"

echo "-- 5. not a git repo"
out="$(BENCHED_GH_BIN="$W/gh" bash "$B" "$W" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && ok "a non-repo path is BROKEN, not silently clean" || bad "exited $rc, want 3: $out"

printf '\nclone-benched-check-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
