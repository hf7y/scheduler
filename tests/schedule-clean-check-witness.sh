#!/usr/bin/env bash
# Witness for bin/schedule-clean-check.sh -- the committed-config gate
# extracted out of bin/sync-crontab.sh's --check-clean (hf7y/scheduler#471).
# bin/usage-paced-runner.sh's dispatch gate calls this script on its hot
# path, so its exit-code contract (0 clean, 2 dirty/unverifiable) is asserted
# against real git fixtures before anything is wired to it -- same reasoning
# as tests/consume-deploy-gate-witness.sh: a mock would only agree with
# itself.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GATE="$ROOT/bin/schedule-clean-check.sh"
[ -x "$REAL_GATE" ] || { echo "gate not found/executable: $REAL_GATE"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

git_q() { git -c init.defaultBranch=main -c user.email=w@w -c user.name=w "$@"; }

# The gate resolves its own SCHED_DIR from its own location (one dir above
# bin/), same as bin/sync-crontab.sh always did -- it checks the checkout it
# belongs to, not the caller's cwd. So each fixture repo gets its own copy
# under bin/, and "$GATE" is that copy, not $REAL_GATE.
install_gate() {  # $1 = repo root
  mkdir -p "$1/bin"
  cp "$REAL_GATE" "$1/bin/schedule-clean-check.sh"
  chmod +x "$1/bin/schedule-clean-check.sh"
}

# --- 1. clean tree: committed schedule/, nothing pending ---------------------
echo "== 1. schedule/ matches HEAD"
REPO="$TMP/clean"
git_q init -q "$REPO"
mkdir -p "$REPO/schedule"
echo "PROJECT=demo" > "$REPO/schedule/demo.conf"
install_gate "$REPO"
git_q -C "$REPO" add -A
git_q -C "$REPO" commit -qm seed
GATE="$REPO/bin/schedule-clean-check.sh"

out="$("$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exit 0 on a clean tree"
else bad "expected exit 0, got $rc: $out"; fi
if printf '%s' "$out" | grep -q 'schedule/ is clean'; then ok "reported clean"
else bad "missing 'clean' report: $out"; fi

# --- 2. dirty: a tracked schedule/*.conf modified but not committed ----------
echo "== 2. a tracked schedule/*.conf has an uncommitted edit"
echo "EXTRA=1" >> "$REPO/schedule/demo.conf"
out="$(cd "$REPO" && "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "exit 2 on a dirty tracked file"
else bad "expected exit 2, got $rc: $out"; fi
if printf '%s' "$out" | grep -q 'DIRTY:'; then ok "reported DIRTY"
else bad "missing DIRTY report: $out"; fi
git_q -C "$REPO" checkout -q -- schedule/demo.conf

# --- 3. dirty: an untracked schedule/*.conf (never committed at all) --------
echo "== 3. an untracked schedule/*.conf -- the worst case, not an exempt one"
echo "PROJECT=new" > "$REPO/schedule/new.conf"
out="$(cd "$REPO" && "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "exit 2 on an untracked conf"
else bad "expected exit 2, got $rc: $out"; fi
rm -f "$REPO/schedule/new.conf"

# --- 4. back to clean after the untracked file is gone -----------------------
echo "== 4. removing the untracked file restores clean"
out="$(cd "$REPO" && "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exit 0 again once the tree matches HEAD"
else bad "expected exit 0, got $rc: $out"; fi

# --- 5. unverifiable: not inside a git repository -----------------------------
echo "== 5. schedule/ exists but is not inside a git repo"
NOGIT="$TMP/nogit"
mkdir -p "$NOGIT/schedule"
echo "PROJECT=demo" > "$NOGIT/schedule/demo.conf"
install_gate "$NOGIT"
out="$("$NOGIT/bin/schedule-clean-check.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then ok "exit 2 outside a git repo"
else bad "expected exit 2, got $rc: $out"; fi
if printf '%s' "$out" | grep -q 'UNVERIFIABLE:'; then ok "reported UNVERIFIABLE"
else bad "missing UNVERIFIABLE report: $out"; fi

# --- 6. writes nothing, reads no crontab --------------------------------------
echo "== 6. the gate itself is read-only"
BEFORE="$(cd "$REPO" && git status --porcelain)"
(cd "$REPO" && "$GATE" >/dev/null 2>&1) || true
AFTER="$(cd "$REPO" && git status --porcelain)"
if [ "$BEFORE" = "$AFTER" ]; then ok "no files written by the gate itself"
else bad "gate mutated the tree: before=[$BEFORE] after=[$AFTER]"; fi

echo
echo "schedule-clean-check-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
