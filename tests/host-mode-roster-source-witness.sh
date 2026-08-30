#!/usr/bin/env bash
# host-mode-roster-source-witness.sh -- in HOST MODE, the live/parked question
# is answered by the roster that was FETCHED, not by the checkout's copy
# (hf7y/scheduler#412).
#
# THE BUG THIS CATCHES. Host mode materialises schedule/ROSTER over gh and
# refuses to fall back to a checkout -- its own comment calls falling back
# "the exact clone dependency this branch exists to remove". But the rotation
# was the only thing that came from the fetch. participant_enabled (:318) then
# calls roster_state_for, which reads ${SCHEDULER_ROSTER_FILE:-$REPO_ROOT/
# schedule/ROSTER} (:280), and REPO_ROOT is the script's own tree (:55). So a
# STALE LOCAL `live` beat a FETCHED `parked`: parking a project with
# `dose --park`, which writes ROSTER and pushes, would not stop a host-mode
# dispatcher whose checkout had not pulled.
#
# WHY IT IS WITNESSED AT THIS SEAM. A full host-mode dispatch needs root and
# 0700 homes (see tests/paced-host-mode-witness.sh, which says the same and
# says why). So the conf-resolution block is evaluated on its own, with
# fetch_roster stubbed, and the question is put to the real participant_enabled
# afterwards -- the same extract-and-call convention as
# tests/paced-roster-authority-witness.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "host-mode-roster-source-witness"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The two copies DISAGREE, which is the whole fixture: the checkout says alpha
# is live, the roster that would come back over gh says it is parked.
mkdir -p "$TMP/repo/schedule" "$TMP/bin" "$TMP/lib"
cat > "$TMP/repo/schedule/ROSTER" <<'EOF'
# the checkout, not pulled since alpha was parked
alpha | alpha@testhost | 2h | live
beta  | beta@testhost  | 2h | live
EOF
FETCHED='# what gh returns: alpha has been parked and pushed
alpha | alpha@testhost | 2h | parked
beta  | beta@testhost  | 2h | live'

# Stub the library the block sources by name, so the fetch is controlled and
# no network or gh is involved.
cat > "$TMP/lib/dose-common.sh" <<EOF
fetch_roster() { printf '%s\n' '$FETCHED'; }
EOF

# --- extract the three pieces under test -------------------------------------
eval "$(sed -n '/^roster_rows() {/,/^}/p' "$R")"
eval "$(sed -n '/^roster_state_for() {/,/^}/p' "$R")"
eval "$(sed -n '/^participant_enabled() {/,/^}/p' "$R")"
for f in roster_rows roster_state_for participant_enabled; do
  declare -F "$f" >/dev/null \
    || { bad "could not extract $f -- nothing below tested anything"; echo; exit 1; }
done
ok "roster_rows, roster_state_for and participant_enabled extracted"

# The host-mode branch of the conf ladder, lifted out of the elif chain. Taken
# by its anchors rather than by line number so it cannot silently test a
# different block after an edit above it.
BLOCK="$(sed -n '/^elif \[ "\$PACED_HOST_MODE" = 1 \]; then$/,/^elif \[ -f "\$REPO_ROOT\/schedule\/_paced\.\$PACED_HOST\.conf" \]; then$/p' "$R" | sed '1d;$d')"
[ -n "$BLOCK" ] || { bad "the host-mode conf block could not be located in $R"; echo; exit 1; }
grep -q 'fetch_roster' <<<"$BLOCK" || { bad "the block found is not the host-mode block"; echo; exit 1; }
ok "the host-mode conf-resolution block was located by its anchors"
eval "host_mode_block() { $BLOCK
}"

# --- run it ------------------------------------------------------------------
# TMPDIR so the block's own mktemp files land inside $TMP and the trap above
# still owns every temp this witness creates.
REPO_ROOT="$TMP/repo"
SELF_DIR="$TMP/bin"
PACED_HOST=testhost
TMPDIR="$TMP"
unset SCHEDULER_ROSTER_FILE

