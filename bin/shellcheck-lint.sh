#!/usr/bin/env bash
# bin/shellcheck-lint.sh -- run shellcheck over this repository's own shell,
# and fail when a NEW class of finding appears in a file that did not have it.
#
# THE PATH PREFIX ON THE LINE ABOVE IS LOAD-BEARING, which is the silliest true
# sentence in this repository. A comment opening with the bare word
# `shellcheck` is parsed by shellcheck as a DIRECTIVE, so `# shellcheck-lint.sh
# -- ...` reads as the directive `-lint.sh`, which is invalid, which is
# SC1072/SC1073 -- two errors emitted by a file for stating its own name. Any
# file named shellcheck-* has to introduce itself with a path prefix or a
# different word, and the same applies to every comment line below.
#
# GUARD: is any shell file in this tree carrying a shellcheck finding it did not carry when the ratchet was last accepted?
# RUNNER: tests/shellcheck-lint-witness.sh
# GATE: default
#
# Ported from hf7y/realisateur (bin/shellcheck-lint.sh, PR #133/#136) per
# hf7y/scheduler#77. The MECHANISM is that file's; .shellcheckrc's disable
# list and bin/shellcheck-lint.ratchet were re-derived against this tree, not
# copied, because a disable list is a judgement about a specific codebase.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS AT ALL
#
# 14,743 lines of tracked bash in this repository, and until 2026-08-11
# ShellCheck had never once been RUN against them. It appeared in the tree
# only as inline `# shellcheck source=` and disable directives -- annotations
# written for a tool nobody invoked, and bin/overnight-dev.sh's own prompt
# tells the overnight agent to prefer changes verifiable with "shellcheck".
#
# This is also the repository that writes every other project's crontab and
# dispatches their work, as several different unix accounts, unattended. Its
# silent-failure surface is the whole estate's. The failure mode this repo
# documents most often -- the exit-0 no-op, the unguarded `cd`, the check that
# cannot see and says fine -- has shellcheck codes: SC2164, SC2181, SC2086,
# SC2115.
#
# The first run found 405 findings at default severity across 42 files (74 at
# the warning-and-above level the ratchet reads). Three were dangerous enough
# to fix in the same change: bin/overnight-dev.sh:88, :116 and
# bin/scheduler-dev-cycle.sh:339, all unguarded `cd` on the line before
# `git worktree remove --force`. The rest are held by the ratchet.
#
# ---------------------------------------------------------------------------
# WHY A RATCHET AND NOT A CONFORMANCE CHECK
#
# A check nobody expects to be green is a document with an exit code, and this
# estate has already priced what a permanently-red suite is worth. So the
# assertion is not "shellcheck is clean". It is "no file has acquired a
# finding it did not have". bin/shellcheck-lint.ratchet records the
# (file, code) pairs that existed when it was last accepted; anything outside
# that set is a regression and exits 1.
#
# WHY (file, code) AND NOT (file, line, code) OR A COUNT.
#   A COUNT is gameable in the direction that matters: fix one finding, add
#   another, and the number is unchanged while the tree got worse in a new
#   place.
#   A LINE NUMBER is noise: inserting a comment at the top of a file
#   invalidates every entry for it, so the ratchet would need re-accepting on
#   edits that changed nothing, and re-accepting on autopilot is how a
#   baseline stops being read.
#   (file, code) is stable under edits and still catches the thing worth
#   catching -- a file acquiring a KIND of defect it did not have.
#
# ---------------------------------------------------------------------------
# WHAT IT REFUSES TO DO
#
# It never reports "I could not look" as "nothing is wrong". shellcheck
# missing from PATH is BLIND (exit 2), never success. Matching zero files is
# BLIND for the same reason: a lint that lints nothing reports success in
# exactly the voice of a lint that found nothing wrong.
#
# It never lowers the ratchet. `--accept` writes the CURRENT set, which is how
# a baseline is supposed to move, but a run that would REMOVE nothing and ADD
# entries still reports what it added, so accepting is a visible act rather
# than a quiet one.
#
# usage:  shellcheck-lint.sh [--strict] [--accept] [--quiet]
# exit:   0 no new findings   1 REGRESSION (a new file/code pair)
#         2 BLIND (shellcheck absent, or zero files matched -- never success)
#         3 --strict and the baseline is non-empty (no regression)
set -uo pipefail

