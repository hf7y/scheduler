#!/usr/bin/env bash
# Witness for @@FRAGMENT:<name>@@ marker substitution in bin/scheduler-run.
#
# THE DEFECT THIS RETIRES (hf7y/scheduler#98). USES_STANDING_RULES prepends
# one fragment at the TRUE HEAD of PROMPT -- see the comment above it in
# bin/scheduler-run. That is the right shape for a block whose own first
# line reads "These override everything below", but #98's two duplicated
# blocks (ecosim.conf/vim-arcade.conf's triage rules and verdict semantics)
# sit MID-PROMPT, wrapped in project-specific prose on both sides. A second
# boolean cannot place a fragment in the middle of a string; a marker can.
#
# THIS IS ADDITIVE, NOT A REPLACEMENT. USES_STANDING_RULES keeps working
# exactly as tests/standing-rules-witness.sh already proves -- this witness
# only exercises the new marker substitution, and case 5 below confirms the
# two mechanisms compose (a conf can use both at once).
#
# Asserts:
#   1. @@FRAGMENT:name@@ is replaced with schedule/_name.md's contents,
#      in place -- prose before and after the marker survives, in order.
#   2. two distinct markers in one PROMPT both resolve.
#   3. the same fragment referenced twice in one PROMPT resolves both times.
#   4. missing fragment file => exit 2, loud, nothing dispatched.
#   5. composes with USES_STANDING_RULES: the prepended block AND a
#      mid-prompt marker both resolve in the same run.
#   6. the substituted text is inert -- $(cat) into a variable, never
#      evaled, same guarantee as the standing-rules extraction.
#   7. real wiring: schedule/_triage-rules.md and schedule/_verdict-
#      semantics.md exist, ecosim.conf and vim-arcade.conf reference them
#      via marker, and neither still carries an inlined copy.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- fixture repo, same shape as tests/standing-rules-witness.sh -----------
FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"

mkconf() {  # $1=name, rest=lines
  local name="$1"; shift
  { echo 'REPO_URL="https://example.invalid/fixture.git"'; printf '%s\n' "$@"; } \
    > "$FX/schedule/$name.conf"
}

run() {  # $1=project $2=tier -- echoes the assembled prompt
  ( cd "$FX" && bash bin/scheduler-run "$1" "$2" 2>"$TMP/err" )
}

echo "== case 1: a single marker resolves in place"
printf 'FRAGMENT BODY LINE ONE.\nFRAGMENT BODY LINE TWO.\n' > "$FX/schedule/_frag-a.md"
mkconf single 'BATCH_JOB_NAME="single-batch"' \
              'BATCH_PROMPT="BEFORE THE MARKER.
@@FRAGMENT:frag-a@@
AFTER THE MARKER."'
out="$(run single batch)"; rc=$?
case "$out" in
  "BEFORE THE MARKER."*"FRAGMENT BODY LINE ONE."*"FRAGMENT BODY LINE TWO."*"AFTER THE MARKER.") \
    ok "prose before and after the marker survives, fragment resolved in between" ;;
  *) bad "marker did not resolve in place: rc=$rc out=[$out]" ;;
esac
case "$out" in *'@@FRAGMENT:'*) bad "raw marker token leaked into the prompt: [$out]" ;; *) ok "no raw marker token left in the prompt" ;; esac

echo "== case 2: two distinct markers both resolve"
printf 'SECOND FRAGMENT BODY.\n' > "$FX/schedule/_frag-b.md"
mkconf twomark 'BATCH_JOB_NAME="twomark-batch"' \
               'BATCH_PROMPT="ONE: @@FRAGMENT:frag-a@@ TWO: @@FRAGMENT:frag-b@@ DONE."'
out="$(run twomark batch)"
case "$out" in
  *"FRAGMENT BODY LINE ONE."*"SECOND FRAGMENT BODY."*) ok "both distinct markers resolved" ;;
  *) bad "not all markers resolved: [$out]" ;;
esac

echo "== case 3: the same fragment referenced twice both resolve"
mkconf repeatmark 'BATCH_JOB_NAME="repeatmark-batch"' \
                  'BATCH_PROMPT="FIRST: @@FRAGMENT:frag-b@@ SECOND: @@FRAGMENT:frag-b@@ DONE."'
