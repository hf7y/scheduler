#!/usr/bin/env bash
# carry-drift-witness.sh -- a script carried onto `bashified` must be
# byte-identical to the one on `main`.
#
# THE HAZARD THE CARRY MODEL CREATES. hf7y/scheduler#123 moved freeze-check.sh,
# verdict.sh and usage-paced-runner.sh onto bashified so the verb build carries
# them and the dispatch path needs no checkout. That is right, and it means
# those files now exist TWICE, on two branches, with nothing holding them
# together.
#
# It bit within hours. #125 fixed a fail-OPEN in freeze-check.sh (a
# build-resident copy answered "not frozen" when it had no config, so the
# emergency abort handle was inert) and #126 fixed lib/dose-common.sh exiting
# its callers. Both landed on main. bashified kept the broken copies, the
# nightly cut shipped them, and every host adopted the version WITH the safety
# hole -- while main looked fixed and every test passed.
#
# A carried file is a deploy artifact. Drift between it and its source is the
# same defect class as realisateur's deploy-drift.sh, one branch over.
#
# DERIVED, NOT LISTED. The carried set is computed as "tracked on both
# branches" rather than hardcoded, so carrying a fourth script is covered the
# moment it lands instead of when someone remembers to add it here.
#
# hf7y/scheduler#222 added two things on top of the byte-identical check
# above: a carried file's OWN sibling references must resolve on the branch
# that ships it too (see the dependency check inside the loop below), and on
# a pull request the "main" side is the PR's proposed HEAD, not origin/main
# (see REF_MAIN below) -- comparing against origin/main is exactly why #219's
# broken carry passed its own PR and only went red on main after merging.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib/witness-common.sh"
cd "$HERE/.." || exit 2
echo "carry-drift-witness"

# origin/main, not main: a CI checkout has no local branches, and the fetch
# below writes into refs/remotes/origin/. Defaulting to the bare name made this
# fetch successfully and then go BLIND looking for a ref it had not created --
# caught by CI on this witness's own first run, which is the correct place for
# a check about deploy drift to be caught.
#
# ON A PULL REQUEST, though, origin/main does not yet carry the change under
# test -- actions/checkout for `pull_request` leaves HEAD at the PR's own
# content (GitHub's merge of the PR into its base), which is exactly "what
# main would look like if this merged". Diffing THAT against origin/bashified
# moves the failure to where it can be fixed before landing, instead of
# guaranteeing a red main the instant a carried file's PR merges (#222).
if [ -n "${CARRY_REF_MAIN:-}" ]; then
  REF_MAIN="$CARRY_REF_MAIN"
elif [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then
  REF_MAIN="HEAD"
else
  REF_MAIN="origin/main"
fi
REF_BASH="${CARRY_REF_BASHIFIED:-origin/bashified}"

# CI CHECKOUTS ARE SHALLOW. actions/checkout fetches the one ref under test, so
# origin/bashified is usually absent and this witness would go BLIND on every
# pull request -- and a witness that is permanently BLIND is one nobody reads,
# which is how the drift it exists to catch got shipped in the first place. Try
# to fetch what is missing before giving up. Quiet on success, and BLIND (never
# green) if the fetch cannot supply it either.
for r in "$REF_MAIN" "$REF_BASH"; do
  git rev-parse --verify -q "$r" >/dev/null 2>&1 && continue
  # Fetch into the SAME name being tested, or the check above still fails.
  b="${r#origin/}"
  git fetch -q --depth=1 origin "$b:refs/remotes/origin/$b" 2>/dev/null || true
done

for r in "$REF_MAIN" "$REF_BASH"; do
  git rev-parse --verify -q "$r" >/dev/null || {
    echo "  BLIND: ref '$r' is not readable here -- drift was NOT checked."
    echo "  A witness that cannot see both sides has not found them equal."
    printf '\ncarry-drift-witness: BLIND\n'; exit 2; }
done

carried="$(comm -12 \
  <(git ls-tree -r --name-only "$REF_MAIN"  -- bin/ lib/ | sort) \
  <(git ls-tree -r --name-only "$REF_BASH" -- bin/ lib/ | sort))"

[ -n "$carried" ] || { bad "no file is tracked on both refs -- either nothing is carried, or the refs are wrong"; \
  printf '\ncarry-drift-witness: %d passed, %d failed\n' "$PASS" "$((FAIL))"; exit 1; }

# KNOWN, TRACKED gaps -- not a silent exemption list. hf7y/scheduler#210
# specifically rejects a drift detector that quietly tolerates a copy staying
# wrong; these two rows are the opposite of that: still printed every run,
# just not counted as this WITNESS's failure because the open question is
# named and owned elsewhere. hf7y/scheduler#130 found usage-gate.sh names
# vendor vocabulary (bashify/lib/surface.sh's list: it reads `claude-*` model
# names and `~/.claude/...` paths) and sync-crontab.sh is a clone-only tool --
# neither is a mechanical carry like tempo.sh (#220) or check-witness.sh
# (#222): carrying either is the "none of which should be picked quietly"
# decision #130 is still open about. A row here must name the issue that
# owns it and must be deleted the same PR that resolves it -- an entry for a
# pair this check no longer flags is stale, same rule bashify's own
# PURGE-EXEMPT.tsv uses.
known_dep_gap() {
  case "$1 -> $2" in
    "bin/usage-paced-runner.sh -> bin/usage-gate.sh")   echo "#130" ;;
    "bin/usage-paced-runner.sh -> bin/sync-crontab.sh") echo "#130" ;;
    *) return 1 ;;
  esac
}

