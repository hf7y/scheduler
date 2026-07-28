#!/usr/bin/env bash
# Runs every tests/*-witness.sh and fails loud if any of them fails.
#
# Added 2026-07-28 with the q-756f82 fix: three witnesses existed and
# NOTHING ran them -- each was a test only a person who already knew its
# filename would ever execute. One entry point means a new witness is
# picked up by existing, not by being remembered.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
shopt -s nullglob
WITNESSES=(*-witness.sh)
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
