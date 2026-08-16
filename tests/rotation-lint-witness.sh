#!/usr/bin/env bash
# Witness for bin/rotation-lint.sh -- "is any project enabled in more than one
# host's rotation file?", i.e. CROSS-HOST DOUBLE DISPATCH, the direction
# bin/sync-crontab.sh's own guard does not cover (that one asks the fixed-cron
# question: a crontab line vs. rotation membership).
#
# THE HAZARD, stated so a failure here is legible: mandark and dexter run
# bin/usage-paced-runner.sh out of ONE git-tracked repo, each reading its own
# schedule/_paced*.conf, with no shared lock (2026-07-24: full local peer).
# A project enabled in two of them is dispatched twice, into one git history.
# Until 2026-07-29 the only thing preventing it was whoever edited the files
# remembering to do both halves in one change -- a rule those files state in
# capitals four times over, which is the shape of a latent bug, not a control.
#
# What must hold, and cases 4-6 are what keep this honest: a check that FLAGs
# everything passes 1-3 and nothing else.
#   1. enabled=1 in two rotation files             -> FINDING, rc=1
#   2. enabled=1 three times                       -> FINDING names all three
#   3. same name listed twice in ONE file          -> FINDING, rc=1
#   4. enabled in one file, parked in the other    -> CLEAN (the normal
#      post-move state -- every host move produces exactly this)
#   5. enabled NOWHERE                             -> CLEAN, deliberately;
#      parked-on-purpose and lost-in-a-move are the same bytes (see the
#      script header's "what is deliberately NOT checked")
#   6. COMMENTED OUT in one file                   -> CLEAN (the documented
#      rollback path back to a fixed nightly cron line)
#   7. no rotation file at all                     -> BLIND rc=3, never "clean"
#   8. the enabled predicate still matches bin/usage-paced-runner.sh's
#   9. it is WIRED into `scheduler sweep`, not merely built
#  10. the REAL schedule/ in the tree this witness ships in is clean
#
# Fixtures are synthetic trees built from the tree under test -- no real
# project's conf can make cases 1-7 pass or fail. Case 10 is the one that
# reads live data, on purpose, and is the regression guard for the ecosystem
# itself. Read-only throughout: this check never writes a conf, a crontab, or
# a git object.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/bin/rotation-lint.sh"
[ -f "$LINT" ] || { echo "script under test not found: $LINT"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# Keep the fixtures' runtime witnesses out of the real ~/.local/share -- a
# test must not make an unwired check look wired in the next `scheduler sweep`.
export CHECK_WITNESS_DIR="$TMP/witness"

# run_case <name> -- builds $TMP/<name>/schedule from the heredocs the caller
# already wrote, runs the lint against it, and leaves OUT/RC set.
OUT=""; RC=0
run_case() {
  OUT="$(SCHED_ROOT="$TMP/$1" bash "$LINT" 2>&1)"; RC=$?
}
new_case() { mkdir -p "$TMP/$1/schedule" "$TMP/$1/lib"; cp "$ROOT/lib/check-witness.sh" "$TMP/$1/lib/"; }

echo "== 1. enabled in two rotation files is a FINDING"
new_case c1
cat > "$TMP/c1/schedule/_paced.conf" <<'EOF'
alpha|1|2|/bin/true
beta|0|/bin/true
EOF
cat > "$TMP/c1/schedule/_paced.dexter.conf" <<'EOF'
alpha|1|/bin/true
gamma|1|/bin/true
EOF
run_case c1
[ "$RC" -eq 1 ] && ok "rc=1" || bad "expected rc=1, got $RC"
printf '%s\n' "$OUT" | grep -q "DOUBLE DISPATCH: 'alpha'" \
  && ok "names alpha" || bad "did not name alpha -- output: $OUT"
printf '%s\n' "$OUT" | grep -q 'shared/default:1' \
  && ok "names the shared file and its line" || bad "did not locate the shared-file line"
printf '%s\n' "$OUT" | grep -q 'dexter:1' \
  && ok "names the dexter file and its line" || bad "did not locate the dexter line"
printf '%s\n' "$OUT" | grep -q "'gamma'" \
  && bad "flagged gamma, which is enabled in only one rotation" || ok "does not flag gamma (one rotation only)"
printf '%s\n' "$OUT" | grep -q "'beta'" \
  && bad "flagged beta, which is enabled nowhere" || ok "does not flag beta (enabled nowhere)"

echo "== 2. three rotations, all three named"
new_case c2
printf 'alpha|1|/bin/true\n' > "$TMP/c2/schedule/_paced.conf"
printf 'alpha|1|/bin/true\n' > "$TMP/c2/schedule/_paced.dexter.conf"
printf 'alpha|1|/bin/true\n' > "$TMP/c2/schedule/_paced.mandark.conf"
run_case c2
[ "$RC" -eq 1 ] && ok "rc=1" || bad "expected rc=1, got $RC"
printf '%s\n' "$OUT" | grep -q 'enabled=1 in 3 rotations' \
  && ok "reports the count as 3" || bad "did not report 3 rotations -- output: $OUT"
for h in shared/default dexter mandark; do
  printf '%s\n' "$OUT" | grep -q "$h:1" && ok "names $h" || bad "did not name $h"
done

echo "== 3. the same name twice in ONE file is a FINDING"
new_case c3
cat > "$TMP/c3/schedule/_paced.conf" <<'EOF'
alpha|1|/bin/true
beta|1|/bin/true
alpha|0|/bin/true
EOF
run_case c3
[ "$RC" -eq 1 ] && ok "rc=1" || bad "expected rc=1, got $RC"
printf '%s\n' "$OUT" | grep -q "_paced.conf:3: DUPLICATE 'alpha'" \
  && ok "names the file, the SECOND line, and the project" || bad "wrong duplicate location -- output: $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c DUPLICATE)" -eq 1 ] \
  && ok "reports the duplicate once, not once per copy" || bad "duplicate reported more than once"
