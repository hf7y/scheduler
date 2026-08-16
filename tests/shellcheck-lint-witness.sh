#!/usr/bin/env bash
# tests/shellcheck-lint-witness.sh -- witness for bin/shellcheck-lint.sh.
#
# THE WORD ON THE LINE ABOVE IS PREFIXED FOR A REASON: a comment opening with
# the bare word `shellcheck` is parsed by shellcheck as a DIRECTIVE, and
# `shellcheck-lint-witness.sh -- ...` reads as the invalid directive
# `-lint-witness.sh`, which is SC1072/SC1073. A file named shellcheck-*
# emitting two errors for stating its own name is a real thing that has
# happened in this estate more than once.
#
# HERMETICITY: builds a throwaway git repository per case, copies the guard
# into it, and points the guard at THAT root via its own `cd "$ROOT"` (ROOT is
# derived from the script's own location, so a copy in a fixture lints the
# fixture). It never reads this repository's files or ratchet, and it never
# runs shellcheck against this repository -- so a red tree here cannot make
# this witness lie in either direction. The BLIND case shims PATH to a
# directory holding only the binaries the guard needs MINUS the linter --
# rather than clearing PATH, which would also remove git and make the case
# pass for the wrong reason.
#
# THE LOAD-BEARING ASSERTIONS ARE C, D AND E.
#
# A ratchet whose regression path does not fire is a green light wired to
# nothing, and this estate has shipped that exact thing more than once: three
# guards tested a literal unexpanded `$HOME` so `silence-audit --strict` was
# never once passable, and a propagation pass that reached zero projects
# exited 0. So the cases that matter are not "it runs" -- they are:
#
#   C  a NEW (file, code) pair exits 1, and names the pair
#   D  shellcheck missing exits 2 (BLIND), NOT 0
#   E  matching zero shell files exits 2 (BLIND), NOT 0
#
# E is the one that looks like paranoia and is not. A lint that lints nothing
# reports success in exactly the voice of a lint that found nothing wrong, and
# tests/run-all.sh carries its own version of this check for the same reason.
#
# G and H are specific to this port. G asserts the self-containment claim the
# port rests on -- the guard runs in a repo with no lib/ and no .shellcheckrc.
# H asserts the ratchet records the shellcheck version it was accepted under,
# because the baseline is not comparable across releases and this repository
# has no CI step asserting the runner's version.
#
# SKIPS RATHER THAN FAILS when shellcheck is absent from the host -- except
# for case D, which needs it absent and is therefore the one case that always
# runs. A suite that goes red on a developer laptop for lacking a linter is a
# suite that gets commented out.
set -uo pipefail

