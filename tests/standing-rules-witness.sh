#!/usr/bin/env bash
# Witness for the shared standing-rules block -- schedule/_standing-rules.md
# and the prepend in bin/scheduler-run.
#
# THE DEFECT THIS RETIRES: commit 9cfd130 (2026-08-07) hand-typed one
# identical "STANDING RULES" block into THREE separate BATCH_PROMPT strings
# (ecosim, vim-arcade, bibliothecaire) as independent copy-pasted text. Nothing
# held them equal, so the next rules edit meant retyping into all three and
# hoping nobody missed one -- the "retyping is the distribution mechanism"
# failure this ecosystem keeps paying for. The block now lives in ONE file and
# is prepended at dispatch.
#
# Asserts, and 3 and 5 are the ones that rot:
#   1. an opted-in conf gets the file's text at the HEAD of its prompt, its
#      own prompt intact below -- prepended, not interleaved, because the
#      block's first line claims "These override everything below" and that
#      is only true at the head
#   2. a conf that never opted in is untouched (chezz, crt, baudin ... never
#      had this text; acquiring it as a side effect of an engine change is
#      the surprise the opt-in exists to prevent)
#   3. the opt-in resolves PER TIER first, project-level second. Project-level
#      alone is indistinguishable from correct today only because no conf arms
#      SWEEP; the day one does, "whichever tier is dispatching" silently stops
#      meaning "batch"
#   4. flag set + file missing => exit 2, loud, never a dispatch with the
#      rules quietly absent
#   5. the extracted text is INERT. This is the half that is easy to lose: in
#      a conf it was the right-hand side of BATCH_PROMPT="...", so a backtick
#      in it EXECUTED at `source` time. Read from a .md by $(cat) into a
#      variable it does not. Case 5b re-proves the old hazard is real, so
#      "inert" is a measured difference and not an assumption.
#   6. real wiring: the three real confs opt in, the real file exists, and
#      none of them still carries an inlined copy
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
REAL_RULES="$ROOT/schedule/_standing-rules.md"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- fixture repo -----------------------------------------------------------
# A throwaway tree shaped like this one, running the REAL bin/scheduler-run
# (SCHED_ROOT is derived from the script's own location, so a copy governs the
# tree it sits in). The engine and the freeze gate are stubs: this witness is
# about the assembled PROMPT, and it must never dispatch anything.
FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
# Stands in for lib/sweep-loop-common.sh, which scheduler-run sources last.
# Printing PROMPT and exiting is the whole engine as far as this test cares.
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"

cat > "$FX/schedule/_standing-rules.md" <<'EOF'
STANDING RULES (fixture). These override everything below.

0. FIRST RULE, fixture text.
1. SECOND RULE, fixture text.
EOF

mkconf() {  # $1=name, rest=lines
  local name="$1"; shift
  { echo 'REPO_URL="https://example.invalid/fixture.git"'; printf '%s\n' "$@"; } \
    > "$FX/schedule/$name.conf"
}

run() {  # $1=project $2=tier -- echoes the assembled prompt, returns its rc
  ( cd "$FX" && bash bin/scheduler-run "$1" "$2" 2>"$TMP/err" )
}

echo "== case 1: opted in -- rules at the head, own prompt intact below"
mkconf optin 'BATCH_JOB_NAME="optin-batch"' \
             'BATCH_PROMPT="OWN PROMPT LINE."' \
             'USES_STANDING_RULES=1'
out="$(run optin batch)"; rc=$?
first="$(printf '%s' "$out" | head -1)"
if [ "$rc" -eq 0 ] && [ "$first" = "STANDING RULES (fixture). These override everything below." ]; then
  ok "the rules file's first line is the prompt's first line"
else
  bad "expected rules at the head, got rc=$rc first=[$first]"
fi
case "$out" in
  *"1. SECOND RULE, fixture text."*"OWN PROMPT LINE."*) ok "own prompt survives, below the rules" ;;
  *) bad "own prompt missing or out of order: [$out]" ;;
esac

echo "== case 2: never opted in -- untouched"
mkconf optout 'BATCH_JOB_NAME="optout-batch"' \
              'BATCH_PROMPT="OWN PROMPT LINE."'
out="$(run optout batch)"
if [ "$out" = "OWN PROMPT LINE." ]; then
  ok "a conf without the flag gets exactly its own prompt"
else
  bad "non-participating conf was modified: [$out]"
fi

echo "== case 3: per-tier beats project-level"
# Project says yes, BATCH says no. If the per-tier field were ignored -- the
# shape this started as -- batch would still get the rules here.
mkconf pertier 'BATCH_JOB_NAME="pertier-batch"' \
               'BATCH_PROMPT="BATCH OWN."' \
               'SWEEP_JOB_NAME="pertier-sweep"' \
               'SWEEP_PROMPT="SWEEP OWN."' \
               'USES_STANDING_RULES=1' \
               'BATCH_USES_STANDING_RULES=0'
