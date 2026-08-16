#!/usr/bin/env bash
# Witness for "is the same prose hand-copied into two schedule/ prompt
# sources, so one goes stale while the other is updated?"
#
# THE DEFECT THIS RETIRES. Commit 9cfd130 (2026-08-07) hand-typed an
# identical STANDING RULES block into THREE separate BATCH_PROMPT strings --
# ecosim, vim-arcade, bibliothecaire. Nothing held them equal; they were
# known identical only because someone diffed them once, by hand, after the
# fact. #71 extracted that block into schedule/_standing-rules.md, which
# fixes the instance. This fixes the CLASS: nothing stops the next hurried
# edit from pasting a paragraph into two confs again, and nothing stops a
# copy of the extracted block from being pasted BACK into one.
#
# WHAT IT COMPARES. Every schedule/*.conf's BATCH_PROMPT and SWEEP_PROMPT,
# plus the shared fragments schedule/_*.md. That second half is the job the
# check inherits post-#71: conf-vs-conf duplication is now the rarer case,
# and a re-inlined copy of the shared block is the likelier one. Duplication
# WITHIN one file (its own two tiers) is deliberately not flagged -- that is
# one text in one place, which is the thing being asked for.
#
# THE THRESHOLD IS 8 CONSECUTIVE NON-BLANK LINES, and it is no longer a bare
# judgement call. Sweeping it against the real tree on 2026-08-11:
#
#     threshold   2   3   4   5   6   7   8  10  15  20  25  29
#     findings   33  28  13   2   2   2   2   2   1   1   1   0
#
# There is a plateau from 5 to 10 where the count is exactly the two real
# duplications, a noise cliff at 4 (13 findings, coincidental short-phrase
# overlap), and above 10 it starts missing real ones. 8 is the middle of the
# plateau: three lines of margin above the noise, two below the smaller real
# finding. Re-run the sweep if this ever needs re-arguing -- the numbers are
# reproducible with tests/lib/conf-prompt-dup-detect.py.
#
# WHY A RATCHET AND NOT A CONFORMANCE CHECK. Same reasoning as
# bin/shellcheck-lint.sh, and the same file format: a check nobody expects to
# be green is a document with an exit code. When this was written the tree
# held two real duplicated blocks between ecosim.conf and vim-arcade.conf
# (~25 and ~14 lines of triage and verdict policy) that #71 did not touch and
# that are a separate piece of work -- extracting them means a SECOND shared
# fragment, which is the stated trigger for generalising the opt-in beyond
# one boolean (#72 q2). So the assertion is not "no conf shares prose". It is
# "no NEW duplication has appeared, and no existing one has drifted".
#
# The ratchet key is (fileA:field, fileB:field, sha12-of-the-block) -- not
# line numbers, which move when unrelated prose is edited above them, and not
# a count, which is gameable in the direction that matters. Hashing the block
# means editing ONE of two copies changes the key and the pair goes red. That
# is the alarm working, not brittleness: divergence between copies is the
# exact failure this check is named after.
#
# usage:  conf-prompt-duplication-witness.sh [--accept]
#         --accept rewrites tests/conf-prompt-dup.ratchet to the current set,
#         reporting what it added and removed. Accepting is a visible act.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$ROOT/tests/lib/conf-prompt-dup-detect.py"
RATCHET="$ROOT/tests/conf-prompt-dup.ratchet"
THRESHOLD=8

[ -f "$DETECTOR" ] || { echo "detector not found: $DETECTOR"; exit 1; }
command -v python3 >/dev/null 2>&1 || {
  echo "BLIND: python3 not on PATH -- this witness could not look, which is not a pass"
  exit 1
}

ACCEPT=0
case "${1:-}" in
  --accept) ACCEPT=1 ;;
  "") : ;;
  *) echo "usage: conf-prompt-duplication-witness.sh [--accept]" >&2; exit 2 ;;
esac

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# Stable ratchet key: the first three fields of a finding.
keys_of() { cut -f1-3 | sort -u; }
detect()  { python3 "$DETECTOR" "$THRESHOLD" "$@"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# PART 1 -- the detector against synthetic fixtures.
#
# This half is here because the real-tree scan alone cannot tell a working
# detector from a broken one: both report "nothing found" on a clean tree. A
# detector never observed rejecting a known-bad input is indistinguishable
# from one that cannot reject anything.
# ---------------------------------------------------------------------------
echo "== the detector actually bites (synthetic fixtures)"
F="$TMP/fx"; mkdir -p "$F"

# A 10-line block, and a 7-line prefix of it, so the boundary can be probed
# without changing anything else about the fixtures.
block() { local n="$1" i; for ((i=1; i<=n; i++)); do echo "SHARED POLICY LINE $i -- long enough to be a real paragraph."; done; }

mkconf() { # $1=name $2=prompt body
  printf 'BATCH_JOB_NAME="%s"\nBATCH_PROMPT="%s"\n' "$1" "$2" > "$F/$1.conf"
}

mkconf alpha "ALPHA OWN LINE.
$(block 10)
ALPHA TAIL."
mkconf beta "BETA OWN LINE.
$(block 10)
BETA TAIL."
out="$(detect "$F/alpha.conf" "$F/beta.conf")"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ]; then
  ok "a 10-line block shared by two confs is found (exit 1, one finding)"
