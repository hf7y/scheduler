#!/usr/bin/env bash
# Witness for bin/roster-diff.sh -- hermetic: builds fixture files in a temp
# dir, never touches the live schedule/. Proves the differ can actually
# reject (not just accept), in both directions, and that BLIND is distinct
# from a clean disagreement.
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

echo
echo "roster-diff-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
