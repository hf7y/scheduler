#!/usr/bin/env bash
# Witness for the GH_TOKEN mint in bin/scheduler-run.
#
# THE DEFECT THIS RETIRES, measured on monkey 2026-08-11. Three armed
# self-dev accounts, three different GitHub credentials, nothing comparing
# them:
#
#     vim-arcade      gho_...            pulls API works
#     bibliothecaire  gho_...            pulls API works
#     ecosim          github_pat_11A...  403 on the ENTIRE Pull-requests API
#
# ecosim's fine-grained PAT was missing the Pull requests permission, so it
# was refused on READ as well as write. It did correct work on 2026-08-09 and
# again on 08-11, pushed branch `port-self-dev-checks` with green tests, and
# could not open a pull request for any of it. That work is still stranded.
#
# THE PART WORTH TESTING IS THE SILENCE, not the permission. `gh issue list`
# kept working, so the brief's first step succeeded and every run looked
# healthy right up to the step that mattered. Nothing in the engine had an
# opinion about which credential an account carried, so an account whose token
# had rotted was the last to find out.
#
# The mint uses realisateur's bin/selfdev-gh-app.sh, whose installation tokens
# expire in an hour and are minted from a key on demand -- see its own "WHY A
# TOKEN AND NOT A PAT". One source, once per dispatch, same for every account.
#
# Asserts, and 2 and 4 are the ones that rot:
#   1. configured + helper works => GH_TOKEN is exported with EXACTLY what the
#      helper printed
#   2. NOT configured => no GH_TOKEN, and the run proceeds. Fail-open is
#      deliberate: this must never take a working credential away from an
#      account that already had one, which is every account but ecosim today
#   3. configured but the helper FAILS => a warning on stderr, and the run
#      still proceeds. Loud, not fatal -- a dead mint should not take dispatch
#      down, but it must not be indistinguishable from case 2 either
#   4. GH_TOKEN already in the environment => left alone. A caller that has
#      already decided (a hand-run, a test, a different App) outranks the file
#
# HERMETIC. Both paths are overridden -- SELFDEV_APP_CONF and
# SELFDEV_GH_APP_SH -- so this never reads the live estate, never touches a
# real key and never reaches GitHub. Without the overrides a green run here
# would be indistinguishable from the live fleet happening to be healthy,
# which is the trap bin/install-verbs.sh's INSTALLE_* knobs exist to avoid.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- fixture repo, same shape as tests/standing-rules-witness.sh ------------
# The REAL bin/scheduler-run (SCHED_ROOT derives from the script's own
# location, so a copy governs the tree it sits in), with the freeze gate and
# the engine stubbed. The stub engine prints GH_TOKEN and nothing else: this
# witness is about which credential reaches the run, and it must never
# dispatch.
FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
printf 'printf "%%s" "${GH_TOKEN:-<unset>}"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"

cat > "$FX/schedule/proj.conf" <<'EOF'
REPO_URL="https://example.invalid/fixture.git"
BATCH_JOB_NAME="proj-batch"
BATCH_PROMPT="OWN PROMPT."
EOF

# A stub helper standing in for realisateur's selfdev-gh-app.sh. It prints a
# recognisable token, or fails, depending on how it is written per case.
HELPER="$TMP/selfdev-gh-app.sh"
CONF="$TMP/gh-app.conf"
mkhelper() { printf '%s\n' '#!/usr/bin/env bash' "$@" > "$HELPER"; chmod +x "$HELPER"; }

run() {  # echoes what the engine saw in GH_TOKEN; stderr lands in $TMP/err
  # unset, not just left un-exported: this witness's OWN dispatcher (scheduler-run,
  # 9735193) mints and exports GH_TOKEN into its own process before invoking
  # anything else, so any real self-dev run of this suite -- including
  # scheduler's own, armed 2026-08-11 (5380468) -- inherits a live token here.
  # Cases 1-3 assert what happens when the account had NO prior token; an
  # inherited one would silently take that branch instead (case 4's own
  # behaviour), making the assertion pass or fail by environment accident
  # rather than by what scheduler-run actually does.
  ( cd "$FX" \
    && unset GH_TOKEN \
    && SELFDEV_APP_CONF="$CONF" SELFDEV_GH_APP_SH="$HELPER" \
       bash bin/scheduler-run proj batch 2>"$TMP/err" )
}

echo "== case 1: configured and the helper works -- the minted token reaches the run"
: > "$CONF"
mkhelper 'echo ghs_FIXTURE_TOKEN_1'
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "ghs_FIXTURE_TOKEN_1" ]; then
  ok "GH_TOKEN is exactly what the helper printed"
else
  bad "expected the minted token, got rc=$rc GH_TOKEN=[$out]"
fi
grep -q 'minted a GitHub App installation token' "$TMP/err" \
  && ok "the mint is announced on stderr" \
  || bad "a silent mint is not observable in a run log: [$(cat "$TMP/err")]"

echo "== case 2: NOT configured -- fail open, nothing is taken away"
rm -f "$CONF"
mkhelper 'echo ghs_SHOULD_NOT_BE_USED'
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "<unset>" ]; then
  ok "no conf => no mint, and the run proceeds on whatever gh auth exists"
else
  bad "an unconfigured account was changed: rc=$rc GH_TOKEN=[$out]"
fi

echo "== case 3: configured but the helper FAILS -- loud, and still not fatal"
: > "$CONF"
mkhelper 'exit 5'
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "<unset>" ]; then
  ok "a dead mint does not take dispatch down"
else
  bad "a failed mint changed the run's outcome: rc=$rc GH_TOKEN=[$out]"
fi
if grep -q 'WARNING' "$TMP/err"; then
  ok "a configured-but-broken mint is distinguishable from an unconfigured one"
else
  bad "silent fallback -- this is exactly ecosim's two lost days: [$(cat "$TMP/err")]"
fi

echo "== case 4: GH_TOKEN already set -- the caller outranks the file"
: > "$CONF"
mkhelper 'echo ghs_FIXTURE_TOKEN_2'
out="$( cd "$FX" \
        && GH_TOKEN=ghs_CALLER_SUPPLIED \
           SELFDEV_APP_CONF="$CONF" SELFDEV_GH_APP_SH="$HELPER" \
           bash bin/scheduler-run proj batch 2>/dev/null )"
if [ "$out" = "ghs_CALLER_SUPPLIED" ]; then
  ok "an inherited GH_TOKEN is not clobbered"
else
  bad "the mint overrode a caller's explicit credential: [$out]"
fi

echo
echo "gh-app-token-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
