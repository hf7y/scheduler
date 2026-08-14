#!/usr/bin/env bash
# Witness for WHAT COUNTS AS AN ANSWER (lib/provenance.sh,
# PROVENANCE_ANSWERED_JQ), 2026-08-14.
#
# The bug this pins: `issues_counts` in bin/scheduler counted an issue as
# unanswered unless it carried the `answered` LABEL, and queried only
# `--state open`. Nothing has ever applied that label -- Zach answers by
# COMMENTING and leaving the issue open -- so every answer he ever wrote was
# reported as UNANSWERED on the bare `scheduler` glance, the most-typed
# command in the estate. Live on hf7y/chezz the day this landed: the old
# predicate said 5 of 5 open questions were unanswered; the real number is 1.
#
# Assertions run over fixture JSON, so this needs no network and no `gh`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/lib/provenance.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "  FAIL: jq missing -- this witness cannot look, which is not a pass"; exit 1; }

# $1 = issue JSON object, $2 = expected true/false, $3 = label
answers() {
  local got
  got="$(printf '%s' "$1" | jq -r --arg owner hf7y "$PROVENANCE_ANSWERED_JQ"'is_answered($owner)' 2>&1)" \
    || { bad "$3 -- jq errored: $got"; return; }
  [ "$got" = "$2" ] && ok "$3" || bad "$3 -- expected $2, got $got"
}

STAMP='<!-- agent: chezz/tick 2026-08-14T00:00:00Z -->'

echo "== is_answered"
answers '{"labels":[],"comments":[]}' false \
  "no comments at all -- unanswered"
answers '{"labels":[],"comments":[{"author":{"login":"hf7y"},"body":"audio default on"}]}' true \
  "plain owner comment -- ANSWERED (no label, issue left open)"
answers "{\"labels\":[],\"comments\":[{\"author\":{\"login\":\"hf7y\"},\"body\":\"asked under the shared token\n\n$STAMP\"}]}" false \
  "agent-stamped comment under the same shared token -- still unanswered"
answers "{\"labels\":[],\"comments\":[{\"author\":{\"login\":\"hf7y\"},\"body\":\"quoting a stamp $STAMP mid-body, then talking\"}]}" true \
  "stamp quoted MID-body is not a stamp -- last non-blank line only"
answers '{"labels":[],"comments":[{"author":{"login":"someone-else"},"body":"drive-by"}]}' false \
  "comment from a non-owner -- unanswered"
answers '{"labels":[{"name":"answered"}],"comments":[]}' true \
  'the `answered` label is still honoured as an optional override where someone applied it'

echo "== the retired predicate must not come back"
if grep -nE 'index\("answered"\)' "$ROOT/bin/scheduler" | grep -v '^[0-9]*:#'; then
  bad "bin/scheduler still READS the \`answered\` label as an answer predicate"
else
  ok "bin/scheduler no longer reads the \`answered\` label as an answer predicate"
fi
if sed -n '/^issues_counts() {/,/^}/p' "$ROOT/bin/scheduler" | grep -q -- '--state all'; then
  ok "issues_counts queries --state all (an answer sits on open and closed issues alike)"
else
  bad "issues_counts is gated on an issue STATE -- that gate drops answers"
fi
if sed -n '/^issues_counts() {/,/^}/p' "$ROOT/bin/scheduler" | grep -q 'BLIND, not zero'; then
  ok "issues_counts fails loud rather than returning a clean zero it never looked for"
else
  bad "issues_counts has no BLIND path -- a count it could not read reads as 'nothing open'"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