# ROOT is derived from this script's OWN location and is deliberately NOT
# `${SCHED_ROOT:-...}` like the rest of bin/. Two reasons, both load-bearing:
# tests/shellcheck-lint-witness.sh copies this file into throwaway fixture
# repos and relies on the copy linting the fixture it sits in; and a guard
# whose target can be redirected by an inherited environment variable is a
# guard that can be pointed at a clean tree by accident.
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
RATCHET="$ROOT/bin/shellcheck-lint.ratchet"

STRICT=0; ACCEPT=0; QUIET=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --accept) ACCEPT=1 ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help)
      sed -n '/^# usage:/,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'
      exit 0 ;;
    *) echo "shellcheck-lint.sh: unknown flag '$a'" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

# Runtime witness -- record that this check actually RAN, so a
# built-but-unwired check fails loud in `scheduler sweep` instead of looking
# clean (lib/check-witness.sh + bin/check-witness-lint.sh, which globs
# bin/*-lint.sh and would otherwise report this file NEVER RUN forever).
# First act, before any early exit: a check that came back BLIND still ran.
# Never fatal, and guarded by -r so a copy of this guard sitting in a fixture
# with no lib/ still works -- that is what the witness depends on.
if [ -r "$ROOT/lib/check-witness.sh" ]; then
  source "$ROOT/lib/check-witness.sh"
  check_witness "$(basename "${BASH_SOURCE[0]}")"
fi

command -v shellcheck >/dev/null 2>&1 || {
  echo "BLIND: shellcheck is not on PATH -- this guard could not look." >&2
  echo "  install: apt-get install shellcheck, or drop the static binary from" >&2
  echo "  https://github.com/koalaman/shellcheck/releases onto PATH." >&2
  echo "  A guard that cannot probe does not get to report success." >&2
  exit 2
}

# WHICH FILES. Tracked-only, so an untracked scratch script in the working
# tree cannot turn the guard red, and a deleted one cannot keep it red. The
# corollary is a trap worth knowing: this guard CANNOT SEE ITSELF until it is
# committed, so an uncommitted guard reads clean while carrying errors.
#
# `*.sh` misses the extensionless executables in bin/ -- bin/scheduler and
# bin/scheduler-run -- so those are selected by SHEBANG rather than by name.
# Reading the file is the only honest way to ask "is this shell". The scan is
# limited to bin/ because that is where every extensionless shell file in this
# tree lives; verified 2026-08-11 by shebang-scanning all 105 tracked files
# and finding bin/scheduler, bin/scheduler-run and bin/scheduler-completion.bash
# and nothing outside bin/.
#
# Nothing is excluded. realisateur's copy skips archive/; this repository has
# no retired-code directory, and examples/*.sh are live templates that get
# copied into real jobs, so they are exactly what wants linting.
cd "$ROOT" || { echo "BLIND: cannot cd to $ROOT" >&2; exit 2; }

mapfile -t FILES < <(
  {
    git ls-files '*.sh' 2>/dev/null
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      case "$(head -c 2 "$f" 2>/dev/null)" in
        '#!') head -1 "$f" | grep -qE '^#!.*(bash|sh)\b' && printf '%s\n' "$f" ;;
      esac
    done < <(git ls-files 'bin/*' 2>/dev/null | grep -v '\.ratchet$')
  } | sort -u
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "BLIND: matched zero shell files under $ROOT -- this run linted NOTHING." >&2
  echo "  A lint that lints nothing is not a clean tree; it is a broken glob." >&2
  exit 2
fi

# CURRENT set: "path<TAB>SCNNNN", one per distinct pair, sorted.
# The tool's own exit status is deliberately ignored here (it is non-zero
# whenever there is any finding at all, which is the normal state of a
# ratcheted tree); the FINDINGS are the signal, and an empty output with
# the linter present is a genuinely clean tree.
#
# -S warning: style and info findings are not ratcheted. In this tree that is
# 331 of the 405 first-run findings, dominated by SC2015 (247) -- see
# .shellcheckrc for why that class is left visible to hand-runs rather than
# disabled or baselined.
current="$(
  shellcheck -f gcc -S warning "${FILES[@]}" 2>/dev/null \
  | sed -nE 's|^([^:]+):[0-9]+:[0-9]+: [a-z]+: .* \[(SC[0-9]+)\]$|\1\t\2|p' \
  | sort -u
)"

baseline=""
[ -f "$RATCHET" ] && baseline="$(grep -v '^#' "$RATCHET" | grep -v '^[[:space:]]*$' | sort -u)"

