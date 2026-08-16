#!/usr/bin/env bash
# HERMETICITY: reads bin/scheduler as TEXT and checks the label descriptions it
# would send. No network, no `gh`, no GitHub token, no repo writes. It asserts a
# property of the source, which is the only thing that can be checked offline --
# and the only thing that was wrong.
#
# tests/from-label-witness.sh -- witness for the label-description length limit.
#
# WHY THIS EXISTS. `scheduler -i` labels each filed idea `from:<project>` and
# creates that label on demand, because the set of callers is open-ended. The
# description shipped in #69 was 102 characters. GitHub rejects a label
# description over 100 with HTTP 422.
#
# The failure was silent in the worst way. `gh label create ... || true` is
# correct -- "label already exists" is the normal case and must not be fatal --
# but it swallows a 422 identically. So every call failed, the label never
# existed, and the NEXT call, `gh issue create --label from:<p>`, failed with
#
#     could not add label: 'from:realisateur' not found
#
# and recorded nothing. That is `notify-senechal` -- the front door this
# ecosystem REQUIRES before any machine-wide config change -- broken from the
# moment #69 merged, for every project, on every host. It was found by trying to
# file a real note through it, not by a test, which is why there is now a test.
#
# WHAT THIS DOES NOT COVER, stated so the coverage is not overread: it checks
# the LITERAL descriptions in the source. It cannot catch a description built at
# runtime from a variable, and it does not talk to GitHub, so it cannot notice
# if the limit itself changes. It asserts the one property that broke.
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SCHED="$ROOT/bin/scheduler"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "--- gh label description length ---"

[ -f "$SCHED" ] || { echo "BLIND: no $SCHED"; exit 2; }

# GitHub's documented maximum. Named rather than inlined so the failure message
# can state the rule instead of only the number.
LIMIT=100

# Every --description literal on a `gh label create` line. The descriptions sit
# on their own continuation line, so the file is scanned for the flag directly
# rather than trying to reassemble backslash-continued commands.
found=0
while IFS= read -r line; do
  desc="$(sed -nE 's/.*--description "([^"]*)".*/\1/p' <<<"$line")"
  [ -n "$desc" ] || continue
  found=$((found + 1))
  if [ "${#desc}" -gt "$LIMIT" ]; then
    bad "description is ${#desc} chars (limit $LIMIT)" "GitHub returns HTTP 422 and the label is never created: ${desc:0:60}..."
  else
    ok "${#desc}/$LIMIT: ${desc:0:52}"
  fi
done < <(grep -n -- '--description "' "$SCHED" | grep -v '^\s*#')

# A scan that matched nothing is a broken grep, not a clean file. This is the
# same conflation `bin/tests/*.sh matched nothing` was in realisateur's CI:
# "found no violations" and "could not look" must never share an exit code.
if [ "$found" -eq 0 ]; then
  bad "matched zero --description literals in bin/scheduler" "the scan is broken; this run asserted NOTHING"
fi

echo "from-label: $PASS passed, $FAIL failed ($found description(s) checked)"
[ "$FAIL" -eq 0 ]
