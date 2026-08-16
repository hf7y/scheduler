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
REF_MAIN="${CARRY_REF_MAIN:-origin/main}"
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
done <<<"$carried"

[ "$n" -gt 0 ] && ok "checked $n carried file(s), derived rather than listed" \
  || bad "derived an empty carried set"

printf '\ncarry-drift-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
