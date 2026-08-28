#!/usr/bin/env bash
# carry.sh -- the actuator tests/carry-drift-witness.sh never had (#315).
#
# DERIVED, NOT LISTED, because the detector is: the carried set is "tracked on
# both refs under bin/ and lib/", read here from the same refs, so the two
# cannot disagree about what a carry is. A carries.tsv would be a second
# definition of one fact -- what #210 refuses -- and carried path equals source
# path here, so it would add nothing.
#
# IT MOVES PATHS, NEVER THE BRANCH: realisateur's hand fix for this defect ran
# `git push origin main:bashified` and deleted 13 bashified-only files.
set -uo pipefail

CLI_NAME='carry.sh'
CLI_SUMMARY='copy each carried file from main onto bashified, and nothing else'
CLI_USAGE='  carry.sh            print which carried files have drifted
  carry.sh --check    the same; writes nothing (default)
  carry.sh --apply    build one commit on bashified carrying every drifted file'

HERE="${CARRY_REPO:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)}"
REF_MAIN="${CARRY_REF_MAIN:-origin/main}"
REF_BASH="${CARRY_REF_BASH:-origin/bashified}"
BRANCH="${CARRY_BRANCH:-bashified}"
REMOTE="${CARRY_REMOTE:-origin}"

die()   { printf '%s: FAIL: %s\n' "$CLI_NAME" "$*" >&2; exit 1; }
blind() { printf '%s: BLIND: %s\n' "$CLI_NAME" "$*" >&2; exit 6; }
usage() { printf '%s: %s\n' "$CLI_NAME" "$*" >&2; printf 'usage:\n%s\n' "$CLI_USAGE" >&2; exit 2; }

MODE=--check
for a in "$@"; do
  case "$a" in
    --check|--apply) MODE="$a" ;;
    -h|--help) printf '%s -- %s\nusage:\n%s\n' "$CLI_NAME" "$CLI_SUMMARY" "$CLI_USAGE"; exit 0 ;;
    *) usage "unknown argument $a" ;;
  esac
done

cd "$HERE" || die "cannot enter $HERE"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

# THE REPO AND THE REFS MUST BE OVERRIDDEN TOGETHER. Refs come from the
# environment, the REPO from this file's own location. In realisateur those
# disagreed in silence: a suite set the fixture's refs and not CARRY_REPO, so
# the script resolved the REAL repo, pushed a REAL carry, and reported success.
if [ -z "${CARRY_REPO:-}" ]; then
  for v in CARRY_REMOTE CARRY_BRANCH CARRY_REF_MAIN CARRY_REF_BASH; do
    [ -z "${!v:-}" ] || usage "$v is set but CARRY_REPO is not.
  Those name where to WRITE and where to READ; setting one without the other
  points this at a repo you did not mean. Set CARRY_REPO too."
  done
fi

# REFRESH BOTH REFS FIRST: a stale origin/bashified reports drift that was
# already carried, and a stale origin/main carries yesterday's content.
git fetch -q "$REMOTE" main "$BRANCH" 2>/dev/null || true
for r in "$REF_MAIN" "$REF_BASH"; do
  git rev-parse --verify -q "$r^{commit}" >/dev/null 2>&1 \
    || blind "$r is not readable here -- refusing to carry against a ref I cannot see"
done

carried="$(comm -12 \
  <(git ls-tree -r --name-only "$REF_MAIN"  -- bin/ lib/ | sort) \
  <(git ls-tree -r --name-only "$REF_BASH" -- bin/ lib/ | sort))"
[ -n "$carried" ] || blind "no file is tracked on both refs -- either nothing is carried, or the refs are wrong"

drifted=(); n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  [ "$(git rev-parse "$REF_BASH:$f")" = "$(git rev-parse "$REF_MAIN:$f")" ] || drifted+=("$f")
done <<< "$carried"

if [ "${#drifted[@]}" -eq 0 ]; then
  printf '%s: %d carried file(s), none drifted\n' "$CLI_NAME" "$n"
  exit 0
fi

printf '%s: %d of %d carried file(s) have drifted:\n' "$CLI_NAME" "${#drifted[@]}" "$n"
printf '  %s\n' "${drifted[@]}"
[ "$MODE" = --apply ] || { printf '%s: NOT carried (need --apply)\n' "$CLI_NAME"; exit 0; }

# PLUMBING, NOT A CHECKOUT. Read bashified's tree into a temp index, replace
# only the drifted paths, write it back -- no second worktree and no branch
# switch to fight whatever the caller has in flight.
OLD="$(git rev-parse "$REF_BASH")"
IDX="$(mktemp)"; trap 'rm -f "$IDX"' EXIT
GIT_INDEX_FILE="$IDX" git read-tree "$REF_BASH" || die "could not read $REF_BASH into a temp index"

for f in "${drifted[@]}"; do
  # The MODE comes from main's entry, so a carried script stays executable.
  mode="$(git ls-tree "$REF_MAIN" -- "$f" | awk '{print $1}')"
  [ -n "$mode" ] || die "no tree entry for $f on $REF_MAIN"
  GIT_INDEX_FILE="$IDX" git update-index --add \
    --cacheinfo "$mode,$(git rev-parse "$REF_MAIN:$f"),$f" || die "could not stage $f"
done

TREE="$(GIT_INDEX_FILE="$IDX" git write-tree)" || die "could not write the carried tree"
[ "$TREE" != "$(git rev-parse "$REF_BASH^{tree}")" ] || {
  printf '%s: the carried tree is identical -- nothing to push\n' "$CLI_NAME"; exit 0; }

MSG="carry: $(printf '%s ' "${drifted[@]}" | sed 's/ $//') from ${REF_MAIN#origin/}"
COMMIT="$(git commit-tree "$TREE" -p "$OLD" -m "$MSG")" || die "could not commit the carried tree"

# --force-with-lease against the sha we read, so a bashified that moved while
# we worked is a refusal rather than a silent overwrite.
git push -q "$REMOTE" "$COMMIT:refs/heads/$BRANCH" \
  --force-with-lease="refs/heads/$BRANCH:$OLD" \
  || die "push refused -- $BRANCH moved since $OLD was read. Re-run."
printf '%s: carried %d file(s) onto %s (%s)\n' "$CLI_NAME" "${#drifted[@]}" "$BRANCH" "${COMMIT:0:8}"
