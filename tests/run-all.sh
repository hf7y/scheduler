#!/usr/bin/env bash
# Runs every tests/*-witness.sh AND every tests/*.test.sh, and fails loud if
# any of them fails.
#
# Added 2026-07-28 with the q-756f82 fix: three witnesses existed and
# NOTHING ran them -- each was a test only a person who already knew its
# filename would ever execute. One entry point means a new witness is
# picked up by existing, not by being remembered.
#
# THE SECOND SUFFIX, 2026-08-26. The provisioning block arrived from
# realisateur carrying nine suites named `*.test.sh` -- that repo's
# convention, not this one. Under a `*-witness.sh`-only glob all nine would
# have sat in this directory passing locally and running NOWHERE, which is
# the exact defect the paragraph above records being fixed. Renaming them
# would have worked too and was rejected: a suite that changes name on the
# way between repos loses its git history at the moment someone most needs
# to ask what it used to assert. The glob is cheaper and it is the half that
# was wrong.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
shopt -s nullglob
WITNESSES=(*-witness.sh *.test.sh)
[ "${#WITNESSES[@]}" -gt 0 ] || { echo "no witnesses found -- that is a failure, not a pass"; exit 1; }

FAILED=()
for w in "${WITNESSES[@]}"; do
  echo "==== $w"
  if bash "$w"; then echo "---- $w OK"; else FAILED+=("$w"); echo "---- $w FAILED"; fi
  echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "FAILED (${#FAILED[@]}/${#WITNESSES[@]}): ${FAILED[*]}"
  exit 1
fi
echo "all ${#WITNESSES[@]} witness(es) passed"