n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n+1))
  a="$(git show "$REF_MAIN:$f"  2>/dev/null | md5sum | cut -d' ' -f1)"
  b="$(git show "$REF_BASH:$f" 2>/dev/null | md5sum | cut -d' ' -f1)"
  if [ "$a" = "$b" ]; then
    ok "$f is identical on $REF_MAIN and $REF_BASH"
  else
    bad "$f DRIFTED -- $REF_BASH ships a different file than $REF_MAIN develops. The build carries the bashified one."
  fi

  # A carried file's OWN sibling references must resolve on $REF_BASH too --
  # byte-identical is not enough if the file reaches for a neighbour the OTHER
  # branch does not ship (#219 added `$SELF_DIR/tempo.sh` to a carried file
  # without carrying tempo.sh in the same PR; only caught by hand in #220).
  # Cheap approximation, not a real dependency graph: grep the AUTHORED text
  # (REF_MAIN, i.e. what this PR proposes) for the two shapes every script
  # here actually uses to reach a sibling -- `$SELF_DIR/../lib/<name>` (or any
  # similarly-derived `$VAR/lib/<name>`) and `$SELF_DIR/<name>` -- and require
  # the resolved path to exist on REF_BASH. Not a claim that every such
  # reference is reached unconditionally at runtime; a hit here is a lead to
  # check, same as this whole witness is a lead and not a full deploy replay.
  content="$(git show "$REF_MAIN:$f" 2>/dev/null)"
  deps="$( { grep -oE '\$[A-Za-z_][A-Za-z0-9_]*/(\.\./)?lib/[A-Za-z0-9_.-]+\.sh' <<<"$content" \
               | sed -E 's#.*/(lib/[A-Za-z0-9_.-]+\.sh)#\1#'
             grep -oE '\$SELF_DIR/[A-Za-z0-9_.-]+\.sh' <<<"$content" \
               | sed -E 's#\$SELF_DIR/#bin/#'
           } | sort -u )"
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    [ "$dep" = "$f" ] && continue
    if git cat-file -e "$REF_BASH:$dep" 2>/dev/null; then
      ok "$f's reference to $dep resolves on $REF_BASH"
    elif issue="$(known_dep_gap "$f" "$dep")"; then
      echo "  KNOWN GAP ($issue): $f references $dep, not carried on $REF_BASH -- open decision, not counted as a failure here"
    else
      bad "$f references $dep but $REF_BASH does not ship it -- a carried file's dependency is missing on the branch that runs it"
    fi
  done <<<"$deps"
done <<<"$carried"

[ "$n" -gt 0 ] && ok "checked $n carried file(s), derived rather than listed" \
  || bad "derived an empty carried set"

printf '\ncarry-drift-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