else
  bad "known-bad input not flagged: rc=$rc out=[$out]"
fi
case "$out" in
  "alpha.conf:BATCH_PROMPT"*"beta.conf:BATCH_PROMPT"*) ok "and it names both confs and both fields" ;;
  *) bad "finding does not name the pair: [$out]" ;;
esac
case "$out" in
  */*) bad "finding leaks an absolute path -- a ratchet keyed on it breaks in CI" ;;
  *)   ok "paths are basenames, so a ratchet accepted locally still matches in CI" ;;
esac

# Boundary. 7 shared lines must not fire at threshold 8; 8 must.
mkconf alpha "ALPHA OWN LINE.
$(block 7)
ALPHA TAIL."
mkconf beta "BETA OWN LINE.
$(block 7)
BETA TAIL."
detect "$F/alpha.conf" "$F/beta.conf" >/dev/null
if [ $? -eq 0 ]; then ok "7 shared lines is below the threshold of 8 -- silent"
else bad "threshold is not honoured: 7 lines fired at THRESHOLD=$THRESHOLD"; fi
mkconf alpha "ALPHA OWN LINE.
$(block 8)
ALPHA TAIL."
mkconf beta "BETA OWN LINE.
$(block 8)
BETA TAIL."
detect "$F/alpha.conf" "$F/beta.conf" >/dev/null
if [ $? -eq 1 ]; then ok "8 shared lines is at the threshold -- flagged"
else bad "threshold off by one: 8 lines did not fire at THRESHOLD=$THRESHOLD"; fi

# Known-good: two confs that share nothing.
mkconf alpha "ALPHA OWN LINE.
$(block 10)
ALPHA TAIL."
printf 'BATCH_JOB_NAME="gamma"\nBATCH_PROMPT="GAMMA SAYS SOMETHING ENTIRELY ITS OWN.\nAnd a second unrelated line."\n' > "$F/gamma.conf"
detect "$F/alpha.conf" "$F/gamma.conf" >/dev/null
if [ $? -eq 0 ]; then ok "two confs sharing nothing are clean (exit 0)"
else bad "false positive on unrelated confs"; fi

echo "== a copy back INTO a conf is caught (the post-#71 job)"
# The shared fragment, and a conf that has pasted it back inline. Note the
# conf escapes its quotes, as a real one must; if the detector did not undo
# that, this would silently pass for the wrong reason.
{ echo 'SHARED FRAGMENT (fixture). These override everything "below".'; block 9; } > "$F/_frag.md"
mkconf delta "DELTA OWN LINE.
SHARED FRAGMENT (fixture). These override everything \\\"below\\\".
$(block 9)
DELTA TAIL."
out="$(detect "$F/delta.conf" "$F/_frag.md")"; rc=$?
if [ "$rc" -eq 1 ]; then ok "a conf that re-inlines the shared fragment is flagged against it"
else bad "copy-back into a conf was NOT caught: rc=$rc"; fi
case "$out" in
  *"_frag.md:FILE"*) ok "and the finding names the fragment file, not just the conf" ;;
  *) bad "finding does not name the fragment: [$out]" ;;
esac
case "$out" in
  *'everything "below"'*) ok "escaped quotes in the conf are unescaped before comparing" ;;
  *) bad "the quoted line did not match across the escaping boundary: [$out]" ;;
esac

echo "== drift between two copies changes the ratchet key"
key_before="$(detect "$F/delta.conf" "$F/_frag.md" | keys_of)"
sed -i 's/SHARED POLICY LINE 5 -- long enough to be a real paragraph./SHARED POLICY LINE 5 -- EDITED IN ONE COPY ONLY./' "$F/delta.conf"
key_after="$(detect "$F/delta.conf" "$F/_frag.md" | keys_of)"
if [ -n "$key_before" ] && [ "$key_before" != "$key_after" ]; then
  ok "editing one copy changes the key, so a baselined pair goes red on drift"
else
  bad "drift did not change the key -- the ratchet would hide a diverging copy"
fi

echo "== the ratchet comparison itself"
# Exercised on fixture data, so the logic that decides pass/fail is tested
# rather than only run.
printf 'a.conf:BATCH_PROMPT\tb.conf:BATCH_PROMPT\tdeadbeef1234\n' > "$TMP/rat"
cur_same="a.conf:BATCH_PROMPT	b.conf:BATCH_PROMPT	deadbeef1234"
cur_new="a.conf:BATCH_PROMPT	b.conf:BATCH_PROMPT	deadbeef1234
c.conf:BATCH_PROMPT	d.conf:BATCH_PROMPT	0123456789ab"
base="$(grep -v '^#' "$TMP/rat" | grep -v '^[[:space:]]*$' | sort -u)"
added="$(comm -13 <(printf '%s\n' "$base") <(printf '%s\n' "$cur_same" | sort -u))"
[ -z "$added" ] && ok "a finding already in the ratchet is not a regression" \
                || bad "baselined finding reported as new: [$added]"
added="$(comm -13 <(printf '%s\n' "$base") <(printf '%s\n' "$cur_new" | sort -u))"
[ "$added" = "c.conf:BATCH_PROMPT	d.conf:BATCH_PROMPT	0123456789ab" ] \
  && ok "a finding NOT in the ratchet is reported as new" \
  || bad "new finding not detected: [$added]"

# ---------------------------------------------------------------------------
# PART 2 -- the real schedule/ directory, against the ratchet.
# ---------------------------------------------------------------------------
echo "== the real schedule/ directory"
shopt -s nullglob
SOURCES=("$ROOT"/schedule/*.conf "$ROOT"/schedule/_*.md)
if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "  FAIL: no schedule/ prompt sources matched -- a scan of nothing is not a clean tree"
  exit 1
fi

FINDINGS="$(detect "${SOURCES[@]}")"; DRC=$?
if [ "$DRC" -gt 1 ]; then
  echo "  FAIL: detector errored (rc=$DRC) -- treat as failure, never a pass by absence"
  printf '%s\n' "$FINDINGS" | sed 's/^/    /'
  exit 1
fi
CURRENT="$(printf '%s' "$FINDINGS" | grep -v '^$' | keys_of)"
BASELINE=""
[ -f "$RATCHET" ] && BASELINE="$(grep -v '^#' "$RATCHET" | grep -v '^[[:space:]]*$' | sort -u)"

ADDED="$(comm -13 <(printf '%s\n' "$BASELINE") <(printf '%s\n' "$CURRENT"))"
GONE="$(comm -23 <(printf '%s\n' "$BASELINE") <(printf '%s\n' "$CURRENT"))"
NCUR="$(printf '%s' "$CURRENT" | grep -c . || true)"
NBASE="$(printf '%s' "$BASELINE" | grep -c . || true)"

if [ "$ACCEPT" -eq 1 ]; then
  { echo "# conf-prompt-dup.ratchet -- duplicated prompt blocks present when accepted."
    echo "# Raised or lowered ONLY by --accept, which always reports what it changed."
    echo "# Key: fileA:field <TAB> fileB:field <TAB> sha12 of the duplicated block."
    echo "# See tests/conf-prompt-duplication-witness.sh for why the pair-and-hash."
    echo "# accepted $(date -u +%Y-%m-%dT%H:%M:%SZ) threshold=$THRESHOLD"
    printf '%s\n' "$CURRENT" | grep -v '^$'
  } > "$RATCHET"
  echo "  accepted: $NCUR finding(s) now baselined (was $NBASE)"
  [ -n "$ADDED" ] && { echo "  ADDED:"; printf '%s\n' "$ADDED" | sed 's/^/    /'; }
  [ -n "$GONE" ]  && { echo "  REMOVED:"; printf '%s\n' "$GONE"  | sed 's/^/    /'; }
  exit 0
fi

echo "  scanned ${#SOURCES[@]} prompt source(s), threshold=$THRESHOLD, $NCUR finding(s), $NBASE baselined"
if [ -n "$GONE" ]; then
  # Not a failure -- the ratchet is never lowered automatically, same as
  # bin/shellcheck-lint.sh. But it is said out loud, because a baseline
  # holding entries that no longer exist is a baseline nobody is reading.
  echo "  note: baselined duplication(s) no longer present -- run --accept to lower the ratchet:"
  printf '%s\n' "$GONE" | sed 's/^/    /'
fi
if [ -n "$ADDED" ]; then
  bad "NEW duplicated prompt text -- one copy can go stale while the other is updated"
  echo "        Extract it into a schedule/_*.md fragment and opt the confs in with"
  echo "        USES_STANDING_RULES (see bin/scheduler-run), or, if it is genuinely"
  echo "        meant to be two texts, re-accept the ratchet and say why in the commit."
  printf '%s\n' "$FINDINGS" | while IFS=$'\t' read -r a b h n ar br first; do
    printf '%s\n' "$ADDED" | grep -qF "$a	$b	$h" && \
      echo "    $a:$ar == $b:$br  ($n lines, $h)" && echo "      first line: $first"
  done
else
  ok "no duplicated prompt text beyond the $NBASE baselined block(s)"
fi

echo
echo "conf-prompt-duplication-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