out="$(run repeatmark batch)"
n="$(printf '%s' "$out" | grep -o 'SECOND FRAGMENT BODY.' | wc -l)"
if [ "$n" -eq 2 ]; then ok "a fragment referenced twice resolves both occurrences"
else bad "expected 2 resolutions, got $n: [$out]"; fi

echo "== case 4: missing fragment -- loud, not silent"
mkconf missing 'BATCH_JOB_NAME="missing-batch"' \
               'BATCH_PROMPT="HAS A @@FRAGMENT:does-not-exist@@ IN IT."'
out="$(run missing batch)"; rc=$?
err="$(cat "$TMP/err")"
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
  ok "missing fragment exits 2 with no prompt emitted (rc=$rc)"
else
  bad "missing fragment did not fail loud: rc=$rc out=[$out]"
fi
case "$err" in
  *"_does-not-exist.md"*) ok "and says which file, on stderr" ;;
  *) bad "no usable error message naming the missing file: [$err]" ;;
esac

echo "== case 5: composes with USES_STANDING_RULES"
cat > "$FX/schedule/_standing-rules.md" <<'EOF'
STANDING RULES (fixture). These override everything below.
EOF
mkconf both 'BATCH_JOB_NAME="both-batch"' \
            'BATCH_PROMPT="OWN HEAD. @@FRAGMENT:frag-a@@ OWN TAIL."' \
            'USES_STANDING_RULES=1'
out="$(run both batch)"
first="$(printf '%s' "$out" | head -1)"
if [ "$first" = "STANDING RULES (fixture). These override everything below." ]; then
  ok "standing rules still prepended at the true head"
else
  bad "standing-rules prepend regressed: first=[$first]"
fi
case "$out" in
  *"OWN HEAD."*"FRAGMENT BODY LINE ONE."*"OWN TAIL."*) ok "and the mid-prompt marker still resolved" ;;
  *) bad "marker substitution did not compose with the prepend: [$out]" ;;
esac

echo "== case 6: substituted text is inert"
MARK="$TMP/executed.marker"
printf '0. Do not run `touch %s` by hand.\n' "$MARK" > "$FX/schedule/_frag-exec.md"
mkconf inert 'BATCH_JOB_NAME="inert-batch"' \
             'BATCH_PROMPT="HEAD. @@FRAGMENT:frag-exec@@ TAIL."'
out="$(run inert batch)"
if [ ! -e "$MARK" ]; then
  ok "a backtick in the fragment does not execute"
else
  bad "the fragment EXECUTED: $MARK was created"
fi
rm -f "$MARK"
case "$out" in
  *"Do not run \`touch $MARK\` by hand."*) ok "and reaches the prompt literally" ;;
  *) bad "literal text did not survive into the prompt: [$out]" ;;
esac

echo "== case 7: real wiring"
for f in triage-rules verdict-semantics; do
  p="$ROOT/schedule/_$f.md"
  if [ -s "$p" ]; then ok "schedule/_$f.md exists and is non-empty"
  else bad "schedule/_$f.md missing or empty: $p"; fi
done
for c in ecosim vim-arcade; do
  conf="$ROOT/schedule/$c.conf"
  for f in triage-rules verdict-semantics; do
    if grep -qF "@@FRAGMENT:$f@@" "$conf" 2>/dev/null; then
      ok "$c.conf references @@FRAGMENT:$f@@"
    else
      bad "$c.conf does not reference @@FRAGMENT:$f@@"
    fi
  done
done
# No conf should carry an inlined copy of either fragment's first line.
for f in triage-rules verdict-semantics; do
  head1="$(head -1 "$ROOT/schedule/_$f.md" 2>/dev/null)"
  [ -n "$head1" ] || continue
  INLINED=""
  for c in "$ROOT"/schedule/*.conf; do
    grep -qF "$head1" "$c" && INLINED="$INLINED $(basename "$c")"
  done
  if [ -z "$INLINED" ]; then ok "no conf re-inlines _$f.md's first line"
  else bad "_$f.md re-inlined into:$INLINED"; fi
done

echo
echo "fragment-marker-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
