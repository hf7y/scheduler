#!/usr/bin/env bash
# Witness for WHICH REFS carry-drift-witness.sh compares -- unobservable by
# running it here, where origin/main and origin/bashified are normally in sync.
# A and B are its two questions; C, D and E are the proof that exempting a PR
# from the first did not leave a detector which cannot fail. Hermetic: each case
# builds a throwaway repo with its own bare remote and runs the real witness in it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/witness-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "carry-drift-ref-witness"

CARRIED='SELF_DIR=x
. "$SELF_DIR/../lib/carried.sh"
echo v1'

fixture() {   # origin/main and origin/bashified carry bin/ and lib/carried.sh
  local d="$TMP/$1" bare="$TMP/$1.git"
  git init -q --bare "$bare"; git init -q -b main "$d"
  git -C "$d" config user.email w@w.invalid; git -C "$d" config user.name w
  mkdir -p "$d/bin" "$d/lib" "$d/docs" "$d/tests/lib"
  cp "$HERE/carry-drift-witness.sh" "$d/tests/"; cp "$HERE/lib/witness-common.sh" "$d/tests/lib/"
  printf '%s\n' "$CARRIED" > "$d/bin/carried.sh"
  printf 'echo lib\n' > "$d/lib/carried.sh"; printf 'docs\n' > "$d/docs/notes.md"
  git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" remote add origin "$bare"
  git -C "$d" push -q origin main; git -C "$d" push -q origin main:bashified
  git -C "$d" fetch -q origin; printf '%s' "$d"
}
edit() { printf '%s\n' "$3" > "$1/$2"; git -C "$1" add -A; git -C "$1" commit -qm edit; }
land() { edit "$@"; git -C "$1" push -q origin main; git -C "$1" fetch -q origin; }  # a merge whose carry never ran
propose() { git -C "$1" checkout -q -b pr 2>/dev/null; edit "$@"; }                  # what actions/checkout leaves at HEAD
verdict() { ( cd "$1" && GITHUB_EVENT_NAME="$2" bash tests/carry-drift-witness.sh ) >"$TMP/out" 2>&1; echo "$?"; }

echo "A. a PR touching a carried file, main and bashified in sync -- the deadlock"
d="$(fixture a)"; propose "$d" bin/carried.sh "$CARRIED
echo v2-fix"
[ "$(verdict "$d" pull_request)" = 0 ] && ok "PASSES: the PR's own edit is not drift the PR can fix" \
  || { bad "a PR editing a carried file still fails -- #367/#374 stay BLOCKED"; cat "$TMP/out"; }

echo "B. the dependency half still reads the PR's HEAD, not origin/main"
d="$(fixture b)"; printf 'echo new\n' > "$d/bin/newdep.sh"
propose "$d" bin/carried.sh "$CARRIED
. \"\$SELF_DIR/newdep.sh\""
[ "$(verdict "$d" pull_request)" = 1 ] && grep -q 'references bin/newdep.sh' "$TMP/out" \
  && ok "FAILS: a sibling bashified does not ship is caught before landing (#219)" \
  || { bad "#222's dependency check went blind -- it is reading origin/main again"; cat "$TMP/out"; }

echo "C. a push to main with real drift -- the outage this witness exists for"
d="$(fixture c)"; land "$d" lib/carried.sh 'echo lib-v2'
[ "$(verdict "$d" push)" = 1 ] && ok "FAILS: an uncarried main is still an outage on push" \
  || { bad "real drift went green on push -- the detector is inert"; cat "$TMP/out"; }

echo "D. a PR touching nothing carried, while main is uncarried"
d="$(fixture d)"; land "$d" lib/carried.sh 'echo lib-v2'; propose "$d" docs/notes.md 'unrelated'
[ "$(verdict "$d" pull_request)" = 1 ] && ok "FAILS: a PR is not exempt from a main that is already uncarried" \
  || { bad "the exemption leaked -- a real outage is invisible on every PR"; cat "$TMP/out"; }

echo "E. a PR touching a carried file WHILE main is uncarried -- no masking"
d="$(fixture e)"; land "$d" lib/carried.sh 'echo lib-v2'
propose "$d" bin/carried.sh "$CARRIED
echo v2-fix"
[ "$(verdict "$d" pull_request)" = 1 ] && grep -q 'lib/carried.sh DRIFTED' "$TMP/out" \
  && ok "FAILS on lib/carried.sh: touching a carried file does not buy an amnesty" \
  || { bad "a PR touching a carried file masked a real drift in another one"; cat "$TMP/out"; }

printf '\ncarry-drift-ref-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
