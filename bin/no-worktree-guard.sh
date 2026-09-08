#!/usr/bin/env bash
# bin/no-worktree-guard.sh -- does any production script in this tree create a
# git worktree?
#
# GUARD: does any shell file outside tests/ name `git worktree add`?
# RUNNER: tests/no-worktree-witness.sh
# GUARD-TEST: tests/no-worktree-witness.sh
# GATE: default
#
# WHY THIS EXISTS (#49). Two production scripts here created a worktree on
# every run, a one-time cleanup did not hold, and the estate regrew them within
# days. Removing today's instances is not the fix -- the fix is that a third
# creator cannot appear without this going red.
#
# DETECTION IS TEXTUAL, deliberately. Telling `git worktree add` inside an echo
# from one for real is the per-case judgement that let two live here for
# months. A justified mention goes in the allowlist below, in a diff, with a
# reason. THE ALLOWLIST IS EMPTY, and that is the interesting fact.
#
# NOT SCANNED: tests/ (a mktemp worktree dropped on exit is correct usage),
# archive/ (retired code kept as evidence -- a guard that demands retired code
# be maintained gets disabled), and prose/conf, none of which can create one.
#
# AN ALLOWLIST, NOT A .ratchet. A ratchet suits a baseline expected to fall
# over months; this one is expected to be EMPTY, and a one-command accept-flow
# is how a new violation gets baselined by a run nobody reads. Compiled in, it
# cannot grow without a diff -- and check B fails on an entry that has stopped
# matching, which is the anti-rot half `--accept` would otherwise provide.
#
# PORTED, NOT PROPAGATED. realisateur carries the same mechanism with its own
# allowlist (#77's reasoning): what would propagate is the judgement about
# WHICH tree's paths are excused, not the scan. A shipped copy would name a
# file this repo lacks and report its own entry stale forever.
#
# THE NAME is not `*-lint.sh`, because check-witness-lint.sh scans those for a
# runtime witness and would report this NEVER RUN every sweep -- a true
# statement about the wrong sensor. CI's `suites` gates it, not `scheduler
# sweep`.
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
  echo "bin/overnight-dev.sh is the worked example."
  exit 1
fi
echo "0 FLAG(s) -- no production path in $ROOT names 'git worktree add'."
exit 0
