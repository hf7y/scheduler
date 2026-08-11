#!/usr/bin/env bash
# bin/no-worktree-guard.sh -- does any production script in this tree create a
# git worktree?
#
# GUARD: does any shell file outside tests/ name `git worktree add`?
# RUNNER: tests/no-worktree-witness.sh
# GUARD-TEST: tests/no-worktree-witness.sh
# GATE: default
# VERIFIED: 2026-08-11 via bash bin/no-worktree-guard.sh (37 files scanned, 0 FLAGs) and its witness
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# Zach, 2026-08-06: "we should not have any more worktrees after tonight."
# hf7y/scheduler#49 was filed the same evening, this repo's 8 linked worktrees
# were removed, and five days later the estate was back to 30. Nothing had
# gone wrong. Two production scripts here created one on every run:
#
#   bin/scheduler-dev-cycle.sh   `git worktree add -b paced/<date> ... main`
#   bin/overnight-dev.sh         one per cycle, up to MAX_CYCLES a night
#
# Both now work in a clone. Removing today's instances is not the fix, because
# 2026-08-06 already did exactly that and it did not hold. The fix is that a
# third creator cannot appear without this going red.
#
# ---------------------------------------------------------------------------
# WHAT IS AND IS NOT A VIOLATION
#
# DETECTION IS TEXTUAL, and deliberately so. Telling `git worktree add` inside
# an `echo` from one on its own is exactly the per-case judgement that let two
# of these live here for months. A justified mention goes in the allowlist
# below, in a diff, with a reason attached -- a smaller and more visible
# surface than a regex that tries to be clever about intent. The allowlist is
# EMPTY today and that is the interesting fact about this repository.
#
# tests/ is excluded. A worktree built under mktemp and dropped on exit is
# correct usage and is not what #49 is about; a witness that needs a linked
# worktree to have anything to assert about must stay writable.
#
# archive/ is excluded on bin/shellcheck-lint.sh's stated reasoning: it is
# retired code kept as evidence, and a guard that demands retired code be
# maintained is a guard that gets disabled.
#
# Markdown, schedule/*.conf and the RUN-MARKER are not scanned. None of them
# can create a worktree, several of them describe the historical arrangement
# on purpose, and folding prose in would make this un-passable on a
# technicality -- the failure mode CLAUDE.md's silence-audit row was scoped
# for.
#
# ---------------------------------------------------------------------------
# WHY AN INLINE ALLOWLIST AND NOT A .ratchet FILE
#
# bin/shellcheck-lint.ratchet is the right shape for a baseline of many
# findings expected to fall over months. This one is expected to be EMPTY, and
# a ratchet whose accept-flow is one command is a way for a new violation to be
# baselined by a run nobody reads. An allowlist compiled in cannot grow without
# an edit to this file appearing in a diff. It also cannot ROT: check B fails
# if an entry has stopped existing or stopped matching, which is the half
# `--accept` normally provides and the half that matters when the target is
# zero.
#
# ---------------------------------------------------------------------------
# A PORTED COPY, NOT A PROPAGATED ONE
#
# hf7y/realisateur carries bin/no-worktree-lint.sh, the same mechanism with a
# different allowlist. It is classified LOCAL there for the reason
# hf7y/scheduler#77 already gives about shellcheck-lint.sh: what would
# propagate is the judgement -- which paths in WHICH tree are excused -- not
# the scan. A shipped copy would carry realisateur's one entry, naming a file
# this repository does not have, and its own rot check would report that entry
# stale forever.
#
# THE NAME. Not `no-worktree-lint.sh`, because bin/check-witness-lint.sh scans
# `bin/*-lint.sh` and `bin/*-check.sh` for a runtime witness and would report
# this NEVER RUN on every sweep. That would be a true statement about the wrong
# sensor: this guard is gated by CI's `suites` job through
# tests/no-worktree-witness.sh, not by `scheduler sweep`, so a sweep-witness
# is not the thing that proves it ran.
#
# usage:  no-worktree-guard.sh [ROOT]
# exit:   0 clean   1 FLAGs   2 BLIND (not a git tree, or zero files scanned --
#         never reported as success)
set -uo pipefail

# Resolved from cwd, not from this script's own location: a guard that falls
# back to the checkout it lives in reports on the live estate when it is
# pointed at a tree, which is the defect this repository has paid for in
# bin/deploy-drift-check.sh's header and in lib/paced-conf.sh's.
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || {
  echo "BLIND: no git worktree root resolved from $PWD -- this guard could not look." >&2
  exit 2
}
cd "$ROOT" || { echo "BLIND: cannot cd to $ROOT" >&2; exit 2; }

# `git ... worktree add` with any flags between, so `git -C "$repo" worktree
# add` and the bare form both match, while `git worktree remove` and
# `git worktree prune` -- which DELETE registrations and are the fix, not the
# defect -- do not.
PATTERN='git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+worktree[[:space:]]+add'

# ALLOWLIST: allow <path> "<why>". Every entry must still match, or check B fails.
ALLOW_PATHS=()
ALLOW_WHY=()
allow() { ALLOW_PATHS+=("$1"); ALLOW_WHY+=("$2"); }

