#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/../lib/sweep-loop-common.sh"
source "$HERE/lib/witness-common.sh"

echo "remote-refs-are-evidence-witness"

# The engine's HEAD-did-not-move arm, lifted verbatim and closed with `fi`, so
# this drives the shipped text rather than a paraphrase of it. Same extraction
# idiom as tests/sweep-loop-node-bin-witness.sh.
BLOCK="$(sed -n '/^  if \[ "\$AFTER_SHA" = "\$BEFORE_SHA" \]; then$/,/^  elif \[ "\$AFTER_SHA" = "\$REMOTE_SHA" \]; then$/p' "$ENGINE" \
         | sed '$d')"
if ! printf '%s' "$BLOCK" | grep -q 'ls-remote --heads origin'; then
  bad "could not lift the HEAD-unchanged arm out of the engine -- nothing below was tested"
  exit 1
fi
eval "report_unchanged_head() { $BLOCK fi; }"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/work" 2>/dev/null
cd "$T/work" || exit 1
git config user.email a@b; git config user.name a
echo one > f; git add f; git commit -qm one; git push -q origin HEAD:main
git checkout -q -B main

BEFORE_SHA="$(git rev-parse HEAD)"; AFTER_SHA="$BEFORE_SHA"
HEAD_BRANCH=main; BRANCH=main
BEFORE_REMOTE_HEADS="$(git ls-remote --heads origin 2>/dev/null | sort)"

out="$(report_unchanged_head 2>&1)"
case "$out" in
  "pushed: no -- no new commits this run, and origin gained no refs"*)
    ok "a run that pushed nothing still reports pushed: no" ;;
  *) bad "an idle run reported: $out" ;;
esac

# The shape the estate's own workflow produces: branch, commit, push, open a
# PR, return to main. HEAD is byte-identical to where it started.
git checkout -q -b feature
echo two > g; git add g; git commit -qm two; git push -q origin feature
git checkout -q main
[ "$(git rev-parse HEAD)" = "$BEFORE_SHA" ] \
  && ok "the fixture reproduces it: HEAD is exactly where the run started" \
  || bad "fixture is wrong -- HEAD moved, so the case under test is not the one being run"

out="$(report_unchanged_head 2>&1)"
case "$out" in
  "pushed: no"*) bad "two pushed refs and an opened PR still read as 'pushed: no' -- the 2026-09-02 american-cycle report" ;;
  "pushed: yes, but not onto main"*) ok "a branch pushed from an unmoved HEAD is reported as pushed, not as nothing" ;;
  *) bad "unrecognised report: $out" ;;
esac
case "$out" in
  *refs/heads/feature*) ok "and the report names the ref origin gained" ;;
  *) bad "the report does not name refs/heads/feature: $out" ;;
esac

printf '\nremote-refs-are-evidence: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