GUARD="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)/bin/shellcheck-lint.sh"
[ -f "$GUARD" ] || { echo "guard under test not found: $GUARD"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
skipped=0
T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT

skip() { echo "  skip $1 -- $2"; skipped=$((skipped+1)); }
check() { # <name> <expected-exit> <actual-exit>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected exit $2, got $3"; fi
}

# Build a fixture repo with one shell file, and the guard copied inside it so
# the guard's own ROOT resolves to the fixture rather than to this repository.
# Deliberately NO lib/ and NO .shellcheckrc: the fixture is the proof that the
# guard is self-contained.
mkfixture() { # <dir> <script-content>
  local d="$1" content="$2"
  mkdir -p "$d/bin"
  cp "$GUARD" "$d/bin/shellcheck-lint.sh"
  printf '%s' "$content" > "$d/bin/subject.sh"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email t@test; git -C "$d" config user.name T
  git -C "$d" add -A 2>/dev/null
  git -C "$d" commit -qm fixture 2>/dev/null
}

HAVE_SC=0
command -v shellcheck >/dev/null 2>&1 && HAVE_SC=1

echo "--- shellcheck-lint guard ---"

# --- A: a clean tree with no ratchet is exit 0, not a crash ------------------
if [ "$HAVE_SC" -eq 1 ]; then
  mkfixture "$T/a" '#!/usr/bin/env bash
echo "nothing wrong here"
'
  rc=0; bash "$T/a/bin/shellcheck-lint.sh" --quiet >/dev/null 2>&1 || rc=$?
  check "A clean tree, no ratchet: exit 0" 0 "$rc"
else
  skip "A clean tree" "shellcheck absent"
fi

# --- B: --accept writes a ratchet recording the pair ------------------------
if [ "$HAVE_SC" -eq 1 ]; then
  mkfixture "$T/b" '#!/usr/bin/env bash
cd /tmp
echo hi
'
  bash "$T/b/bin/shellcheck-lint.sh" --accept --quiet >/dev/null 2>&1
  if grep -q 'SC2164' "$T/b/bin/shellcheck-lint.ratchet" 2>/dev/null; then
    ok "B --accept records the (file, code) pair"
  else
    bad "B --accept records the pair" "no SC2164 in the written ratchet"
  fi
  # and the accepted finding no longer counts as new
  rc=0; bash "$T/b/bin/shellcheck-lint.sh" --quiet >/dev/null 2>&1 || rc=$?
  check "B2 an accepted finding is not a regression" 0 "$rc"
else
  skip "B --accept" "shellcheck absent"
fi

# --- C: a NEW pair is a regression, exit 1, and is NAMED --------------------
# THE LOAD-BEARING CASE. Accept a baseline, then add a second file with a
# different defect, and require both the exit code and the report.
if [ "$HAVE_SC" -eq 1 ]; then
  mkfixture "$T/c" '#!/usr/bin/env bash
cd /tmp
echo hi
'
  bash "$T/c/bin/shellcheck-lint.sh" --accept --quiet >/dev/null 2>&1
  # The SAME code (SC2164) in a DIFFERENT file. That is the sharper test: the
  # ratchet keys on the PAIR, so this must be caught even though the code is
  # already baselined for subject.sh. A count-based baseline would also catch
  # it, but a code-only baseline would not, and this asserts which one is
  # implemented.
  printf '#!/usr/bin/env bash\ncd /var\necho second\n' > "$T/c/bin/second.sh"
  git -C "$T/c" add -A 2>/dev/null
  rc=0; out="$(bash "$T/c/bin/shellcheck-lint.sh" 2>&1)" || rc=$?
  check "C a new file/code pair: exit 1" 1 "$rc"
  if printf '%s' "$out" | grep -q 'second.sh'; then
    ok "C2 the regression report NAMES the new file"
  else
    bad "C2 regression names the file" "report did not mention second.sh"
  fi
  # the pre-existing baselined finding must NOT be re-reported as new
  if printf '%s' "$out" | grep -q '^  + .*subject.sh'; then
    bad "C3 baselined finding stays quiet" "subject.sh reported as new"
  else
    ok "C3 the baselined finding is not re-reported as new"
  fi
else
  skip "C regression path" "shellcheck absent"
fi

# --- D: shellcheck absent is BLIND (exit 2), never success -------------------
# ALWAYS RUNS. Needs shellcheck gone, so it builds a PATH holding the guard's
# other dependencies and nothing else. Clearing PATH entirely would remove git
# too and the guard would exit 2 for the wrong reason -- which would pass this
# assertion while proving nothing.
mkfixture "$T/d" '#!/usr/bin/env bash
echo fine
'
mkdir -p "$T/pathdir"
for b in git bash head grep sed sort comm mktemp date cat printf readlink dirname basename awk; do
  p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$T/pathdir/$b" 2>/dev/null
done
rc=0
PATH="$T/pathdir" bash "$T/d/bin/shellcheck-lint.sh" >/dev/null 2>&1 || rc=$?
check "D shellcheck absent: BLIND (exit 2), not 0" 2 "$rc"

# --- E: zero shell files is BLIND (exit 2), never success -------------------
if [ "$HAVE_SC" -eq 1 ]; then
  mkdir -p "$T/e/bin"
  cp "$GUARD" "$T/e/bin/shellcheck-lint.sh"
  git -C "$T/e" init -q 2>/dev/null
  git -C "$T/e" config user.email t@test; git -C "$T/e" config user.name T
  # A repo whose ONLY tracked file is a non-shell one. The guard's own copy is
  # left untracked on purpose: selection is tracked-only, so it must not count
  # itself and must therefore find nothing.
  printf 'not shell\n' > "$T/e/README.md"
  git -C "$T/e" add README.md 2>/dev/null
  git -C "$T/e" commit -qm fixture 2>/dev/null
  rc=0; bash "$T/e/bin/shellcheck-lint.sh" >/dev/null 2>&1 || rc=$?
  check "E zero shell files: BLIND (exit 2), not 0" 2 "$rc"
else
  skip "E zero files" "shellcheck absent"
fi

# --- F: --strict fails while findings remain baselined ----------------------
if [ "$HAVE_SC" -eq 1 ]; then
  rc=0; bash "$T/b/bin/shellcheck-lint.sh" --strict --quiet >/dev/null 2>&1 || rc=$?
  check "F --strict with a non-empty baseline: exit 3" 3 "$rc"
else
  skip "F --strict" "shellcheck absent"
fi

# --- G: the guard is SELF-CONTAINED -----------------------------------------
# Specific to this port. The claim that justified copying the guard here at
# all is that it derives its own ROOT from its own location and needs nothing
# else from the repository around it. Every fixture above is built without a
# lib/ or a .shellcheckrc, so the claim is already load-bearing; this asserts
# it out loud, and asserts the ROOT it picked is the FIXTURE's -- not this
# repository's, which is the way a fixture test silently starts measuring the
# wrong tree.
if [ "$HAVE_SC" -eq 1 ]; then
  [ -e "$T/a/lib" ] && bad "G fixture has no lib/" "the fixture grew a lib/, the case is void"
  [ -e "$T/a/.shellcheckrc" ] && bad "G fixture has no rc" "the fixture grew a .shellcheckrc"
  # Add a file that only the FIXTURE has, and require the guard to see it.
  printf '#!/usr/bin/env bash\ncd /etc\necho g\n' > "$T/a/bin/only-in-fixture.sh"
  git -C "$T/a" add -A 2>/dev/null
  rc=0; out="$(bash "$T/a/bin/shellcheck-lint.sh" 2>&1)" || rc=$?
  if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q 'only-in-fixture.sh'; then
    ok "G the copied guard lints the tree it SITS IN, with no lib/ and no rc"
  else
    bad "G self-contained" "expected exit 1 naming only-in-fixture.sh, got exit $rc"
  fi
else
  skip "G self-contained" "shellcheck absent"
fi

# --- H: the ratchet records the version it was accepted under ---------------
# A ratchet is a COMPARISON, and findings are not comparable across shellcheck
# releases -- 0.9.0 flags a comment line beginning with the bare word
# `shellcheck` as a malformed directive and 0.10.0 does not, so the same file
# is clean under one and carries two errors under the other. realisateur lost
# an evening to that (hf7y/realisateur#136). This repository has no CI step
# asserting the runner's version, so the pin living in the ratchet is the only
# record there is; a re-accept that dropped it would be invisible otherwise.
if [ "$HAVE_SC" -eq 1 ]; then
  if grep -q '^# shellcheck-version [0-9]' "$T/b/bin/shellcheck-lint.ratchet" 2>/dev/null; then
    ok "H --accept stamps the shellcheck version into the ratchet"
  else
    bad "H version stamp" "no '# shellcheck-version <n>' line in the written ratchet"
  fi
  REAL_RATCHET="$(dirname "$GUARD")/shellcheck-lint.ratchet"
  if [ ! -f "$REAL_RATCHET" ]; then
    bad "H2 committed ratchet is stamped" "no ratchet at $REAL_RATCHET"
  elif grep -q '^# shellcheck-version [0-9]' "$REAL_RATCHET"; then
    ok "H2 this repository's committed ratchet names its shellcheck version"
  else
    bad "H2 committed ratchet is stamped" "$REAL_RATCHET has no version line"
  fi
else
  skip "H version stamp" "shellcheck absent"
fi

echo "shellcheck-lint: $PASS passed, $FAIL failed, $skipped skipped"
[ "$FAIL" -eq 0 ]
