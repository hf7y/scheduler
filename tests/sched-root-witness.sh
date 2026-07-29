#!/usr/bin/env bash
# Witness for bin/scheduler's SCHED_ROOT resolution.
#
# The bug this exists to prevent is a glance that FAILS OPEN: until
# 2026-07-29 SCHED_ROOT was a bare hardcoded path into mandark's checkout,
# so on dexter (no /home/zach/Documents at all) the source of
# lib/autonomy-merge.sh failed, every SCHED_ROOT read below it resolved to
# nothing, and `scheduler` printed an EMPTY project table and exited 0.
# An unreadable world rendered as a clean one, which is exactly the
# "no exit-0 no-ops" row of this repo's build discipline.
#
# Two things must hold, and the second is the one that rots first:
# the right checkout is found on any host, AND when no checkout can be
# found the tool REFUSES instead of printing a comfortable blank.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/scheduler"
[ -f "$SRC" ] || { echo "script under test not found: $SRC"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Running bin/scheduler outright would run the whole glance, so lift just the
# resolution block out of it by its markers. If the extraction stops matching,
# that is a failure -- never a pass by absence.
BLOCK="$TMP/block.sh"
awk '/^# >>> SCHED_ROOT resolution/,/^# <<< SCHED_ROOT resolution/' "$SRC" > "$BLOCK"
grep -q 'SELF_REPO' "$BLOCK" \
  || { echo "FAIL: could not extract the SCHED_ROOT block from $SRC"; exit 1; }
grep -q 'exit 1' "$BLOCK" \
  || { echo "FAIL: extracted block has no refusal path -- it can still fail open"; exit 1; }

# The block's third step is mandark's absolute path, which EXISTS on mandark
# and does not on dexter -- so the refusal cases would assert different things
# depending on where the suite runs. Neutralise exactly that one constant to a
# guaranteed-absent path, and prove the substitution landed rather than
# assuming it: an unmatched sed here would silently re-host-couple the test.
FALLBACK='/home/zach/Documents/Project Archive/scheduler'
grep -qF "\"$FALLBACK\"" "$BLOCK" \
  || { echo "FAIL: the documented fallback constant is gone from the block"; exit 1; }
NOBLOCK="$TMP/block-nofallback.sh"
sed "s|\"$FALLBACK\"|\"$TMP/definitely-absent\"|" "$BLOCK" > "$NOBLOCK"
grep -qF "$TMP/definitely-absent" "$NOBLOCK" \
  || { echo "FAIL: fallback substitution did not apply"; exit 1; }

# Materialise the block as a REAL script at a REAL path. This matters: an
# earlier draft sourced the block instead, and BASH_SOURCE -- maintained by
# the shell, not assignable -- then pointed at the block itself, so every
# case fell down the fallback path and three of them PASSED for the wrong
# reason. Invoking a file is the only way to exercise self-location honestly.
stub() {  # $1 = destination path, $2 = block to embed
  mkdir -p "$(dirname "$1")"
  { printf '#!/usr/bin/env bash\nset -uo pipefail\n'
    cat "$2"
    printf 'echo "RESOLVED=$SCHED_ROOT"\n'; } > "$1"
  chmod +x "$1"
}
make_repo() {  # $1 = dir, $2 = block
  mkdir -p "$1/bin" "$1/lib"
  : > "$1/.git"                       # a worktree's .git is a FILE, not a dir
  : > "$1/bin/usage-paced-runner.sh"  # the repo-unique marker
  stub "$1/bin/scheduler" "$2"
}

echo "== 1. symlink install -> resolves to the real checkout, not the symlink"
make_repo "$TMP/checkout" "$BLOCK"
mkdir -p "$TMP/localbin"
ln -sfn "$TMP/checkout/bin/scheduler" "$TMP/localbin/scheduler"
out="$("$TMP/localbin/scheduler" 2>&1)"
[ "$out" = "RESOLVED=$TMP/checkout" ] \
  && ok "followed the symlink home ($TMP/checkout)" || bad "got: $out"

echo "== 2. run straight out of the checkout -> that checkout"
out="$("$TMP/checkout/bin/scheduler" 2>&1)"
[ "$out" = "RESOLVED=$TMP/checkout" ] && ok "self-located" || bad "got: $out"

echo "== 3. THE REGRESSION: no checkout anywhere -> refuses, does NOT exit 0"
# A copied-not-symlinked install sitting outside any repo, on a host where
# the fallback path does not exist. This is the dexter case, exactly.
stub "$TMP/orphan/bin/scheduler" "$NOBLOCK"
out="$("$TMP/orphan/bin/scheduler" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "non-zero exit (rc=$rc)" || bad "exited 0 on an unreadable world"
grep -q 'cannot locate the scheduler checkout' <<<"$out" \
  && ok "says it cannot find the repo" || bad "silent: $out"
grep -q 'tried SCHED_ROOT=' <<<"$out" \
  && ok "names the path it tried" || bad "does not name what it tried"
grep -q 'RESOLVED=' <<<"$out" && bad "carried on past an unresolvable root" \
  || ok "stopped instead of continuing with a bad root"

echo "== 4. a stray PARENT git repo is not mistaken for the checkout"
# .git present, marker absent -- the case the marker file exists to reject.
mkdir -p "$TMP/stray"; : > "$TMP/stray/.git"
[ -e "$TMP/stray/.git" ] || { echo "FAIL: fixture has no .git -- case 4 would pass without testing anything"; exit 1; }
stub "$TMP/stray/bin/scheduler" "$NOBLOCK"
out="$("$TMP/stray/bin/scheduler" 2>&1)"
grep -q "RESOLVED=$TMP/stray" <<<"$out" \
  && bad "adopted a git repo that is not the scheduler checkout" \
  || ok "rejected a .git without the marker file"

echo "== 5. the third step really is the documented fallback path"
# Same shape as case 4 but with the REAL constant, so the fallback is proven
# to be used rather than merely present in a comment.
mkdir -p "$TMP/stray2"; : > "$TMP/stray2/.git"
stub "$TMP/stray2/bin/scheduler" "$BLOCK"
out="$("$TMP/stray2/bin/scheduler" 2>&1)"
grep -qF "$FALLBACK" <<<"$out" \
  && ok "fell back to the documented path" || bad "fallback not exercised: $out"

echo "== 6. an explicit SCHED_ROOT override wins over self-location"
make_repo "$TMP/elsewhere" "$BLOCK"
out="$(SCHED_ROOT="$TMP/elsewhere" "$TMP/checkout/bin/scheduler" 2>&1)"
[ "$out" = "RESOLVED=$TMP/elsewhere" ] \
  && ok "honoured the override" || bad "ignored SCHED_ROOT: $out"

echo "== 7. an override pointing at a NON-checkout still refuses"
# The override says WHERE the repo is; it is not a way to skip the check.
out="$(SCHED_ROOT="$TMP/nope" "$TMP/checkout/bin/scheduler" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refused a bogus override (rc=$rc)" || bad "trusted a bogus override"
grep -q "tried SCHED_ROOT=$TMP/nope" <<<"$out" \
  && ok "names the bogus override in the refusal" || bad "did not name it: $out"

echo
echo "==== sched-root witness: $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