out="$(run pertier batch)"
if [ "$out" = "BATCH OWN." ]; then
  ok "BATCH_USES_STANDING_RULES=0 opts one tier out of a project-level yes"
else
  bad "per-tier opt-out ignored: [$out]"
fi
out="$(run pertier sweep)"
case "$out" in
  "STANDING RULES (fixture)."*"SWEEP OWN.") ok "the other tier still inherits the project-level yes" ;;
  *) bad "sweep tier lost the project-level opt-in: [$out]" ;;
esac
# And the reverse: no project-level field at all, one tier opting itself in.
mkconf tieronly 'BATCH_JOB_NAME="tieronly-batch"' \
                'BATCH_PROMPT="BATCH OWN."' \
                'SWEEP_JOB_NAME="tieronly-sweep"' \
                'SWEEP_PROMPT="SWEEP OWN."' \
                'SWEEP_USES_STANDING_RULES=1'
out="$(run tieronly sweep)"
case "$out" in "STANDING RULES (fixture)."*) ok "a tier can opt itself in with no project-level field" ;;
  *) bad "per-tier opt-in did not apply: [$out]" ;;
esac
out="$(run tieronly batch)"
if [ "$out" = "BATCH OWN." ]; then ok "and that does not leak to the other tier"
else bad "per-tier opt-in leaked across tiers: [$out]"; fi

echo "== case 4: flag set, file missing -- loud, not silent"
mv "$FX/schedule/_standing-rules.md" "$TMP/rules.parked"
out="$(run optin batch)"; rc=$?
err="$(cat "$TMP/err")"
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
  ok "missing rules file exits 2 with no prompt emitted (rc=$rc)"
else
  bad "missing rules file did not fail loud: rc=$rc out=[$out]"
fi
case "$err" in
  *"_standing-rules.md is missing"*) ok "and says which file, on stderr" ;;
  *) bad "no usable error message: [$err]" ;;
esac
mv "$TMP/rules.parked" "$FX/schedule/_standing-rules.md"

echo "== case 5: the extracted text is inert, and the old hazard was real"
MARK="$TMP/executed.marker"
cat > "$FX/schedule/_standing-rules.md" <<EOF
STANDING RULES (fixture). These override everything below.

0. Do not run \`touch $MARK\` by hand.
EOF
out="$(run optin batch)"
if [ ! -e "$MARK" ]; then
  ok "a backtick in the .md does not execute -- \$(cat) into a variable, never evaled"
else
  bad "the rules file EXECUTED: $MARK was created"
fi
rm -f "$MARK"
case "$out" in
  *"Do not run \`touch $MARK\` by hand."*) ok "and reaches the prompt literally, backticks and all" ;;
  *) bad "literal text did not survive into the prompt: [$out]" ;;
esac
# 5b -- the same characters INSIDE a conf's BATCH_PROMPT, which is where they
# lived before the extraction. `source` evaluates that string. If this stops
# executing, the contrast above has stopped being a difference and case 5 is
# passing for a reason that no longer holds.
mkconf inlined 'BATCH_JOB_NAME="inlined-batch"' \
               "BATCH_PROMPT=\"0. Do not run \`touch $MARK\` by hand.\""
run inlined batch >/dev/null
if [ -e "$MARK" ]; then
  ok "the same text inlined in a conf DOES execute at source time (hazard confirmed)"
else
  bad "could not reproduce the inlined-prose hazard -- case 5 proves nothing"
fi
rm -f "$MARK"

echo "== case 6: real wiring"
if [ -s "$REAL_RULES" ]; then
  ok "schedule/_standing-rules.md exists and is non-empty"
else
  bad "schedule/_standing-rules.md missing or empty: $REAL_RULES"
fi
# First line of the real block, used below to prove no conf re-inlines it.
RULES_HEAD="$(head -1 "$REAL_RULES" 2>/dev/null)"
for p in ecosim vim-arcade bibliothecaire; do
  c="$ROOT/schedule/$p.conf"
  if grep -q '^USES_STANDING_RULES=1$' "$c" 2>/dev/null; then
    ok "$p.conf opts in"
  else
    bad "$p.conf no longer sets USES_STANDING_RULES=1"
  fi
done
INLINED=""
for c in "$ROOT"/schedule/*.conf; do
  [ -n "$RULES_HEAD" ] || break
  grep -qF "$RULES_HEAD" "$c" && INLINED="$INLINED $(basename "$c")"
done
if [ -z "$INLINED" ]; then
  ok "no conf carries an inlined copy of the block's first line"
else
  bad "block re-inlined into:$INLINED"
fi

echo
echo "standing-rules-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
