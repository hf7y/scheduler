#!/usr/bin/env bash
# Witness for bin/roster-target.sh -- the roster redesign's dated commitment.
#
# WHAT THIS WITNESS DOES AND DOES NOT ASSERT.
#
# It does NOT assert that the six vision probes pass. They do not, and they are
# expected not to until hf7y/scheduler#79/#80/#81/#78 land. Wiring a
# known-red check into tests/run-all.sh -- which fails loud if ANY witness
# fails -- would make the whole suite permanently red, and this repo already
# has one such failure (#58, runner-conf-host-witness). A second one is how a
# suite stops being read. realisateur's CLAUDE.md writes that lesson down about
# silence-audit in as many words: "A mandatory row nobody can satisfy is how a
# checklist stops being read."
#
# It DOES assert the thing that must not rot: that the SUNSET is real. On
# 2026-08-24 `--strict` starts exiting 4, this witness starts failing, and the
# only thing that clears it is deleting bin/roster-target.sh and this file. A
# self-destruct that no runner evaluates is a paragraph, not a commitment.
#
# So the split is: the sunset is CI-gated and cheap (a date comparison, no repo
# reads, no network); the probes are operator-run --
#
#     bash bin/roster-target.sh
#
# and their result is the answer to "has the redesign landed", which is a
# question for a human or a report, not a gate on every pull request.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET=bin/roster-target.sh

echo "roster-target-witness -- the sunset is the assertion"

# --- 0. the file is there and runnable ------------------------------------
if [ -x "$TARGET" ]; then
  ok "$TARGET exists and is executable"
else
  bad "$TARGET missing or not executable -- if the redesign landed and it was deleted, delete this witness too"
  echo; echo "roster-target-witness: $PASS passed, $FAIL failed"; exit 1
fi

# --- 1. BEFORE the sunset: --strict is green ------------------------------
# This is the case that holds today. It is what keeps run-all.sh able to go
# green while the probes are still red.
out="$(ROSTER_TARGET_SUNSET=2099-01-01 bash "$TARGET" --strict 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "before the sunset, --strict exits 0" \
  || bad "before the sunset, --strict exited $rc (want 0): $out"

# --- 2. AFTER the sunset: --strict is red, and says to delete the file -----
# The commitment itself. If this stops being true, the self-destruct is
# decorative.
out="$(ROSTER_TARGET_SUNSET=2026-01-01 bash "$TARGET" --strict 2>&1)"; rc=$?
[ "$rc" -eq 4 ] && ok "after the sunset, --strict exits 4" \
  || bad "after the sunset, --strict exited $rc (want 4) -- the self-destruct does not fire: $out"
grep -qi 'delete' <<<"$out" && ok "the sunset message says what to do (delete the file)" \
  || bad "the sunset fires but does not say to delete the file: $out"

# --- 3. --strict reads no repository state --------------------------------
# The reason --strict can be the CI gate at all: it must work in a checkout
# with no schedule/ dir, no bashified branch, and no network. Proved by
# running it somewhere that has none of those, not by reading the code.
tmp="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
cp "$TARGET" "$tmp/roster-target.sh"
out="$(cd "$tmp" && ROSTER_TARGET_SUNSET=2099-01-01 bash roster-target.sh --strict 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--strict runs with no schedule/, no git, no network" \
  || bad "--strict needs repository state, so it cannot be the CI gate (exit $rc): $out"

# --- 4. the sunset date agrees with realisateur's ------------------------
# Same commitment, two files. Two dates for one promise is how one of them
# quietly becomes the real one. Advisory: realisateur is not always present,
# and its absence is not this repo's failure.
theirs=/home/zach/Documents/Projects/realisateur/bin/served-not-cloned.sh
mine="$(grep -m1 '^SUNSET=' "$TARGET" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
if [ -f "$theirs" ]; then
  other="$(grep -m1 '^SUNSET=' "$theirs" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
  [ "$mine" = "$other" ] && ok "sunset $mine matches realisateur/bin/served-not-cloned.sh" \
    || bad "sunset drift: this file says $mine, served-not-cloned.sh says $other -- one promise, two dates"
else
  echo "  SKIP: realisateur checkout not present; cannot compare sunset dates (this file says $mine)"
fi

# --- 5. the probes still RUN, whatever they conclude ----------------------
# Not an assertion about the verdict -- an assertion that a broken probe is
# distinguishable from an unmet one. Exit 1 is UNMET (expected today); exit 0
# is MET; exit 2 is BLIND. Anything else means the script itself broke.
out="$(bash "$TARGET" --quiet 2>&1)"; rc=$?
case "$rc" in
  0) ok "the probes ran; target MET -- delete $TARGET and this witness" ;;
  1) ok "the probes ran; UNMET (expected until the redesign lands)" ;;
  2) ok "the probes ran; BLIND reported honestly rather than as an all-clear" ;;
  *) bad "the probes did not run cleanly (exit $rc): $out" ;;
esac

echo
echo "roster-target-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
