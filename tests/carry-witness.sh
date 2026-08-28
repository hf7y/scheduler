#!/usr/bin/env bash
# Witness for bin/carry.sh -- hermetic: every case builds a throwaway repo with
# a `main`, a `bashified` and a bare remote, and carry.sh is pointed at it with
# CARRY_REPO. Nothing here touches this repository or origin/bashified.
#
# WHAT MUST HOLD
#   1. no drift -> exit 0, and bashified does not move (an actuator that
#      commits on every run is a second writer, not a repair)
#   2. drift -> --check reports it and writes NOTHING; --apply moves bashified
#   3. --apply carries ONLY the drifted path. realisateur's hand fix for this
#      same defect ran `git push origin main:bashified` and deleted 13 files
#      bashified carries that main does not have -- the file below named
#      bashified-only.txt is that regression, in one line.
#   4. a file's executable bit survives the carry
#   5. setting CARRY_REMOTE/CARRY_BRANCH without CARRY_REPO is a usage error,
#      not a push into the real repo (realisateur, 2026-08-25)
#   6. an unreadable ref is BLIND (exit 6), never "none drifted"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/witness-common.sh"
CARRY="$HERE/../bin/carry.sh"
echo "carry-witness"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# fixture <name> -- a repo whose origin/main and origin/bashified share
# bin/carried.sh and lib/carried.sh, plus one bashified-only file. Echoes the
# work repo path.
fixture() {
  local d="$TMP/$1" bare="$TMP/$1.git"
  git init -q --bare "$bare"
  git init -q -b main "$d"
  git -C "$d" config user.email w@w.invalid; git -C "$d" config user.name w
  mkdir -p "$d/bin" "$d/lib"
  printf 'echo one\n' > "$d/bin/carried.sh"; chmod +x "$d/bin/carried.sh"
  printf 'echo lib\n' > "$d/lib/carried.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" remote add origin "$bare"; git -C "$d" push -q origin main
  git -C "$d" checkout -q -b bashified
  printf 'only on bashified\n' > "$d/bashified-only.txt"
  git -C "$d" add -A; git -C "$d" commit -qm bashified-extra
  git -C "$d" push -q origin bashified
  git -C "$d" checkout -q main
  git -C "$d" fetch -q origin
  printf '%s' "$d"
}
run() { CARRY_REPO="$1" CARRY_REMOTE=origin CARRY_BRANCH=bashified \
        CARRY_REF_MAIN=origin/main CARRY_REF_BASH=origin/bashified \
        bash "$CARRY" "${@:2}" 2>&1; }
drift() {   # drift <repo> <file> <content>
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add -A
  git -C "$1" commit -qm "drift $2"; git -C "$1" push -q origin main
  git -C "$1" fetch -q origin
}

echo "== 1. no drift is exit 0 and moves nothing"
d="$(fixture clean)"; before="$(git -C "$d" rev-parse origin/bashified)"
out="$(run "$d")"; rc=$?
[ "$rc" -eq 0 ] && ok "clean repo exits 0" || bad "clean repo exited $rc: $out"
case "$out" in *"none drifted"*) ok "says none drifted" ;; *) bad "no none-drifted wording: $out" ;; esac
out="$(run "$d" --apply)"
[ "$(git -C "$d" rev-parse origin/bashified)" = "$before" ] \
  && ok "--apply on a clean repo does not move bashified" \
  || bad "--apply moved bashified with nothing to carry"

echo "== 2. drift: --check reports and writes nothing, --apply carries"
d="$(fixture drifted)"; drift "$d" bin/carried.sh 'echo two'
before="$(git -C "$d" rev-parse origin/bashified)"
out="$(run "$d")"; rc=$?
[ "$rc" -eq 0 ] && ok "--check exits 0 (a report, not a failure)" || bad "--check exited $rc: $out"
case "$out" in *bin/carried.sh*) ok "names the drifted path" ;; *) bad "path not named: $out" ;; esac
case "$out" in *"NOT carried"*) ok "--check says it carried nothing" ;; *) bad "no NOT-carried wording: $out" ;; esac
[ "$(git -C "$d" rev-parse origin/bashified)" = "$before" ] \
  && ok "--check left bashified alone" || bad "--check pushed"
out="$(run "$d" --apply)"; rc=$?
[ "$rc" -eq 0 ] && ok "--apply exits 0" || bad "--apply exited $rc: $out"
git -C "$d" fetch -q origin
[ "$(git -C "$d" rev-parse origin/bashified)" != "$before" ] \
  && ok "--apply moved bashified" || bad "--apply did not push"
[ "$(git -C "$d" show origin/bashified:bin/carried.sh)" = "echo two" ] \
  && ok "bashified now ships main's content" || bad "carried content is wrong"

echo "== 3. it carries paths, never the branch"
git -C "$d" cat-file -e origin/bashified:bashified-only.txt 2>/dev/null \
  && ok "a bashified-only file survives the carry" \
  || bad "the carry deleted a file bashified had and main does not -- this is the 13-file bug"
[ "$(git -C "$d" show origin/bashified:lib/carried.sh)" = "echo lib" ] \
  && ok "an undrifted carried file is untouched" || bad "an undrifted file changed"
out="$(run "$d")"
case "$out" in *"none drifted"*) ok "a second run is a no-op" ;; *) bad "not idempotent: $out" ;; esac

echo "== 4. the executable bit survives"
[ "$(git -C "$d" ls-tree origin/bashified -- bin/carried.sh | awk '{print $1}')" = 100755 ] \
  && ok "bin/carried.sh is still mode 100755 on bashified" || bad "the carry dropped the executable bit"

echo "== 5. refs without a repo is a usage error, not a push somewhere else"
out="$(CARRY_REMOTE=origin bash "$CARRY" --apply 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "CARRY_REMOTE without CARRY_REPO exits 2" || bad "exited $rc, not 2: $out"
case "$out" in *CARRY_REPO*) ok "names the variable that is missing" ;; *) bad "unhelpful: $out" ;; esac

echo "== 6. an unreadable ref is BLIND, not agreement"
d="$(fixture blindcase)"
out="$(CARRY_REPO="$d" CARRY_REMOTE=origin CARRY_BRANCH=bashified \
       CARRY_REF_MAIN=origin/main CARRY_REF_BASH=origin/nope \
       bash "$CARRY" 2>&1)"; rc=$?
[ "$rc" -eq 6 ] && ok "a missing ref exits 6 (BLIND)" || bad "exited $rc, not 6: $out"
case "$out" in *BLIND*) ok "BLIND is stated, not just an exit code" ;; *) bad "no BLIND wording: $out" ;; esac

printf '\ncarry-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
