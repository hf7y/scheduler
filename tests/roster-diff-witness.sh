#!/usr/bin/env bash
# Witness for bin/roster-diff.sh -- cases 1-4 are hermetic: they build fixture
# files in a temp dir and never touch the live schedule/. They prove the differ
# can actually reject (not just accept), in both directions, and that BLIND is
# distinct from a clean disagreement.
#
# Case 5 deliberately reads the SHIPPED tree, same shape and same reason as
# tests/conf-field-witness.sh's last section: the fixtures above all passed
# while bin/roster-diff.sh reported DISAGREE on main for days, because the
# defect was three real confs missing CRON_HOST/CRON_ACCOUNT and no fixture
# can notice that (hf7y/scheduler#328).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
DIFF=bin/roster-diff.sh

TMP="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# fixture <case-name> writes schedule/ under $TMP/<case-name> and echoes the path
fixture() {
  local d="$TMP/$1"
  mkdir -p "$d/schedule"
  printf '%s\n' "$d"
}

echo "roster-diff-witness"

# --- 1. agree: one live project, old and new say the same thing -----------
d="$(fixture agree)"
printf 'alpha|1|1|/home/alpha/bin/scheduler-run alpha batch\n' > "$d/schedule/_paced.testhost.conf"
printf 'CRON_HOST="testhost"\nCRON_ACCOUNT="alpha"\n' > "$d/schedule/alpha.conf"
printf 'alpha | alpha@testhost | 6h | live\n' > "$d/schedule/ROSTER"
out="$(SCHED_ROOT="$d" ROSTER_DIFF_HOST=testhost bash "$DIFF" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "agreeing old/new exits 0" || bad "agreeing old/new exited $rc (want 0): $out"

# --- 2. ROSTER marks live what the old files park -------------------------
d="$(fixture roster-over-claims)"
printf 'beta|0|1|/home/beta/bin/scheduler-run beta batch\n' > "$d/schedule/_paced.testhost.conf"
printf 'CRON_HOST="testhost"\nCRON_ACCOUNT="beta"\n' > "$d/schedule/beta.conf"
printf 'beta | beta@testhost | 6h | live\n' > "$d/schedule/ROSTER"
out="$(SCHED_ROOT="$d" ROSTER_DIFF_HOST=testhost bash "$DIFF" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ "$rc" -ne 2 ] && ok "roster-claims-live-but-old-parks exits non-zero, non-BLIND ($rc)" \
  || bad "roster-claims-live-but-old-parks exited $rc (want non-zero, non-2): $out"
case "$out" in *beta*) ok "beta is named in the mismatch" ;; *) bad "beta not named: $out" ;; esac

# --- 3. the other direction: old files say live, ROSTER parks it ----------
d="$(fixture old-over-claims)"
printf 'gamma|1|1|/home/gamma/bin/scheduler-run gamma batch\n' > "$d/schedule/_paced.testhost.conf"
printf 'CRON_HOST="testhost"\nCRON_ACCOUNT="gamma"\n' > "$d/schedule/gamma.conf"
printf 'gamma | gamma@testhost | 6h | parked\n' > "$d/schedule/ROSTER"
out="$(SCHED_ROOT="$d" ROSTER_DIFF_HOST=testhost bash "$DIFF" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ "$rc" -ne 2 ] && ok "old-says-live-roster-parks exits non-zero, non-BLIND ($rc)" \
  || bad "old-says-live-roster-parks exited $rc (want non-zero, non-2): $out"
case "$out" in *gamma*) ok "gamma is named in the mismatch" ;; *) bad "gamma not named: $out" ;; esac

# --- 4. BLIND is distinct from disagreement --------------------------------
d="$TMP/blind"; mkdir -p "$d"   # deliberately no schedule/ dir at all
out="$(SCHED_ROOT="$d" ROSTER_DIFF_HOST=testhost bash "$DIFF" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "missing schedule/ exits 2 (BLIND), not 0 or 1" \
  || bad "missing schedule/ exited $rc (want 2): $out"
case "$out" in *BLIND*) ok "BLIND is stated, not just a bare exit code" ;; *) bad "no BLIND wording: $out" ;; esac

# --- 5. the shipped tree: every live ROSTER row's conf sets both fields ----
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while IFS='|' read -r name _acct _rate state; do
  name="${name//[[:space:]]/}"; state="${state//[[:space:]]/}"
  [ -n "$name" ] && [ "$state" = "live" ] || continue
  conf="$ROOT/schedule/$name.conf"
  if grep -qE '^CRON_HOST=' "$conf" && grep -qE '^CRON_ACCOUNT=' "$conf"; then
    ok "$name.conf sets CRON_HOST and CRON_ACCOUNT"
  else
    bad "$name is live in ROSTER but $name.conf leaves CRON_HOST/CRON_ACCOUNT unset -- roster-diff derives parked for it and can never exit 0"
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT/schedule/ROSTER")

out="$(bash "$DIFF" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "roster-diff exits 0 against the shipped schedule/" \
  || bad "roster-diff exited $rc against the shipped schedule/: $out"

echo
echo "roster-diff-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
