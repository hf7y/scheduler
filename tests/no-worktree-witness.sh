#!/usr/bin/env bash
# tests/no-worktree-witness.sh -- witness for bin/no-worktree-guard.sh, the
# guard that keeps `git worktree add` out of this repository's production
# paths (hf7y/scheduler#49).
#
# HERMETIC: every fixture is a throwaway git repo under mktemp -d, committed
# with a per-command identity, and the guard is pointed at it by its ROOT
# argument. Case R1 runs the guard over THIS checkout, which is a statement
# about the branch under test rather than about the host. Nothing here creates
# a worktree, reads $HOME, invokes crontab, or touches the network.
#
# THE LOAD-BEARING ASSERTION IS A2: a production file that gains a
# `git worktree add` must turn the guard RED. Everything else is scaffolding.
# A version of this witness without A2 would pass against a guard whose scan
# had been deleted, which is the exact regression it exists to catch. A2 is
# mutation-verified: with the FLAG line commented out of the guard, A2 (and
# only A2) goes red.
#
# The second is B2/B3. An allowlist that cannot rot is the only reason this
# guard uses one instead of a .ratchet, and those cases are what make that a
# property rather than a claim in a header.
#
# WHY A WITNESS AND NOT A bin/ CHECK WIRED INTO `scheduler sweep`: this guard
# gates a PULL REQUEST -- the moment a new creator would be introduced -- not a
# host. tests/run-all.sh is what CI's `suites` job runs, so putting it here is
# what makes it a gate rather than a script someone could run.
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
GUARD="$REPO/bin/no-worktree-guard.sh"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$*"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (output lacked '$3')" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1 (output contained '$3')" ;; *) ok "$1" ;; esac; }

