#!/usr/bin/env bash
# Witness for bin/debroussaille.sh (hf7y/scheduler#37). Hermetic: builds a
# real throwaway git repo (bare "origin" + clone) under mktemp, a fake
# fauche on PATH, and points reports at a scratch dir -- never the live
# estate. See bin/debroussaille.sh's own header for the full spec.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/debroussaille.sh"

echo "debroussaille-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "debroussaille-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/fauche" <<'EOF'
#!/usr/bin/env bash
echo "KEEP          fake-fauche-verdict-for-$2"
exit 0
EOF
chmod +x "$FAKEBIN/fauche"
export PATH="$FAKEBIN:$PATH"

export DEBROUSSAILLE_REPORTS_ROOT="$WORK/reports"

# --- fixture: a bare "origin" and a clone with merged + unmerged branches,
# and worktrees -- one clean & recoverable, one dirty. -----------------------
git -C "$WORK" init -q -b main --bare origin.git
git -C "$WORK" clone -q "$WORK/origin.git" "$WORK/repo"
REPO="$WORK/repo"
git -C "$REPO" config user.email t@t.example
git -C "$REPO" config user.name debroussaille-witness
echo a > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -q -m init
git -C "$REPO" push -q origin HEAD:main
git -C "$WORK" -C origin.git symbolic-ref HEAD refs/heads/main 2>/dev/null \
  || git -C "$WORK/origin.git" symbolic-ref HEAD refs/heads/main

git -C "$REPO" checkout -q -b merged-branch
echo b > "$REPO/b.txt"
git -C "$REPO" add b.txt
git -C "$REPO" commit -q -m "fully merged, safe to clear"
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q merged-branch
git -C "$REPO" push -q origin main
# merged-branch is deliberately left lying around (not deleted here) -- it
# is exactly the debris debroussaille.sh exists to clear.

git -C "$REPO" checkout -q -b local-only-branch
echo c > "$REPO/c.txt"
git -C "$REPO" add c.txt
git -C "$REPO" commit -q -m "never merged, never pushed -- must survive"
git -C "$REPO" checkout -q main

git -C "$REPO" worktree add -q --detach "$WORK/wt-clean" origin/main
git -C "$REPO" worktree add -q --detach "$WORK/wt-dirty" origin/main
echo dirty > "$WORK/wt-dirty/dirty.txt"

# --- 1. usage/flags -----------------------------------------------------
out="$("$TARGET" --bogus-flag 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "unknown flag exits 2 (usage)" || bad "unknown flag exited $rc, want 2: $out"

out="$("$TARGET" "$WORK/nowhere-empty-dir-xyz" 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && ok "a named path that is not a git repo yields BROKEN (nothing found to scan)" \
  || bad "non-repo path exited $rc, want 5: $out"

# --- 2. --check mode: reports what it WOULD do, mutates nothing ------------
before_branches="$(git -C "$REPO" branch --format='%(refname:short)' | sort)"
before_wt="$(git -C "$REPO" worktree list --porcelain | sort)"
out="$("$TARGET" --check "$REPO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--check exits 0" || bad "--check exited $rc: $out"
grep -q "would clear 1 merged branch(es): merged-branch" <<<"$out" \
  && ok "--check identifies the fully-merged branch as clearable" \
  || bad "--check output missing the merged-branch finding: $out"
grep -q "would clear 1 worktree(s): $WORK/wt-clean" <<<"$out" \
  && ok "--check identifies the clean/recoverable worktree as clearable" \
  || bad "--check output missing the clean-worktree finding: $out"
grep -q "wt-dirty (dirty)" <<<"$out" \
  && ok "--check keeps the dirty worktree, names why" \
  || bad "--check output does not explain why the dirty worktree survives: $out"
after_branches="$(git -C "$REPO" branch --format='%(refname:short)' | sort)"
after_wt="$(git -C "$REPO" worktree list --porcelain | sort)"
[ "$before_branches" = "$after_branches" ] && ok "--check left every branch byte-for-byte in place" \
  || bad "--check MUTATED branches -- this is the most important test in the file"
[ "$before_wt" = "$after_wt" ] && ok "--check left every worktree in place" \
  || bad "--check MUTATED worktrees -- this is the most important test in the file"

# --- 3. --apply mode: clears the provably-safe items, keeps the rest -------
out="$("$TARGET" --apply "$REPO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--apply exits 0" || bad "--apply exited $rc: $out"
grep -q "cleared 1 merged branch(es): merged-branch" <<<"$out" \
  || bad "--apply did not report clearing the merged branch: $out"
if ! git -C "$REPO" branch --format='%(refname:short)' | grep -qxF merged-branch; then
  ok "--apply actually deleted the fully-merged local branch"
else
  bad "merged-branch still exists after --apply"
fi
if git -C "$REPO" branch --format='%(refname:short)' | grep -qxF local-only-branch; then
  ok "--apply left the unmerged local-only branch untouched"
else
  bad "--apply deleted local-only-branch -- it is NOT recoverable, this is data loss"
fi
if [ ! -d "$WORK/wt-clean" ]; then
  ok "--apply removed the clean/recoverable worktree"
else
  bad "clean worktree still on disk after --apply"
fi
if [ -d "$WORK/wt-dirty" ]; then
  ok "--apply left the dirty worktree on disk"
else
  bad "--apply removed the DIRTY worktree -- that would have lost uncommitted work"
fi
[ -d "$REPO/.git" ] && ok "--apply never deletes the repository itself" \
  || bad "the repository itself is gone -- debroussaille must never do this"

# --- 4. residue report is written, not just printed -------------------------
LATEST="$WORK/reports/debroussaille/LATEST.md"
[ -L "$LATEST" ] && ok "LATEST.md published as a symlink (publish-report.sh's contract)" \
  || bad "no LATEST.md symlink at $LATEST after a run"
grep -q "fake-fauche-verdict-for-$REPO" "$LATEST" 2>/dev/null \
  && ok "the published report carries fauche's own verdict for the repo" \
  || bad "published report is missing fauche's verdict: $(cat "$LATEST" 2>&1)"

echo
echo "debroussaille-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