printf '%s\n' "$OUT" | grep -q 'DOUBLE DISPATCH' \
  && bad "also claimed cross-host double dispatch for a single-file duplicate" \
  || ok "does not confuse a same-file duplicate with a cross-host one"

echo "== 4. enabled here, parked there is CLEAN -- the normal post-move state"
new_case c4
printf 'alpha|0|0|/bin/true\nbeta|1|/bin/true\n' > "$TMP/c4/schedule/_paced.conf"
printf 'alpha|1|3|/bin/true\n'                   > "$TMP/c4/schedule/_paced.dexter.conf"
run_case c4
[ "$RC" -eq 0 ] && ok "rc=0" || bad "expected rc=0, got $RC -- output: $OUT"
printf '%s\n' "$OUT" | grep -q '0 finding' \
  && ok "reports 0 findings" || bad "did not report 0 findings"
printf '%s\n' "$OUT" | grep -q '3 participant line' \
  && ok "still counted all 3 participant lines (clean, not blind)" \
  || bad "wrong scan count -- a clean result with nothing scanned is the trap this guards"

echo "== 5. enabled NOWHERE is CLEAN, deliberately"
new_case c5
printf 'alpha|0|/bin/true\n' > "$TMP/c5/schedule/_paced.conf"
printf 'alpha|0|/bin/true\n' > "$TMP/c5/schedule/_paced.dexter.conf"
run_case c5
[ "$RC" -eq 0 ] && ok "rc=0 (parked-on-purpose and lost-in-a-move are the same bytes)" \
  || bad "expected rc=0, got $RC -- output: $OUT"

echo "== 6. COMMENTED OUT in one file is CLEAN -- the rollback path"
new_case c6
printf '#alpha|1|3|/bin/true\n'   > "$TMP/c6/schedule/_paced.conf"
printf 'alpha|1|/bin/true\n'      > "$TMP/c6/schedule/_paced.dexter.conf"
run_case c6
[ "$RC" -eq 0 ] && ok "rc=0" || bad "expected rc=0, got $RC -- output: $OUT"
printf '%s\n' "$OUT" | grep -q '1 participant line' \
  && ok "counted the commented line as not-a-participant" || bad "miscounted the commented line"

