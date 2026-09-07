#!/usr/bin/env bash
# account-mode-roster-fetch-witness.sh -- account mode fetches schedule/ROSTER
# over gh when no local checkout has it (served build, #350; mirrors #412).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "account-mode-roster-fetch-witness"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/schedule" "$TMP/bin" "$TMP/lib" "$TMP/served"

cat > "$TMP/repo/schedule/ROSTER" <<'EOF'
alpha | alpha@testhost | 2h | live
EOF

FETCHED='beta | beta@testhost | 2h | live'
cat > "$TMP/lib/dose-common.sh" <<EOF
fetch_roster() { printf '%s\n' '$FETCHED'; }
EOF

eval "$(sed -n '/^roster_state_for() {/,/^}/p' "$R")"
eval "$(sed -n '/^participant_enabled() {/,/^}/p' "$R")"
declare -F roster_state_for >/dev/null && declare -F participant_enabled >/dev/null \
  && ok "roster_state_for and participant_enabled extracted" \
  || { bad "could not extract the functions under test -- nothing below tested anything"; echo; exit 1; }

BLOCK="$(sed -n '/^# >>> account-mode roster fetch/,/^# <<< account-mode roster fetch/p' "$R" | sed '1d;$d')"
[ -n "$BLOCK" ] || { bad "the account-mode roster-fetch block could not be located in $R by its markers"; echo; exit 1; }
grep -q 'fetch_roster' <<<"$BLOCK" || { bad "the block found does not mention fetch_roster"; echo; exit 1; }
ok "the account-mode roster-fetch block was located by its anchors"
eval "account_mode_block() { $BLOCK
}"

log() { :; }  # the block never calls log(); the runner's own log() needs LOG, unused here

REPO_ROOT="$TMP/repo"; SELF_DIR="$TMP/bin"; PACED_HOST=testhost   # 1: a clone still answers locally, unchanged
unset SCHEDULER_ROSTER_FILE
account_mode_block
[ -z "${SCHEDULER_ROSTER_FILE:-}" ] \
  && ok "with a local schedule/ROSTER present, the block does not fetch (SCHEDULER_ROSTER_FILE stays unset)" \
  || bad "SCHEDULER_ROSTER_FILE was set even though $REPO_ROOT/schedule/ROSTER exists: $SCHEDULER_ROSTER_FILE"
got="$(roster_state_for alpha testhost || true)"
[ "$got" = live ] && ok "roster_state_for still answers from the checkout (alpha live)" \
  || bad "expected the checkout's answer 'live', got '$got'"

REPO_ROOT="$TMP/served"; SELF_DIR="$TMP/bin"; PACED_HOST=testhost   # 2: no local ROSTER -> fetch over gh
unset SCHEDULER_ROSTER_FILE
account_mode_block
trap 'rm -rf "$TMP"' EXIT   # the block installs its own EXIT trap; take cleanup back

[ -n "${SCHEDULER_ROSTER_FILE:-}" ] \
  && ok "with no local schedule/ROSTER, the block fetched and set SCHEDULER_ROSTER_FILE" \
  || bad "SCHEDULER_ROSTER_FILE is unset -- account mode still reads a checkout that is not there"

if [ -r "${SCHEDULER_ROSTER_FILE:-/nonexistent}" ]; then
  diff -q <(printf '%s\n' "$FETCHED") "$SCHEDULER_ROSTER_FILE" >/dev/null \
    && ok "and it holds the FETCHED bytes verbatim" \
    || bad "the file it points at is not what fetch_roster returned"
else
  bad "SCHEDULER_ROSTER_FILE names an unreadable path"
fi

got="$(roster_state_for beta testhost || true)"
[ "$got" = live ] && ok "roster_state_for now answers from the fetch (beta live)" \
  || bad "expected the fetched answer 'live' for beta, got '$got'"

LOG="$TMP/run.log"; log() { echo "$*" >> "$LOG"; }
if participant_enabled beta testhost; then
  ok "participant_enabled dispatches beta -- no longer a blanket SKIP under the served build"
else
  bad "beta still refused to dispatch -- the fetch fallback did not reach participant_enabled"
fi

cat > "$TMP/lib/dose-common.sh" <<'EOF'   # 3: no local ROSTER and the fetch fails -> refuse, never fabricate
fetch_roster() { return 6; }
EOF
REPO_ROOT="$TMP/served"; SELF_DIR="$TMP/bin"; PACED_HOST=testhost
unset SCHEDULER_ROSTER_FILE
( account_mode_block ) 2>/dev/null
rc=$?
[ "$rc" -ne 0 ] && ok "an unreachable roster refuses (exit $rc), rather than dispatch as if none of it mattered" \
  || bad "the block exited 0 with an unreachable roster -- that is a silent-parked failure, not a refusal"

printf '\naccount-mode-roster-fetch-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
