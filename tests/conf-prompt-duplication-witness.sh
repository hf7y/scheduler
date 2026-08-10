#!/usr/bin/env bash
# WIP / exploratory -- see the tracking issue this PR links for the
# higher-level design pass this still needs before it is treated as a real
# mechanism. Committed as-is on 2026-08-10, not polished or finished.
#
# Witness for "does the same prose get hand-copied into two schedule/*.conf
# BATCH_PROMPT (or SWEEP_PROMPT) strings, so one goes stale while the other
# is updated?"
#
# THE BUG THIS IS AIMED AT: commit 9cfd130 hand-typed an identical
# "STANDING RULES" block into THREE separate confs' BATCH_PROMPT
# (schedule/ecosim.conf, schedule/vim-arcade.conf, schedule/bibliothecaire.conf),
# verified byte-identical by diff. Nothing checked for this -- a stale/wrong
# copy in one conf while the others get updated is invisible until someone
# happens to diff them by hand.
#
# This is a GENERIC detector, not a check for that one string: it flags any
# run of THRESHOLD (8) or more consecutive non-blank lines that appear
# verbatim in two or more different confs' prompt fields. 8 was picked as
# "long enough that a real paragraph, not a coincidental short phrase, has to
# match" -- a boilerplate one-liner like "Recording nothing is treated as
# NOT-DONE" is exactly the kind of short overlap that should NOT fire this;
# an entire copy-pasted numbered rule block should. Not empirically tuned
# beyond that judgment call -- flagged as an open question for the design
# pass rather than settled here.
#
# Implementation note: the actual duplicate-detection logic lives in
# tests/lib/conf-prompt-dup-detect.py (stdlib difflib.SequenceMatcher over
# each conf's extracted prompt text, blank lines stripped). This shell
# wrapper just runs it against the real, shipped schedule/*.conf and reports
# pass/fail -- there is deliberately no synthetic-fixture self-test of the
# detector logic itself yet (that's part of what's unfinished; see the issue).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$ROOT/tests/lib/conf-prompt-dup-detect.py"
[ -f "$DETECTOR" ] || { echo "detector script not found: $DETECTOR"; exit 1; }

THRESHOLD=8
shopt -s nullglob
CONFS=("$ROOT"/schedule/*.conf)
[ "${#CONFS[@]}" -gt 0 ] || { echo "no schedule/*.conf found -- nothing to check"; exit 1; }

echo "== conf-prompt-duplication-witness: scanning ${#CONFS[@]} conf(s), threshold=$THRESHOLD consecutive lines"
OUT="$(python3 "$DETECTOR" "$THRESHOLD" "${CONFS[@]}")"
RC=$?

if [ "$RC" -eq 0 ]; then
  echo "  PASS: no duplicated prompt text (>= $THRESHOLD consecutive lines) found across confs"
  exit 0
elif [ "$RC" -eq 1 ]; then
  echo "  FAIL: duplicated prompt text found -- a stale copy in one conf can drift"
  echo "        from the others silently. Each line below names the two confs,"
  echo "        fields, and line ranges that match verbatim:"
  echo "$OUT" | sed 's/^/    /'
  exit 1
else
  echo "  FAIL: detector script errored (rc=$RC) -- treat as a failure, not a pass by absence"
  echo "$OUT" | sed 's/^/    /'
  exit 1
fi