echo "== 6b. an INDENTED line is a live participant, matching the dispatcher"
# bin/usage-paced-runner.sh tests for a leading '#' BEFORE stripping spaces,
# so ' alpha|1|...' dispatches. A lint that trimmed first would silently
# disagree with what actually runs -- in the direction that misses a finding.
new_case c6b
printf ' alpha|1|/bin/true\n' > "$TMP/c6b/schedule/_paced.conf"
printf 'alpha|1|/bin/true\n'  > "$TMP/c6b/schedule/_paced.dexter.conf"
run_case c6b
[ "$RC" -eq 1 ] && ok "indented + plain = still a collision (rc=1)" \
  || bad "expected rc=1, got $RC -- an indented line was treated as a comment"

echo "== 7. no rotation file at all is BLIND, not clean"
new_case c7
run_case c7
[ "$RC" -eq 3 ] && ok "rc=3" || bad "expected rc=3 (BLIND), got $RC -- output: $OUT"
printf '%s\n' "$OUT" | grep -q 'BLIND' \
  && ok "says BLIND out loud" || bad "did not say BLIND"
printf '%s\n' "$OUT" | grep -qi 'NOT a clean result' \
  && ok "states that this is not a clean result" || bad "did not distinguish blind from clean"

echo "== 8. the enabled predicate still agrees with the live dispatcher"
# Not a second source of truth: the lint mirrors the runner's parse, and this
# asserts the runner's parse has not moved out from under it. If the runner
# changes how it reads `enabled`, this fails loud rather than letting the
# check quietly disagree with what dispatches.
RUNNER="$ROOT/bin/usage-paced-runner.sh"
if grep -qF '[ "${enabled// /}" = "1" ] || continue' "$RUNNER"; then
  ok "bin/usage-paced-runner.sh still tests \${enabled// /} = 1"
else
  bad "the dispatcher's enabled test changed -- re-derive bin/rotation-lint.sh against it"
fi
if grep -qF '[ "${enabled// /}" = "1" ]' "$LINT"; then
  ok "bin/rotation-lint.sh uses the identical test"
else
  bad "bin/rotation-lint.sh no longer uses the dispatcher's enabled test"
fi
if grep -qF 'case "$name" in '"''"'|\#*) continue ;; esac' "$RUNNER" \
   && grep -qF 'case "$name" in '"''"'|\#*) continue ;; esac' "$LINT"; then
  ok "both skip blank/comment lines by the same rule, before trimming"
else
  bad "the blank/comment rule differs between the dispatcher and the lint"
fi

echo "== 9. wired into \`scheduler sweep\`, not merely built"
# Static, and knowingly weak on its own -- a call site in a dead branch greps
# the same as a live one. The real proof is the runtime witness
# (lib/check-witness.sh), which bin/check-witness-lint.sh reads back and which
# would report this script as NEVER RUN if the pass below never executes.
if grep -q 'bin/rotation-lint.sh' "$ROOT/bin/scheduler"; then
  ok "bin/scheduler calls bin/rotation-lint.sh"
else
  bad "bin/rotation-lint.sh is not referenced by bin/scheduler -- built-but-unwired"
fi
if grep -qF 'check_witness "$(basename "${BASH_SOURCE[0]}")"' "$LINT"; then
  ok "leaves a runtime witness, so an unwiring later is caught"
else
  bad "no check_witness call -- check-witness-lint.sh cannot see this check"
fi

echo "== 10. the REAL rotation files in this tree are clean"
# The live-data regression guard. If a future host move lands only half of a
# paired edit, this is what goes red.
real_out="$(bash "$LINT" 2>&1)"; real_rc=$?
if [ "$real_rc" -eq 0 ]; then
  ok "$(printf '%s' "$real_out" | tail -1)"
elif [ "$real_rc" -eq 3 ]; then
  bad "the real schedule/ came back BLIND: $real_out"
else
  bad "the real schedule/ has a double-dispatch finding:"
  printf '%s\n' "$real_out" | sed 's/^/      /'
fi

echo
echo "rotation lint witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
