#!/usr/bin/env bash
# branch-protection-witness.sh -- which checks actually gate `main`, read from
# the API rather than asserted in a comment. An agent decides whether it may
# merge its own PR from this. `prose` NOT being required is the half that
# matters: `suites` green + `prose` red is UNSTABLE and IS mergeable, `suites`
# red is BLOCKED.
#
# RUNNER: tests/run-all.sh. THE ONE WITNESS HERE THAT REACHES THE NETWORK: it
# stubs nothing, and asserts nothing where it cannot read protection.
set -uo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"

REPO="${BRANCH_PROTECTION_REPO:-hf7y/scheduler}"
BRANCH="${BRANCH_PROTECTION_BRANCH:-main}"

# THE CONTRACT (hf7y/scheduler#87). `suites` gates; `prose` deliberately does not.
REQUIRED=("suites")
ADVISORY=("prose / prose")

section "A. the required check set on $REPO@$BRANCH"

body="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  case "$body" in
    *"Branch not protected"*)
      bad "$BRANCH is protected" \
          "the API says it is NOT. ${REQUIRED[*]} gates nothing and a direct push lands.
        Remedy: re-enable protection on $REPO@$BRANCH (required checks ${REQUIRED[*]},
        enforce_admins on), or change this witness if that was deliberate."
      summary; exit $?
      ;;
    *)
      # Reading protection needs admin, which a CI GITHUB_TOKEN does not have.
      # Expected there; named rather than counted as a pass.
      echo "  BLIND cannot read protection on $REPO ($(printf '%s' "$body" | tr '\n' ' ' | cut -c1-100))"
      echo "        Nothing in section A was exercised. Re-run where \`gh\` is authenticated as an admin."
      summary; exit $?
      ;;
  esac
fi

got_ctx="$(printf '%s' "$body" | jq -r '.required_status_checks.contexts[]' 2>/dev/null | sort)"
want_ctx="$(printf '%s\n' "${REQUIRED[@]}" | sort)"
eq "the required contexts are exactly the ones this repo gates on" "$got_ctx" "$want_ctx"
[ "$got_ctx" = "$want_ctx" ] || printf '        %s\n' \
  "Remedy: either restore the contexts above on $REPO@$BRANCH, or update REQUIRED/ADVISORY here and say why in the PR."

eq "enforce_admins is on, so a direct push to $BRANCH is refused for everyone" \
   "$(printf '%s' "$body" | jq -r '.enforce_admins.enabled')" "true"

for job in "${ADVISORY[@]}"; do
  case "$got_ctx" in
    *"$job"*) bad "$job is advisory, not required" \
        "it is required now, so a red $job BLOCKS every merge -- and it is
        maintained in hf7y/etalon, outside this repo. Remedy: drop it from the
        required contexts, or move it to REQUIRED here." ;;
    *) ok "$job stays advisory -- red reports UNSTABLE, and the PR is still mergeable" ;;
  esac
done

summary