# Is this the tree the compiled allowlist was written for? Asked of the tree,
# not of $0: the guard is invoked by absolute path from witnesses and sandboxes
# that are not the repository under test. NO_WORKTREE_ALLOW_FILE overrides the
# compiled list with a TSV (<path><TAB><why>) so the rot check can be exercised
# against a fixture instead of by breaking the real tree. Unset, which is how
# CI runs it, the compiled list is the only list.
SELF_REL="bin/no-worktree-guard.sh"
ALLOW_APPLIES=0
if [ -n "${NO_WORKTREE_ALLOW_FILE:-}" ]; then
  ALLOW_APPLIES=1
  while IFS=$'\t' read -r _p _w; do
    [ -n "${_p:-}" ] || continue
    case "$_p" in \#*) continue ;; esac
    allow "$_p" "${_w:-no reason recorded}"
  done < "$NO_WORKTREE_ALLOW_FILE"
elif git ls-files --error-unmatch "$SELF_REL" >/dev/null 2>&1; then
  ALLOW_APPLIES=1
  # Deliberately empty. Both creators became clones on 2026-08-11 and nothing
  # in this repository's production paths needs excusing. An entry appearing
  # here is a decision, and it will be visible as one.
fi

# Excluded prefixes -- see the header for why each.
excluded() {
  case "$1" in
    tests/*|test/*|*/tests/*|*/test/*) return 0 ;;
    archive/*)                         return 0 ;;
    bin/no-worktree-guard.sh)          return 0 ;;
  esac
  return 1
}

# WHICH FILES. Tracked only, so an untracked scratch script cannot turn the
# guard red and a deleted one cannot keep it red. `*.sh` misses the
# extensionless executables in bin/ (bin/scheduler, bin/scheduler-run), so
# those are selected by SHEBANG -- the only honest way to ask "is this shell".
# Same selector as bin/shellcheck-lint.sh.
mapfile -t FILES < <(
  {
    git ls-files '*.sh' 2>/dev/null
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      case "$f" in *.sh|*.md|*.1|*.yml|*.yaml|*.json|*.tsv|*.conf) continue ;; esac
      head -c 2 "$f" 2>/dev/null | grep -q '^#!' && printf '%s\n' "$f"
    done < <(git ls-files 2>/dev/null)
  } | sort -u
)

SCANNED=(); for f in ${FILES[@]+"${FILES[@]}"}; do excluded "$f" || SCANNED+=("$f"); done

# Zero files is BLIND, never clean -- tests/run-all.sh exits 1 on "no witnesses
# found" for the same reason, and a guard that guards nothing is its twin.
if [ "${#SCANNED[@]}" -eq 0 ]; then
  echo "BLIND: no tracked shell file outside tests/ under $ROOT -- this guard scanned nothing."
  exit 2
fi

flags=0
echo "== A. NO PRODUCTION PATH CREATES A WORKTREE =="
echo "  root: $ROOT   scanned: ${#SCANNED[@]} tracked shell file(s)"

matches_of() {   # <file> -> "<lineno>:<line>" for each non-comment match
  grep -nE "$PATTERN" -- "$1" 2>/dev/null \
    | awk -F: '{ rest=substr($0, index($0,":")+1); sub(/^[0-9]+:/,"",rest);
                 line=rest; sub(/^[[:space:]]*/,"",line);
                 if (line !~ /^#/) print $0 }'
}

is_allowed() { local p="$1" i; for i in "${!ALLOW_PATHS[@]}"; do [ "${ALLOW_PATHS[$i]}" = "$p" ] && return 0; done; return 1; }

for f in "${SCANNED[@]}"; do
  hits="$(matches_of "$f")"
  [ -n "$hits" ] || continue
  if is_allowed "$f"; then continue; fi
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    echo "FLAG [creator] $f:${h%%:*} names 'git worktree add' in a production path"
    flags=$((flags + 1))
  done <<<"$hits"
done

echo
echo "== B. EVERY ALLOWLIST ENTRY STILL EARNS ITS PLACE =="
if [ "$ALLOW_APPLIES" -eq 0 ]; then
  echo "  not applicable -- $ROOT does not track $SELF_REL, so this guard's"
  echo "  allowlist is not about this tree and nothing here is stale by it"
elif [ "${#ALLOW_PATHS[@]}" -eq 0 ]; then
  echo "  allowlist is empty -- nothing to justify"
else
  for i in "${!ALLOW_PATHS[@]}"; do
    p="${ALLOW_PATHS[$i]}"
    if [ ! -f "$p" ]; then
      echo "FLAG [stale allowlist] $p is allowlisted but does not exist -- delete the entry"
      flags=$((flags + 1))
    elif [ -z "$(matches_of "$p")" ]; then
      echo "FLAG [stale allowlist] $p is allowlisted but no longer matches -- delete the entry"
      flags=$((flags + 1))
    else
      echo "  allowed $p -- ${ALLOW_WHY[$i]}"
    fi
  done
fi

echo
if [ "$flags" -gt 0 ]; then
  echo "$flags FLAG(s)."
  echo "A worktree is not forbidden because it is exotic. It is forbidden because"
  echo "the estate has already paid for one: gardien's garde.json lived only inside"
  echo "a worktree, a migration removed it, and no backup could be proved for days"
  echo "(hf7y/gardien#7). Clone into \$STATE_DIR and push the branch back instead --"
  echo "bin/scheduler-dev-cycle.sh is the worked example."
  exit 1
fi
echo "0 FLAG(s) -- no production path in $ROOT names 'git worktree add'."
exit 0
