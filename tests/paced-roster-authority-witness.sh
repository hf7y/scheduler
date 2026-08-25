#!/usr/bin/env bash
# paced-roster-authority-witness.sh -- ACCOUNT MODE takes liveness from
# schedule/ROSTER when it has a row, not from _paced.<host>.conf's `enabled`
# column alone (hf7y/scheduler#282, the onekey gap).
#
# THE BUG THIS CATCHES: schedule/_paced.monkey.conf carried `crt|1|...` and
# `secretaire|1|...` (armed) on 2026-08-25 while schedule/ROSTER recorded
# both `parked`, on Zach's own quoted pause/de-animation directives. Nothing
# before this read the second file for the enabled decision, so a paused
# project kept being dispatched every tick. Fixtures below reproduce exactly
# that shape: a conf enabling a row ROSTER says is parked.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "paced-roster-authority-witness"

# Extract both functions so they're testable in isolation, same convention
# as roster_rows in roster-participants-witness.sh.
eval "$(sed -n '/^roster_state_for() {/,/^}/p' "$R")"
eval "$(sed -n '/^participant_enabled() {/,/^}/p' "$R")"
declare -F roster_state_for  >/dev/null && ok "roster_state_for extracted"  \
  || { bad "could not extract roster_state_for -- nothing below tested anything"; echo; exit 1; }
declare -F participant_enabled >/dev/null && ok "participant_enabled extracted" \
  || { bad "could not extract participant_enabled -- nothing below tested anything"; echo; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/schedule"
cat > "$TMP/schedule/ROSTER" <<'EOF'
# comment
alpha   | alpha@testhost   | 20m | live
crt     | crt@testhost     | 6h  | parked
gamma   | gamma@otherhost  | 6h  | live
EOF
REPO_ROOT="$TMP"

# --- roster_state_for --------------------------------------------------------
out="$(roster_state_for alpha testhost)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "live" ] && ok "roster_state_for reports live for a live row" \
  || bad "expected live/rc0, got rc=$rc out=$out"

out="$(roster_state_for crt testhost)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "parked" ] && ok "roster_state_for reports parked for a parked row" \
  || bad "expected parked/rc0, got rc=$rc out=$out"

roster_state_for gamma testhost >/dev/null 2>&1 \
  && bad "a row for another host must not match" \
  || ok "a row naming another host does not match"

roster_state_for nosuchproject testhost >/dev/null 2>&1 \
  && bad "an unknown project must return 1, not a guess" \
  || ok "an unknown project@host returns 1 (no row)"

REPO_ROOT="$TMP/does-not-exist"
roster_state_for alpha testhost >/dev/null 2>&1 \
  && bad "a missing ROSTER file must return 1, not fabricate a state" \
  || ok "a missing ROSTER file returns 1"
REPO_ROOT="$TMP"

# --- participant_enabled: the actual dispatch decision ----------------------
# THE REGRESSION CASE: conf says enabled=1, ROSTER says parked -- ROSTER wins.
participant_enabled crt 1 testhost \
  && bad "crt is parked in ROSTER -- conf's enabled=1 must NOT win" \
  || ok "ROSTER parked overrides a conf enabled=1 (the crt/secretaire bug)"

# The mirror: conf says enabled=0, ROSTER says live -- ROSTER still wins.
cat >> "$TMP/schedule/ROSTER" <<'EOF'
delta   | delta@testhost   | 20m | live
EOF
participant_enabled delta 0 testhost \
  && ok "ROSTER live overrides a conf enabled=0" \
  || bad "delta is live in ROSTER -- conf's enabled=0 must not win"

# No row for this project@host at all -- falls back to the conf column,
# so an un-onboarded project keeps its pre-#282 behaviour instead of going
# dark silently.
participant_enabled epsilon 1 testhost \
  && ok "no ROSTER row -> falls back to the conf's enabled=1" \
  || bad "epsilon has no ROSTER row -- should have fallen back to conf enabled=1"
participant_enabled epsilon 0 testhost \
  && bad "epsilon has no ROSTER row -- should have fallen back to conf enabled=0" \
  || ok "no ROSTER row -> falls back to the conf's enabled=0"

# --- the runner's own loop calls participant_enabled, not the bare column ---
grep -q 'participant_enabled "\$name" "\$enabled" "\$PACED_HOST" || continue' "$R" \
  && ok "the participant-loading loop consults participant_enabled, not a bare enabled check" \
  || bad "the loop no longer calls participant_enabled -- this witness is testing dead code"
grep -qE '^\s*\[ "\$\{enabled// /\}" = "1" \] \|\| continue' "$R" \
  && bad "the loop still has a bare enabled==1 check ahead of the ROSTER lookup" \
  || ok "no bare enabled==1 gate left ahead of the ROSTER lookup"

printf '\npaced-roster-authority-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
