#!/usr/bin/env bash
# provision-witness.sh -- the ok/gap/bad/act/blind counter idiom, shared.
#
# hf7y/scheduler#517: 8 selfdev-*.sh provisioning scripts each retyped this
# by hand and had already drifted (GAP vs MISSING vs gap, OK vs ok, a stray
# FLAG [drift]). #517 itself ruled out unifying the printed text -- one test
# asserts an exact string, and reformatting selfdev-credentials.sh's output
# is a wider blast radius than a dedup pass should take. So this collapses
# only the LOGIC: each caller keeps its own wording by setting the PW_*_FMT
# variables below before sourcing. No script's output changes.
#
# USAGE: set PW_OK_FMT / PW_GAP_FMT / PW_BAD_FMT (required), and
# PW_ACT_FMT / PW_BLIND_FMT (optional -- act()/blind() are defined only if
# their format is set, same as before this collapse, where six of the eight
# callers had no blind() and one had no act()). Each *_FMT is a printf
# format string taking exactly one %s. Then source this file.
#
#   PW_OK_FMT='  OK      %s\n'
#   PW_GAP_FMT='  MISSING %s\n'
#   PW_BAD_FMT='  BAD     %s\n'
#   PW_ACT_FMT='  DO      %s\n'
#   . "$(dirname "${BASH_SOURCE[0]}")/../lib/provision-witness.sh"
#
# die() is deliberately NOT provided here: exit codes and message shapes
# differ per caller (2 vs 1 vs 5, name-prefixed vs not) widely enough that
# sharing it would be the format-unify #517 ruled out, not a logic dedup.

: "${PW_OK_FMT:?provision-witness.sh: PW_OK_FMT must be set before sourcing}"
: "${PW_GAP_FMT:?provision-witness.sh: PW_GAP_FMT must be set before sourcing}"
: "${PW_BAD_FMT:?provision-witness.sh: PW_BAD_FMT must be set before sourcing}"

PASS=0; GAPS=0; BAD=0; BLIND=0

ok()  { printf "$PW_OK_FMT" "$*"; PASS=$((PASS+1)); }
gap() { printf "$PW_GAP_FMT" "$*"; GAPS=$((GAPS+1)); }
bad() { printf "$PW_BAD_FMT" "$*"; BAD=$((BAD+1)); }

if [ -n "${PW_ACT_FMT:-}" ]; then
  act() { printf "$PW_ACT_FMT" "$*"; }
fi
if [ -n "${PW_BLIND_FMT:-}" ]; then
  blind() { printf "$PW_BLIND_FMT" "$*"; BLIND=$((BLIND+1)); }
fi
