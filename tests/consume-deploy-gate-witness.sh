#!/usr/bin/env bash
# Witness for the deadlock in hf7y/scheduler#61 / #70: the engine dirtying the
# very file its own deploy gate refuses to pull past.
#
# THE BUG. lib/sweep-loop-common.sh calls bin/collect-feedback.sh --consume on
# the repo's TRACKED BLOCKERS.md. bin/usage-paced-runner.sh then gates its
# pull-before-dispatch on `git status --porcelain --untracked-files=no`. So the
# FIRST consumed tag on a host froze that host's code at whatever commit it
# was on, permanently, with one `PULL skip` line in a log nobody reads as the
# only symptom. PR #59 merged 2026-08-06T20:02Z to fix vim-arcade's brief; five
# days later it still had not run, because that clone could not pull.
#
# WHAT THIS ASSERTS, and the order is the argument:
#   1. the pull gate GENUINELY BLOCKS on a dirty tracked file. Without this
#      case, everything below could pass on a gate that does nothing at all.
#   2. a --consume of a real reply out of a real tracked BLOCKERS.md leaves the
#      tree clean, and the very next tick of the REAL gate fast-forwards.
#   3. consumption is idempotent through a fresh process -- the record has to
#      survive somewhere, and "somewhere" is now the state dir, not the file.
#   4. an in-repo `>>` marker from the OLD behaviour still suppresses, AND is
#      seeded into the ledger, so `git restore` on a clone still carrying one
#      (vim-arcade, crt) does not un-consume what a run already acted on.
#   5. nothing at all is written inside the repo -- not even an untracked file.
#
# The gate is not re-implemented here. It is LIFTED out of
# bin/usage-paced-runner.sh by its markers and executed, against a real origin
# and a real clone, because the whole failure was two real components
# disagreeing -- a mock of either one would have agreed with itself.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
COLLECT="$ROOT/bin/collect-feedback.sh"
[ -f "$RUNNER" ]  || { echo "runner not found: $RUNNER"; exit 1; }
[ -x "$COLLECT" ] || { echo "collect-feedback.sh not found/executable: $COLLECT"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# --- lift the real pull gate out of the dispatcher ---------------------------
# Running bin/usage-paced-runner.sh outright would take the global flock and
# DISPATCH. Extract by marker instead; an extraction that stops matching is a
# failure, never a pass by absence (same rule as tests/sched-root-witness.sh).
BLOCK="$TMP/pull-gate.sh"
awk '/^# >>> pull gate/,/^# <<< pull gate/' "$RUNNER" > "$BLOCK"
grep -q 'untracked-files=no' "$BLOCK" \
  || { echo "FAIL: could not extract the pull gate block from $RUNNER"; exit 1; }
grep -q 'merge --ff-only' "$BLOCK" \
  || { echo "FAIL: extracted block has no pull in it -- it cannot be the gate"; exit 1; }

GATE="$TMP/bin/gate.sh"
mkdir -p "$TMP/bin"
{ printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'STATE_DIR="$1"; REPO_ROOT="$2"\n'
  printf 'JOB_NAME="scheduler-paced-runner"\nPACED_HOST="witnesshost"\n'
  printf 'LOG="$STATE_DIR/run.log"\nmkdir -p "$STATE_DIR"\n'
  printf 'log() { echo "$(date -Is) $*" >> "$LOG"; }\n'
  cat "$BLOCK"; } > "$GATE"
chmod +x "$GATE"

# --- fixtures ----------------------------------------------------------------
git_q() { git -c init.defaultBranch=main -c user.email=w@w -c user.name=w "$@"; }

BLOCKERS_BODY='# Blockers

## demoproj

- **the setting** somebody has to flip it in a browser
> flipped it, go ahead
'

ORIGIN="$TMP/origin.git"
SEED="$TMP/seed"
git_q init --bare -q "$ORIGIN"
git_q init -q "$SEED"
printf '%s' "$BLOCKERS_BODY" > "$SEED/BLOCKERS.md"
echo v1 > "$SEED/code.sh"
git_q -C "$SEED" add -A
git_q -C "$SEED" commit -qm "seed"
git_q -C "$SEED" remote add origin "$ORIGIN"
git_q -C "$SEED" push -q origin main

CLONE="$TMP/clone"
git_q clone -q "$ORIGIN" "$CLONE"
PINNED="$(git -C "$CLONE" rev-parse HEAD)"

# A commit lands upstream -- the merged fix this host must receive.
echo v2 > "$SEED/code.sh"
git_q -C "$SEED" commit -qam "the merged fix that has to reach the dispatcher"
git_q -C "$SEED" push -q origin main
UPSTREAM="$(git -C "$SEED" rev-parse HEAD)"

STATE="$TMP/state"
LEDGER_DIR="$TMP/share/scheduler-glance"
export SCHEDULER_RECEIPT_DIR="$LEDGER_DIR"

head_of()  { git -C "$CLONE" rev-parse HEAD; }
dirty_of() { git -C "$CLONE" status --porcelain --untracked-files=no; }
logtail()  { tail -n 20 "$STATE/run.log" 2>/dev/null; }

# --- 1. the gate really does block ------------------------------------------
# Establish that the thing under test can fail, before asserting it does not.
echo "== 1. a dirty TRACKED file blocks the pull (the gate is real)"
echo "hand edit" >> "$CLONE/code.sh"
"$GATE" "$STATE" "$CLONE" >/dev/null 2>&1
if [ "$(head_of)" = "$PINNED" ]; then ok "clone stayed pinned at ${PINNED:0:7}"
else bad "clone moved despite a dirty tracked file -- the gate does nothing"; fi
if logtail | grep -q 'PULL skip -- .* uncommitted changes to TRACKED files'; then
  ok "logged the skip"
else bad "no PULL skip line: $(logtail)"; fi
git -C "$CLONE" checkout -q -- code.sh

# --- 2. a consume does not trip that gate ------------------------------------
echo "== 2. --consume on the tracked BLOCKERS.md, then the very next tick pulls"
OUT="$("$COLLECT" "$CLONE/BLOCKERS.md" --section demoproj --consume)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$OUT" | grep -q 'flipped it, go ahead'; then
  ok "the reply was collected (rc=0)"
else bad "consume collected nothing -- the rest of this witness would be vacuous (rc=$rc)"; fi
if [ -z "$(dirty_of)" ]; then ok "tree is CLEAN after --consume"
else bad "--consume dirtied tracked files: $(dirty_of)"; fi

"$GATE" "$STATE" "$CLONE" >/dev/null 2>&1
if [ "$(head_of)" = "$UPSTREAM" ]; then ok "clone fast-forwarded to ${UPSTREAM:0:7} -- the deadlock does not happen"
else bad "clone did NOT pull: at $(head_of), origin/main at $UPSTREAM"; fi
if logtail | grep -q 'PULL fast-forwarded'; then ok "logged the fast-forward"
else bad "no fast-forward line: $(logtail)"; fi

# --- 3. the record persists across processes ---------------------------------
echo "== 3. consumption is idempotent -- a second run is not handed it again"
"$COLLECT" "$CLONE/BLOCKERS.md" --section demoproj --consume >/dev/null 2>&1; rc2=$?
if [ "$rc2" -ne 0 ]; then ok "second --consume collected nothing (rc=$rc2)"
else bad "the same reply was collected twice -- the record did not persist"; fi
if [ -z "$(dirty_of)" ]; then ok "tree still clean after the second pass"
else bad "second --consume dirtied the tree: $(dirty_of)"; fi
if [ -f "$LEDGER_DIR/consumed-entries.tsv" ] \
   && grep -q 'flipped it, go ahead' "$LEDGER_DIR/consumed-entries.tsv"; then
  ok "the record is in the state dir, not the repo"
else bad "no ledger row under $LEDGER_DIR"; fi
if "$COLLECT" "$CLONE/BLOCKERS.md" --list-consumed | grep -q 'flipped it, go ahead'; then
  ok "--list-consumed reads it back (the marker the file used to carry)"
else bad "--list-consumed did not report the consumed entry"; fi

# --- 4. migration: an OLD in-repo >> marker ----------------------------------
# This is vim-arcade's and crt's live state: an uncommitted in-file marker from
# a run that already acted. It must keep suppressing, and it must survive the
# `git restore` that will eventually clear those clones.
echo "== 4. an old in-file >> marker still suppresses, and survives git restore"
LEGACY="$TMP/legacy"
git_q init -q "$LEGACY"
printf '%s' '# Blockers

## demoproj

- **the setting** somebody has to flip it in a browser
> flipped it, go ahead
' > "$LEGACY/BLOCKERS.md"
git_q -C "$LEGACY" add -A
git_q -C "$LEGACY" commit -qm seed
# exactly the shape the pre-2026-08-11 --consume wrote, in the working tree only
printf '%s' '# Blockers

## demoproj

- **the setting** somebody has to flip it in a browser
>> _[consumed 2026-08-08 -- read by a run; this entry is
>> still OPEN until something deletes it]_
>> flipped it, go ahead
' > "$LEGACY/BLOCKERS.md"

"$COLLECT" "$LEGACY/BLOCKERS.md" --section demoproj --consume >/dev/null 2>&1; rc3=$?
if [ "$rc3" -ne 0 ]; then ok "the >> marker still suppresses collection (rc=$rc3)"
else bad "an already-consumed entry was re-collected"; fi
if grep -q 'flipped it, go ahead' "$LEDGER_DIR/consumed-entries.tsv"; then
  ok "the legacy marker was seeded into the ledger"
else bad "legacy marker not seeded -- a git restore would un-consume it"; fi

git -C "$LEGACY" checkout -q -- BLOCKERS.md      # the remediation that was unsafe
if grep -q '^> flipped it, go ahead' "$LEGACY/BLOCKERS.md"; then
  ok "git restore put the plain '> ' reply back (the un-consuming move)"
else bad "fixture wrong: restore did not reinstate the '> ' reply"; fi
"$COLLECT" "$LEGACY/BLOCKERS.md" --section demoproj --consume >/dev/null 2>&1; rc4=$?
if [ "$rc4" -ne 0 ]; then ok "still consumed AFTER the restore -- the record outlived the file"
else bad "git restore un-consumed the entry; the run would be handed it again"; fi

# --- 5. nothing is written into the repo at all ------------------------------
echo "== 5. the repo is untouched, tracked and untracked alike"
if [ -z "$(git -C "$CLONE" status --porcelain)" ]; then
  ok "no tracked modification and no stray untracked file in the clone"
else bad "something was written into the repo: $(git -C "$CLONE" status --porcelain)"; fi

echo
echo "consume-deploy-gate-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