# VERSION SKEW. A ratchet is a comparison, and comparing findings across two
# linter versions compares two different questions: releases add checks,
# retire them, and change wording. A baseline accepted under one version can
# therefore show phantom regressions under another, and the reader's first
# guess will be that their branch broke something.
#
# This is not hypothetical: 0.9.0 flags a comment line beginning with the bare
# word `shellcheck` as a malformed directive and 0.10.0 does not, so the same
# file is clean under one and carries two errors under the other. It cost
# realisateur an evening (hf7y/realisateur#136) before the version was
# recorded here.
#
# It WARNS rather than fails. Failing would break CI the moment a runner image
# is bumped, which is a change nobody here made and cannot fix from this repo
# -- a guard that goes red for that is a guard that gets disabled. A genuine
# skew still surfaces, loudly, as the first thing said on the regression path.
SC_VERSION="$(shellcheck --version 2>/dev/null | awk '/^version:/{print $2}')"
SC_ACCEPTED=""
[ -f "$RATCHET" ] && SC_ACCEPTED="$(awk '/^# shellcheck-version /{print $3}' "$RATCHET")"
SC_SKEW=0
if [ -n "$SC_ACCEPTED" ] && [ -n "$SC_VERSION" ] && [ "$SC_ACCEPTED" != "$SC_VERSION" ]; then
  SC_SKEW=1
fi

new="$(comm -23 <(printf '%s\n' "$current" | grep -v '^$' | sort -u) \
                <(printf '%s\n' "$baseline" | grep -v '^$' | sort -u))"
gone="$(comm -13 <(printf '%s\n' "$current" | grep -v '^$' | sort -u) \
                 <(printf '%s\n' "$baseline" | grep -v '^$' | sort -u))"

n_cur=$(printf '%s\n' "$current" | grep -c . || true)
n_new=$(printf '%s\n' "$new" | grep -c . || true)
n_gone=$(printf '%s\n' "$gone" | grep -c . || true)

say "shellcheck-lint: ${#FILES[@]} tracked shell files, $n_cur baselined finding(s)."
if [ "$SC_SKEW" -eq 1 ]; then
  say "  note: running shellcheck $SC_VERSION; ratchet was accepted with $SC_ACCEPTED."
fi

if [ "$n_gone" -gt 0 ]; then
  say ""
  say "FIXED since the ratchet was accepted ($n_gone) -- run --accept to lock these in:"
  printf '%s\n' "$gone" | grep . | sed 's/^/  - /' | { [ "$QUIET" -eq 1 ] && cat >/dev/null || cat; }
fi

if [ "$ACCEPT" -eq 1 ]; then
  {
    echo "# shellcheck-lint.ratchet -- (file, code) pairs present when accepted."
    echo "# Raised or lowered ONLY by --accept, and --accept always reports what it"
    echo "# changed. See bin/shellcheck-lint.sh for why the pair, not a count."
    echo "# accepted $(date -Is)"
    echo "# shellcheck-version ${SC_VERSION:-unknown}"
    printf '%s\n' "$current" | grep . || true
  } > "$RATCHET"
  say ""
  say "ACCEPTED: $RATCHET now records $n_cur pair(s) (+$n_new new, -$n_gone fixed)."
  exit 0
fi

if [ "$n_new" -gt 0 ]; then
  echo ""
  if [ "$SC_SKEW" -eq 1 ]; then
    echo "READ THIS FIRST: shellcheck $SC_VERSION is running, but the ratchet was" >&2
    echo "accepted with $SC_ACCEPTED. Findings below may be that difference rather" >&2
    echo "than anything your branch did. Check against $SC_ACCEPTED before fixing." >&2
    echo "" >&2
  fi
  echo "REGRESSION: $n_new shellcheck finding(s) in files that did not have them." >&2
  printf '%s\n' "$new" | grep . | sed 's/^/  + /' >&2
  echo "" >&2
  # The advice below deliberately does NOT spell the directive literally.
  # Writing it out in this file would BE a directive as far as shellcheck is
  # concerned, with an invalid code -- which is SC1072/SC1073, the exact
  # defect the header paragraph warns about.
  echo "Fix them, or -- if the finding is deliberate and you can say why in the" >&2
  echo "code -- add an inline shellcheck disable directive naming the code, with" >&2
  echo "the reason beside it, and re-run. '--accept' is for a baseline move you" >&2
  echo "intend, not for a red run." >&2
  exit 1
fi

say "no new findings."

if [ "$STRICT" -eq 1 ] && [ "$n_cur" -gt 0 ]; then
  say ""
  say "--strict: $n_cur finding(s) still baselined. The tree is not clean, it is"
  say "held. bin/shellcheck-lint.ratchet lists every one."
  exit 3
fi
exit 0
