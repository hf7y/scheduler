#!/usr/bin/env bash
# Witness for bin/scheduler-run's fetch fallback (hf7y/scheduler#350).
#
# THE GAP THIS CLOSES. CONF, RULES_FILE, FRAG_FILE and the _contain*.conf loop
# all read "$SCHED_ROOT/schedule/..." off disk. That is fine in a dev checkout
# or a v1 per-account clone (schedule/ is fast-forwarded before every
# dispatch), but the served build #350 exists to retire clones onto ships
# bin/ and lib/, not schedule/ (confirmed: `.../scheduler/schedule` 404s
# against hf7y/verbs) -- so a scheduler-run running from that build had no
# local schedule/ at all and would fail every one of these reads outright.
#
# read_schedule_rel in bin/scheduler-run now reads LOCAL when
# $SCHED_ROOT/schedule exists (unchanged from before -- every other fixture in
# this suite creates that directory, so they never touch the branch below),
# and fetches live over `gh` -- the same no-checkout mechanism fetch_roster
# already uses for schedule/ROSTER -- only when the directory itself is
# absent. This witness is the ONLY fixture in the suite with no schedule/ dir
# at all, so it is the only one that can exercise that branch.
#
# Asserts:
#   1. CONF, USES_STANDING_RULES and a @@FRAGMENT:@@ marker all resolve by
#      live fetch when schedule/ does not exist locally, and the assembled
#      PROMPT is identical in shape to the local-read witnesses.
#   2. _contain.conf (optional) is fetched too, when present.
#   3. a GAP (repo reachable, file absent on that ref) is loud and exits
#      nonzero -- nothing dispatched -- distinguishable in the message from
#   4. a BLIND (gh itself failing) on the same call site.
#   5. a fixture WITH a local schedule/ dir never calls gh at all, even when
#      gh would fail -- the regression this whole conversion must not cause.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- fixture repo: bin/ and lib/ only, deliberately NO schedule/ dir --------
FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib"
cp "$RUN" "$FX/bin/scheduler-run"
cp "$ROOT/lib/dose-common.sh" "$FX/lib/dose-common.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"

# --- the "remote" -- what a fake hf7y/scheduler@main is holding ------------
REMOTE="$TMP/remote-schedule"
mkdir -p "$REMOTE"
printf 'REPO_URL="https://example.invalid/fixture.git"\nBATCH_JOB_NAME="fetched-batch"\nUSES_STANDING_RULES=1\nBATCH_PROMPT="OWN PROMPT LINE. @@FRAGMENT:frag-a@@"\n' > "$REMOTE/fetched.conf"
cat > "$REMOTE/_standing-rules.md" <<'EOF'
STANDING RULES (fixture, fetched). These override everything below.
EOF
printf 'FRAGMENT BODY, FETCHED.\n' > "$REMOTE/_frag-a.md"

FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
mode="${FAKE_GH_MODE:-ok}"
[ "$1" = "api" ] || { echo "fake gh: unsupported invocation: $*" >&2; exit 2; }
shift
path="$1"; shift
echo "$path" >> "$FAKE_GH_LOG"
case "$path" in
  repos/hf7y/scheduler/contents/schedule/*)
    rel="${path#repos/hf7y/scheduler/contents/schedule/}"
    rel="${rel%%\?*}"
    if [ "$mode" = "blind" ]; then
      echo "gh: authentication failed" >&2
      exit 1
    fi
    file="$FAKE_REMOTE/$rel"
    if [ ! -f "$file" ]; then
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    base64 -w0 < "$file"
    ;;
  repos/hf7y/scheduler)
    if [ "$mode" = "blind" ]; then
      echo "gh: authentication failed" >&2
      exit 1
    fi
    echo "scheduler"
    ;;
  *)
    echo "fake gh: unexpected path $path" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$FAKEBIN/gh"

run() {  # $1=project $2=tier [$3=gh mode, default ok] -- echoes the assembled
         # prompt, returns its rc
  ( cd "$FX" && PATH="$FAKEBIN:$PATH" FAKE_REMOTE="$REMOTE" FAKE_GH_LOG="$TMP/gh.log" \
      FAKE_GH_MODE="${3:-ok}" bash bin/scheduler-run "$1" "$2" 2>"$TMP/err" )
}

echo "== case 1: CONF, standing rules and a fragment all resolve by live fetch"
: > "$TMP/gh.log"
out="$(run fetched batch)"; rc=$?
first="$(printf '%s' "$out" | head -1)"
if [ "$rc" -eq 0 ] && [ "$first" = "STANDING RULES (fixture, fetched). These override everything below." ]; then
  ok "standing rules fetched and prepended (rc=$rc)"
else
  bad "expected fetched rules at the head, got rc=$rc first=[$first] err=[$(cat "$TMP/err")]"
fi
case "$out" in
  *"OWN PROMPT LINE."*"FRAGMENT BODY, FETCHED."*) ok "conf and fragment both fetched into the prompt" ;;
  *) bad "conf/fragment fetch did not resolve: [$out]" ;;
esac
if grep -q '^repos/hf7y/scheduler/contents/schedule/fetched\.conf' "$TMP/gh.log" \
   && grep -q '^repos/hf7y/scheduler/contents/schedule/_standing-rules\.md' "$TMP/gh.log" \
   && grep -q '^repos/hf7y/scheduler/contents/schedule/_frag-a\.md' "$TMP/gh.log"; then
  ok "all three fetches actually went out over gh, no checkout"
else
  bad "expected fetches missing from the gh log: $(cat "$TMP/gh.log")"
fi

echo "== case 2: optional _contain.conf is fetched too, when the remote has it"
printf 'CONTAIN_CPU_QUOTA="42%%"\n' > "$REMOTE/_contain.conf"
cat > "$FX/lib/sweep-loop-common.sh" <<'STUB'
printf "%s" "${CONTAIN_CPU_QUOTA:-<unset>}"
exit 0
STUB
: > "$TMP/gh.log"
out="$(run fetched batch)"
if [ "$out" = "42%" ]; then
  ok "_contain.conf fetched and its setting reached the run"
else
  bad "expected CONTAIN_CPU_QUOTA=42%% from a fetched _contain.conf, got: [$out]"
fi
rm -f "$REMOTE/_contain.conf"
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"

echo "== case 3: GAP -- conf absent on the remote, loud, nothing dispatched"
out="$(run does-not-exist-remotely batch)"; rc=$?
err="$(cat "$TMP/err")"
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "missing remote conf refuses (rc=$rc), nothing dispatched"
else
  bad "should have refused: rc=$rc out=[$out]"
fi
case "$err" in
  *"GAP:"*"schedule/does-not-exist-remotely.conf"*) ok "and names it a GAP, not a BLIND, by path" ;;
  *) bad "no GAP diagnostic naming the conf: [$err]" ;;
esac

echo "== case 4: BLIND -- gh itself fails, distinguishable from GAP"
out="$(run fetched batch blind)"; rc=$?
err="$(cat "$TMP/err")"
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "gh failure refuses (rc=$rc), nothing dispatched"
else
  bad "should have refused on a gh failure: rc=$rc out=[$out]"
fi
case "$err" in
  *"BLIND:"*) ok "and names it BLIND, not GAP" ;;
  *) bad "no BLIND diagnostic: [$err]" ;;
esac

echo "== case 5: a fixture WITH local schedule/ never calls gh, even if gh would fail"
LOCALFX="$TMP/local-repo"
mkdir -p "$LOCALFX/bin" "$LOCALFX/lib" "$LOCALFX/schedule"
cp "$RUN" "$LOCALFX/bin/scheduler-run"
cp "$ROOT/lib/dose-common.sh" "$LOCALFX/lib/dose-common.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$LOCALFX/bin/freeze-check.sh"
chmod +x "$LOCALFX/bin/freeze-check.sh" "$LOCALFX/bin/scheduler-run"
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$LOCALFX/lib/sweep-loop-common.sh"
printf 'REPO_URL="https://example.invalid/fixture.git"\nBATCH_JOB_NAME="local-batch"\nBATCH_PROMPT="LOCAL OWN LINE."\n' > "$LOCALFX/schedule/local.conf"
: > "$TMP/gh.log"
out="$(cd "$LOCALFX" && PATH="$FAKEBIN:$PATH" FAKE_GH_MODE=blind FAKE_REMOTE="$REMOTE" FAKE_GH_LOG="$TMP/gh.log" bash bin/scheduler-run local batch 2>"$TMP/err")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "LOCAL OWN LINE." ]; then
  ok "local schedule/ dispatches normally even though gh is set to fail"
else
  bad "local dispatch broke: rc=$rc out=[$out] err=[$(cat "$TMP/err")]"
fi
if [ ! -s "$TMP/gh.log" ]; then
  ok "gh was never invoked -- local schedule/ took none of the fetch branch"
else
  bad "gh was invoked from a fixture with a local schedule/ dir: $(cat "$TMP/gh.log")"
fi

echo
echo "schedule-fetch-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