# NOT VACUOUS: with nothing set, the checkout is what answers, and it says
# live. If this line ever reports parked the fixture has stopped disagreeing
# and every assertion below would pass for the wrong reason.
pre="$(roster_state_for alpha testhost || true)"
[ "$pre" = live ] && ok "before host mode runs, the CHECKOUT answers 'live' (fixture disagrees as intended)" \
  || bad "fixture is not set up: checkout reported '$pre', want live"

host_mode_block
trap 'rm -rf "$TMP"' EXIT   # the block installs its own; take cleanup back

# --- 1. the fetched roster is what roster_state_for now reads ----------------
[ -n "${SCHEDULER_ROSTER_FILE:-}" ] \
  && ok "host mode set SCHEDULER_ROSTER_FILE" \
  || bad "SCHEDULER_ROSTER_FILE is unset after host mode -- roster_state_for still reads the checkout"

# Non-empty is part of the test: an unset variable is "not the checkout path"
# too, and would pass this vacuously on exactly the code the witness exists
# to fail.
[ -n "${SCHEDULER_ROSTER_FILE:-}" ] && [ "$SCHEDULER_ROSTER_FILE" != "$REPO_ROOT/schedule/ROSTER" ] \
  && ok "it points somewhere other than the checkout's ROSTER" \
  || bad "it does not name a path away from the checkout: '${SCHEDULER_ROSTER_FILE:-<unset>}'"

if [ -r "${SCHEDULER_ROSTER_FILE:-/nonexistent}" ]; then
  diff -q <(printf '%s\n' "$FETCHED") "$SCHEDULER_ROSTER_FILE" >/dev/null \
    && ok "and it holds the FETCHED bytes verbatim" \
    || bad "the file it points at is not what fetch_roster returned"
else
  bad "SCHEDULER_ROSTER_FILE names an unreadable path"
fi

# --- 2. THE POINT: a fetched park beats a stale local live -------------------
got="$(roster_state_for alpha testhost || true)"
[ "$got" = parked ] && ok "roster_state_for reports the fetched 'parked', not the checkout's 'live'" \
  || bad "roster_state_for still answers from the checkout: got '$got', want parked"

LOG="$TMP/run.log"; log() { echo "$*" >> "$LOG"; }
if participant_enabled alpha testhost; then
  bad "alpha would still be DISPATCHED -- a pushed park does not stop host mode"
else
  ok "participant_enabled refuses alpha: the pushed park stops the dispatch"
fi

# The mirror, so the fix is not a blanket refusal: a row the fetch calls live
# still dispatches. The fetched bytes are all participant_enabled reads (#364).
if participant_enabled beta testhost; then
  ok "beta, live in both copies, still dispatches (the fix is not a blanket refusal)"
else
  bad "beta stopped dispatching -- host mode now refuses rows that ARE live"
fi

# --- 3. the rotation still came from the fetch ------------------------------
grep -q '^alpha|0|' "$PACED_CONF" \
  && ok "PACED_CONF still carries roster_rows' translation (alpha parked -> enabled 0)" \
  || bad "PACED_CONF is not the roster_rows translation any more: $(cat "$PACED_CONF")"

# --- 4. ACCOUNT MODE IS UNCHANGED -------------------------------------------
# 18 accounts run that path. Host mode is the only writer of
# SCHEDULER_ROSTER_FILE; with the mode off the variable must stay unset so
# roster_state_for keeps reading REPO_ROOT.
sed -n '/^if \[ -n "${PACED_CONF:-}" \]; then$/,/^fi$/p' "$R" \
  | grep -n 'SCHEDULER_ROSTER_FILE' > "$TMP/hits" || true
if [ -s "$TMP/hits" ]; then
  # every hit must be inside the host-mode branch, which is the block above
  while IFS= read -r h; do
    grep -qF "${h#*:}" <<<"$BLOCK" \
      || bad "SCHEDULER_ROSTER_FILE is touched outside the host-mode branch: ${h#*:}"
  done < "$TMP/hits"
  ok "every SCHEDULER_ROSTER_FILE assignment in the conf ladder is inside the host-mode branch"
else
  bad "no SCHEDULER_ROSTER_FILE assignment found in the conf ladder at all"
fi

printf '\nhost-mode-roster-source-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
