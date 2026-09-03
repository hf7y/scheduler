#!/usr/bin/env bash
# provision-witness.sh -- the ok/gap/bad counter idiom shared by the selfdev
# provisioning scripts (#517, continues #210/#215's collapse).
#
# The printed TEXT stays per-caller on purpose: tests/dresse.test.sh:86
# asserts an exact BLIND line, and selfdev-credentials.sh already disagrees
# with the other seven scripts on case and wording (lowercase "ok", "FLAG
# [drift]" for bad). Unifying that text would be a wider, riskier change than
# what actually drifted, which was the counting -- eight copies of "bump a
# counter, print a line" with nothing keeping them in sync. Every existing
# line happens to be "<fixed prefix><message>\n", so the prefix alone is
# enough to reproduce each caller's exact output; no printf-format-from-a-
# variable (SC2059) is needed.
#
# Usage: set OK_PREFIX/GAP_PREFIX/BAD_PREFIX (required) and ACT_PREFIX
# (optional, only if the caller defines act()) to the caller's EXISTING
# prefix, then source this file. It defines PASS/GAPS/BAD=0 and
# ok()/gap()/bad(), plus act() if ACT_PREFIX is set.
#
# blind() stays out of this file: only two of the eight callers have it, they
# disagree on which variable name they bump (BLIND vs BLIND_N), and
# selfdev-claude-token.sh checks $BLIND at several early-exit points, not
# just at the end -- collapsing two sites into a parameterized indirection
# would cost more clarity than it saves.

: "${OK_PREFIX:?provision-witness.sh: OK_PREFIX unset}"
: "${GAP_PREFIX:?provision-witness.sh: GAP_PREFIX unset}"
: "${BAD_PREFIX:?provision-witness.sh: BAD_PREFIX unset}"

PASS=0; GAPS=0; BAD=0
ok()  { printf '%s%s\n' "$OK_PREFIX" "$*"; PASS=$((PASS+1)); }
gap() { printf '%s%s\n' "$GAP_PREFIX" "$*"; GAPS=$((GAPS+1)); }
bad() { printf '%s%s\n' "$BAD_PREFIX" "$*"; BAD=$((BAD+1)); }
if [ -n "${ACT_PREFIX:-}" ]; then
  act() { printf '%s%s\n' "$ACT_PREFIX" "$*"; }
fi
