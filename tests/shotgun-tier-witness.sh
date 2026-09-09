#!/usr/bin/env bash
# Witness for the SHOTGUN tier in bin/scheduler-run (hf7y/scheduler#586).
#
# TWO THINGS SILENTLY UNDO A SHOTGUN. `Agent` missing from ALLOWED_TOOLS: the
# run still succeeds, as a nightly batch with a different name. And
# SELFDEV_IN_ACCOUNT left at `auto`: for an account whose name equals its
# project it resolves to the ONE checkout the batch owns, and points every
# subagent at it. Neither fails loudly, so both are asserted here.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$RUNNER" ] || { echo "usage-paced-runner.sh not found: $RUNNER"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- fixture repo, same shape as tests/fragment-marker-witness.sh ----------
FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
cp "$ROOT/lib/dose-common.sh" "$FX/lib/dose-common.sh"  # #350: scheduler-run now sources this unconditionally
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
# The stub reports the engine inputs, one per line.
cat > "$FX/lib/sweep-loop-common.sh" <<'STUB'
printf 'PREFIX=%s\n' "$PREFIX"
printf 'TIER=%s\n' "$TIER"
printf 'JOB_NAME=%s\n' "$JOB_NAME"
printf 'ALLOWED_TOOLS=%s\n' "${ALLOWED_TOOLS:-<unset>}"
printf 'MAX_TURNS=%s\n' "${MAX_TURNS:-<unset>}"
printf 'SELFDEV_IN_ACCOUNT=%s\n' "${SELFDEV_IN_ACCOUNT:-<unset>}"
printf 'PROMPT=%s\n' "$PROMPT"
exit 0
STUB

mkconf() {  # $1=name, rest=lines
  local name="$1"; shift
  { echo 'REPO_URL="https://example.invalid/fixture.git"'; printf '%s\n' "$@"; } \
    > "$FX/schedule/$name.conf"
}

run() {  # $1=project $2=tier -- echoes the stub's report
  ( cd "$FX" && bash bin/scheduler-run "$1" "$2" 2>"$TMP/err" )
}
field() { printf '%s' "$1" | sed -n "s/^$2=//p" | head -1; }

mkconf both \
  'BATCH_JOB_NAME="both-batch"' \
  'BATCH_PROMPT="batch brief"' \
  'BATCH_ALLOWED_TOOLS="Bash,Read"' \
  'SHOTGUN_JOB_NAME="both-shotgun"' \
  'SHOTGUN_PROMPT="shotgun brief"' \
  'SHOTGUN_ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep,Agent"' \
  'SHOTGUN_MAX_TURNS="240"'

echo "== case 1: the tier is selected and its own conf fields are read"
out="$(run both shotgun)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(field "$out" PREFIX)" = SHOTGUN ] && [ "$(field "$out" TIER)" = shotgun ]; then
  ok "shotgun selects PREFIX=SHOTGUN, TIER=shotgun"
else
  bad "tier not selected: rc=$rc PREFIX=$(field "$out" PREFIX) TIER=$(field "$out" TIER)"
fi
[ "$(field "$out" JOB_NAME)" = both-shotgun ] \
  && ok "reads SHOTGUN_JOB_NAME, not BATCH_JOB_NAME" \
  || bad "JOB_NAME=$(field "$out" JOB_NAME), wanted both-shotgun"
[ "$(field "$out" MAX_TURNS)" = 240 ] \
  && ok "reads SHOTGUN_MAX_TURNS" \
  || bad "MAX_TURNS=$(field "$out" MAX_TURNS), wanted 240"
case "$(field "$out" ALLOWED_TOOLS)" in
  *Agent*) ok "the conf's Agent-bearing SHOTGUN_ALLOWED_TOOLS reaches the engine" ;;
  *) bad "ALLOWED_TOOLS=$(field "$out" ALLOWED_TOOLS) -- no Agent, so nothing fans out" ;;
esac

echo "== case 2: shotgun forces its own clone; batch is left alone"
out="$(SELFDEV_IN_ACCOUNT=1 run both shotgun)"
[ "$(field "$out" SELFDEV_IN_ACCOUNT)" = 0 ] \
  && ok "shotgun forces SELFDEV_IN_ACCOUNT=0 even over an inherited 1" \
  || bad "SELFDEV_IN_ACCOUNT=$(field "$out" SELFDEV_IN_ACCOUNT) -- subagents would share the account checkout"
