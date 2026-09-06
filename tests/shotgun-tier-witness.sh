#!/usr/bin/env bash
# Witness for the SHOTGUN tier in bin/scheduler-run (hf7y/scheduler#586).
#
# WHAT A SHOTGUN IS. One `claude -p` whose ALLOWED_TOOLS carry `Agent`, so it
# splits its own issue queue N ways and works every shard at once, each in its
# own clone. #586 frames the PROJECT_KEY lock in lib/sweep-loop-common.sh as
# the thing to break; measured 2026-09-06, six subagents in ONE process cost
# ~390 MB RSS against ~1680 MB for six processes, on a host capped at
# memory=8GB. So the fan-out goes INSIDE one lock hold and the lock is
# untouched.
#
# THE TWO THINGS THAT SILENTLY UNDO IT, which is why they are asserted and not
# merely written down:
#   * `Agent` missing from ALLOWED_TOOLS. The run still succeeds -- it is just
#     a nightly batch with a different name and a second STATE_DIR. Nothing
#     else in the estate would notice.
#   * SELFDEV_IN_ACCOUNT left at `auto`. For an account whose name equals its
#     project (realisateur@monkey is one), that resolves to the ONE account
#     checkout the nightly batch owns, and points every subagent at it.
#
# Asserts:
#   1. `scheduler-run <p> shotgun` selects PREFIX=SHOTGUN and TIER=shotgun,
#      and reads the conf's SHOTGUN_* fields.
#   2. the shotgun path forces SELFDEV_IN_ACCOUNT=0, overriding an inherited
#      value; and the batch path does NOT (it stays whatever it was).
#   3. an unknown tier still exits 2, and says all three names.
#   4. schedule/_shotgun.md exists and is reachable as @@FRAGMENT:shotgun@@.
#   5. EVERY conf declaring SHOTGUN_JOB_NAME carries `Agent` in its
#      SHOTGUN_ALLOWED_TOOLS and references the fragment -- generalised, so a
#      second project arming a shotgun cannot forget either.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- fixture repo, same shape as tests/fragment-marker-witness.sh ----------
FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
# The stub reports the engine inputs this witness is about, one per line, so a
# case can assert on any of them without a second fixture shape.
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
    *'ONE CLONE PER SUBAGENT'*) ok "@@FRAGMENT:shotgun@@ resolves into the prompt" ;;
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

echo
echo "shotgun-tier-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