[ -x "$GUARD" ] || { echo "FAIL: no executable guard at $GUARD"; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
G() { git -c user.email=t@t -c user.name=t -C "$1" "${@:2}"; }

mkfixture() { # <name> -- a repo with one ordinary production script in bin/
  local d="$T/$1"
  rm -rf "$d"; mkdir -p "$d/bin" "$d/tests"
  G "$d" init -q -b main .
  printf '#!/usr/bin/env bash\necho ordinary\n' > "$d/bin/plain.sh"
  G "$d" add -A >/dev/null; G "$d" commit -qm init >/dev/null
  printf '%s' "$d"
}
run() { out="$(bash "$GUARD" "$1" 2>&1)"; rc=$?; }

echo "== A. THE SCAN =="

# A1 -- a clean tree exits 0 AND prints a count. A guard whose clean output is
# silence cannot be told from one that never ran.
d="$(mkfixture clean)"; run "$d"
check "A1 a clean tree exits 0" "$rc" "0"
has   "A1 and reports zero"     "$out" "0 FLAG(s)"

# A2 -- THE REGRESSION.
d="$(mkfixture creator)"
printf '#!/usr/bin/env bash\ngit worktree add -b x "$T" main\n' > "$d/bin/creator.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm creator >/dev/null
run "$d"
check "A2 a production creator exits 1"   "$rc"  "1"
has   "A2 and names the file and line"    "$out" "bin/creator.sh:2"
has   "A2 and counts it"                  "$out" "1 FLAG(s)"

# A3 -- `git -C <dir> worktree add` is the form realisateur's half of this
# used; a pattern anchored on the bare command would have missed it.
d="$(mkfixture dashc)"
printf '#!/usr/bin/env bash\ngit -C "$R" worktree add -q "$W" bashified\n' > "$d/bin/creator.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm creator >/dev/null
run "$d"
check "A3 'git -C <dir> worktree add' is caught" "$rc" "1"

# A4 -- removal is the FIX. Both scripts in this repo still call
# `git worktree remove` and `git worktree prune` to clear registrations left by
# cycles that ran before the port, and a guard that reddened on cleanup would
# push an author to delete exactly that.
d="$(mkfixture remover)"
printf '#!/usr/bin/env bash\ngit worktree remove --force "$W"\ngit worktree prune\n' > "$d/bin/rm.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm rm >/dev/null
run "$d"
check "A4 worktree remove/prune is not a finding" "$rc" "0"

# A5 -- a COMMENT naming the command is not the command. Both ported scripts
# carry headers explaining what they used to do, and a guard that could not
# tell those apart would only be passable by deleting the explanation.
d="$(mkfixture commented)"
printf '#!/usr/bin/env bash\n# it used to run: git worktree add -b x "$T" main\necho no\n' > "$d/bin/c.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm c >/dev/null
run "$d"
check "A5 a comment naming the command is not a finding" "$rc" "0"

# A6 -- tests/ is exempt: a hermetic worktree under mktemp is correct usage.
d="$(mkfixture testtree)"
printf '#!/usr/bin/env bash\ngit -C "$T" worktree add -q "$T/side" side\n' > "$d/tests/x-witness.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm t >/dev/null
run "$d"
check "A6 tests/ is exempt" "$rc" "0"

# A7 -- and archive/, per bin/shellcheck-lint.sh's stated reasoning.
d="$(mkfixture archived)"; mkdir -p "$d/archive/old"
printf '#!/usr/bin/env bash\ngit worktree add -b x "$T" main\n' > "$d/archive/old/loop.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm a >/dev/null
run "$d"
check "A7 archive/ is exempt" "$rc" "0"

# A8 -- an UNTRACKED creator is not a finding: a scratch file in someone's
# working tree must not redden a shared gate.
d="$(mkfixture untracked)"
printf '#!/usr/bin/env bash\ngit worktree add -b x "$T" main\n' > "$d/bin/scratch.sh"
run "$d"
check "A8 an untracked creator is not a finding" "$rc" "0"

echo
echo "== B. THE ALLOWLIST CANNOT ROT =="

# B1 -- this repository's allowlist is EMPTY and the guard says so out loud,
# rather than printing nothing and leaving a reader to infer it.
run "$REPO"
has "B1 the real tree reports an empty allowlist" "$out" "allowlist is empty"

# B2 -- an entry that no longer matches is a FLAG. This is the rot an inline
# list would otherwise accumulate: the file gets fixed, the excuse stays, and
# the next real violation in it is pre-forgiven by a line nobody re-read.
d="$(mkfixture rotted)"
printf '#!/usr/bin/env bash\necho no worktrees here\n' > "$d/bin/was-a-creator.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm fixed >/dev/null
printf 'bin/was-a-creator.sh\tfixed long ago, entry never removed\n' > "$T/allow-rotted.tsv"
out="$(NO_WORKTREE_ALLOW_FILE="$T/allow-rotted.tsv" bash "$GUARD" "$d" 2>&1)"; rc=$?
check "B2 an entry that no longer matches is a finding" "$rc" "1"
has   "B2 and is named as stale" "$out" "stale allowlist"

# B3 -- an entry naming a file that is gone is equally stale.
printf 'bin/deleted-creator.sh\tthe file is gone\n' > "$T/allow-gone.tsv"
out="$(NO_WORKTREE_ALLOW_FILE="$T/allow-gone.tsv" bash "$GUARD" "$d" 2>&1)"; rc=$?
check "B3 an entry for a missing file is a finding" "$rc" "1"
has   "B3 and says so" "$out" "does not exist"

# B4 -- and a LIVE entry suppresses the finding it was written for, printing
# its reason. An excuse nobody can read is not an excuse.
d="$(mkfixture excused)"
printf '#!/usr/bin/env bash\necho "run: git worktree add -b x \$T main" >&2\n' > "$d/bin/advice.sh"
G "$d" add -A >/dev/null; G "$d" commit -qm advice >/dev/null
out="$(bash "$GUARD" "$d" 2>&1)"; rc=$?
check "B4 without an entry the mention is a finding" "$rc" "1"
printf 'bin/advice.sh\tprints the command, executes nothing\n' > "$T/allow-live.tsv"
out="$(NO_WORKTREE_ALLOW_FILE="$T/allow-live.tsv" bash "$GUARD" "$d" 2>&1)"; rc=$?
check "B4 with an entry it is excused" "$rc" "0"
has   "B4 and the reason is printed, not hidden" "$out" "executes nothing"

echo
echo "== C. IT REFUSES RATHER THAN REPORTS CLEAN =="

# C1 -- not a git tree is BLIND, exit 2. "Could not look" reported as "nothing
# wrong" is the pathology bin/blockers-freshness-check.sh's header records
# paying for.
mkdir -p "$T/notarepo"
out="$(cd "$T/notarepo" && bash "$GUARD" 2>&1)"; rc=$?
check "C1 a non-repo is BLIND, not clean" "$rc" "2"
has   "C1 and says BLIND" "$out" "BLIND"

# C2 -- and a repo with no tracked shell to scan. tests/run-all.sh exits 1 on
# "no witnesses found" for exactly this reason.
d="$T/emptyrepo"; mkdir -p "$d"
G "$d" init -q -b main . >/dev/null
printf 'x\n' > "$d/README.md"; G "$d" add -A >/dev/null; G "$d" commit -qm init >/dev/null
run "$d"
check "C2 a repo with no shell to scan is BLIND" "$rc" "2"
has   "C2 and says BLIND" "$out" "BLIND"

echo
echo "== R. THE REAL TREE =="

# R1 -- the assertion the pull request is making. Not a fixture: this
# checkout, today. If a later change reintroduces a creator, this is the line
# that goes red in `suites`.
run "$REPO"
check "R1 this checkout has no production worktree creator" "$rc" "0"
has   "R1 and the scan was not empty" "$out" "tracked shell file(s)"

# R2 -- and the scripts #49 names are still doing the work, in a clone. A
# guard passing because a script was deleted would be a different change
# than the one claimed -- true of bin/overnight-dev.sh, still checked below.
# bin/scheduler-dev-cycle.sh, #49's other named script, is gone: retired
# entirely rather than ported (hf7y/scheduler#190), so it is no longer a
# candidate worktree creator to check here at all.
for f in bin/overnight-dev.sh; do
  if [ -f "$REPO/$f" ] && grep -q 'git clone -q "\$SCHED_REPO" "\$DEV_CLONE"' "$REPO/$f"; then
    ok "R2 $f still runs its cycle, now in a clone"
  else
    bad "R2 $f does not clone into \$DEV_CLONE -- #49 was closed by deletion, not by port"
  fi
done

echo
printf 'no-worktree-witness: %d passed, %d failed\n' "$pass" "$fail"
exit $(( fail > 0 ? 1 : 0 ))