out="$(SELFDEV_IN_ACCOUNT=1 run both batch)"
[ "$(field "$out" SELFDEV_IN_ACCOUNT)" = 1 ] \
  && ok "batch is unaffected: SELFDEV_IN_ACCOUNT stays 1" \
  || bad "batch's SELFDEV_IN_ACCOUNT became $(field "$out" SELFDEV_IN_ACCOUNT) -- the shotgun change leaked"

echo "== case 3: an unknown tier is still refused, and names all three"
out="$(run both gatling)"; rc=$?
err="$(cat "$TMP/err")"
[ "$rc" -eq 2 ] && [ -z "$out" ] \
  && ok "unknown tier exits 2 with nothing dispatched" \
  || bad "unknown tier did not fail loud: rc=$rc out=[$out]"
case "$err" in
  *sweep*batch*shotgun*) ok "the refusal names all three tiers" ;;
  *) bad "refusal does not name the tiers: [$err]" ;;
esac

echo "== case 4: the fan-out fragment exists and resolves"
FRAG="$ROOT/schedule/_shotgun.md"
if [ -s "$FRAG" ]; then
  ok "schedule/_shotgun.md exists and is non-empty"
  cp "$FRAG" "$FX/schedule/_shotgun.md"
  mkconf fragged 'SHOTGUN_JOB_NAME="fragged-shotgun"' \
                 'SHOTGUN_ALLOWED_TOOLS="Bash,Agent"' \
                 'SHOTGUN_PROMPT="HEAD.
@@FRAGMENT:shotgun@@
TAIL."'
  out="$(run fragged shotgun)"
  case "$out" in
    *'@@FRAGMENT:'*) bad "the shotgun fragment marker did not resolve" ;;
    *'NO SUBAGENT TOUCHES THE WORKING TREE'*) ok "@@FRAGMENT:shotgun@@ resolves into the prompt" ;;
    *) bad "fragment resolved to something unexpected: [$out]" ;;
  esac
else
  bad "schedule/_shotgun.md is missing -- a shotgun with no sharding rules races itself"
fi

echo "== case 5: every armed shotgun conf carries Agent and the fragment"
found=0
for c in "$ROOT"/schedule/*.conf; do
  grep -q '^SHOTGUN_JOB_NAME=' "$c" || continue
  found=$((found + 1))
  n="$(basename "$c")"
  tools="$(sed -n 's/^SHOTGUN_ALLOWED_TOOLS="\(.*\)"$/\1/p' "$c" | head -1)"
  case "$tools" in
    *Agent*) ok "$n: SHOTGUN_ALLOWED_TOOLS carries Agent" ;;
    *) bad "$n: SHOTGUN_ALLOWED_TOOLS=[$tools] has no Agent -- this is a batch wearing a shotgun's name" ;;
  esac
  grep -qF '@@FRAGMENT:shotgun@@' "$c" \
    && ok "$n: references the sharding fragment" \
    || bad "$n: no @@FRAGMENT:shotgun@@ -- its subagents have no rule against working the same issue"
done
[ "$found" -gt 0 ] \
  && ok "checked $found conf(s) declaring a shotgun tier" \
  || bad "no conf declares SHOTGUN_JOB_NAME -- nothing is wired, so cases 1-4 prove only the plumbing"

# --- case 6: SHOTGUN_SLACK, the tier's automatic trigger (hf7y/scheduler#625) -
# Cases 1-5 are the HAND door: `dose <p> --shotgun`. This is the other half
# Zach ruled on 2026-09-06 -- auto-fire, and it REPLACES that tick's batch --
# implemented as one `if` in bin/usage-paced-runner.sh's dispatch loop. Lifts
# the real functions and the real substitution block by their markers, the
# same technique tests/derive-verdict-witness.sh uses for that file's
# repo_slug_of: a reimplementation here would only prove the reimplementation
# is right, not the shipped code.
echo "== case 6: SHOTGUN_SLACK auto-fire substitution in usage-paced-runner.sh"
FUNCS="$TMP/shotgun-slack-funcs.sh"
awk '/^shotgun_slack_for\(\) \{/,/^\}/' "$RUNNER"      > "$FUNCS"
awk '/^gate_slack_for_binding\(\) \{/,/^\}/' "$RUNNER" >> "$FUNCS"
grep -q 'shotgun_slack_for()' "$FUNCS" \
  && grep -q 'gate_slack_for_binding()' "$FUNCS" \
  || bad "shotgun_slack_for() / gate_slack_for_binding() not found in $RUNNER"

SWAP="$TMP/shotgun-slack-swap.sh"
awk '/^[[:space:]]*# >>> shotgun slack substitution/,/^[[:space:]]*# <<< shotgun slack substitution/' "$RUNNER" > "$SWAP"
grep -q 'shotgun_slack_for "\$name"' "$SWAP" \
  || bad "could not extract the substitution block from $RUNNER (markers moved or renamed)"

RUN_28PT='verdict=RUN binding=5h ceiling=0.85 min_slack=0.02 http_code=200 rush=False knobs=x
window=5h util=0.300 burnline=0.578 slack=+0.278 status= resets_in_min=120 rate=n/a
window=7d util=0.400 burnline=0.450 slack=+0.050 status= resets_in_min=5000 rate=n/a
# RUN -- slack available'

out="$(bash -c "$(cat "$FUNCS")"'
gate_slack_for_binding "$1"' -- "$RUN_28PT")"
[ "$out" = "+0.278" ] && ok "gate_slack_for_binding reads the BINDING window's own slack (+0.278)" \
  || bad "expected +0.278, got: $out"
out="$(bash -c "$(cat "$FUNCS")"'
gate_slack_for_binding "$1"' -- 'verdict=ERROR reason=no_headers http_code=? knobs=x')"
[ -z "$out" ] && ok "gate_slack_for_binding is empty for an ERROR reading" || bad "expected empty, got: $out"

mkconf slacker 'SHOTGUN_SLACK=0.25'
mkconf toopicky 'SHOTGUN_SLACK=0.90'
out="$(REPO_ROOT="$FX" bash -c "$(cat "$FUNCS")"'
shotgun_slack_for slacker')"
[ "$out" = "0.25" ] && ok "shotgun_slack_for reads SHOTGUN_SLACK from the project's own conf" \
  || bad "expected 0.25, got: $out"
out="$(REPO_ROOT="$FX" bash -c "$(cat "$FUNCS")"'
shotgun_slack_for both')"
[ -z "$out" ] && ok "a conf with no SHOTGUN_SLACK reads as empty -- unset is the safe default" \
  || bad "expected empty, got: $out"

swap_case() {  # $1=project $2=cmd -> "cmd=[...] tier=[...]" after the real block runs
  REPO_ROOT="$FX" name="$1" cmd="$2" verdict="$RUN_28PT" dispatch_tier="batch" bash -c '
log() { :; }
'"$(cat "$FUNCS")"'
'"$(cat "$SWAP")"'
echo "cmd=[$cmd] tier=[$dispatch_tier]"
'
}

out="$(swap_case slacker "$ROOT/bin/scheduler-run slacker batch")"
[[ "$out" == *"cmd=[$ROOT/bin/scheduler-run slacker shotgun]"* && "$out" == *"tier=[shotgun]"* ]] \
  && ok "slack clearing SHOTGUN_SLACK swaps that tick's batch for shotgun" \
  || bad "expected batch swapped to shotgun: $out"

out="$(swap_case toopicky "$ROOT/bin/scheduler-run toopicky batch")"
[[ "$out" == *"cmd=[$ROOT/bin/scheduler-run toopicky batch]"* && "$out" == *"tier=[batch]"* ]] \
  && ok "slack short of a stricter SHOTGUN_SLACK leaves batch untouched" \
  || bad "expected no substitution: $out"

out="$(swap_case both "$ROOT/bin/scheduler-run both batch")"
[[ "$out" == *"cmd=[$ROOT/bin/scheduler-run both batch]"* ]] \
  && ok "SHOTGUN_SLACK unset (every real project today) -- dormant, matches the issue's own default-after" \
  || bad "expected no substitution with SHOTGUN_SLACK unset: $out"

echo
echo "shotgun-tier-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
