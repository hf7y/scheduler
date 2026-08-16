#!/usr/bin/env bash
# dose-common-purity-witness.sh -- sourcing the library does nothing.
#
# It shipped in hf7y/scheduler#120 ending with
#     ROSTER_CONTENT="$(fetch_roster)" || exit $?
# so `. lib/dose-common.sh` made a NETWORK FETCH and, on failure, `exit`ed the
# CALLING process with dose's exit code. Caught 2026-08-11 when freeze-check.sh
# sourced it for fetch_repo_file and died with 6 (dose's BLIND) instead of its
# own contract's 2 (FROZEN) -- a library reaching past its caller's handling.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib/dose-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "dose-common-purity-witness"

# --- 1. sourcing succeeds even with no usable gh --------------------------
out="$(DOSE_GH_BIN=/nonexistent bash -c ". '$LIB'; echo SOURCED-OK" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "sourcing exits 0 with an unusable gh" || bad "sourcing exited $rc: $out"
grep -q 'SOURCED-OK' <<<"$out" && ok "the caller keeps running after the source" \
  || bad "the library exited the caller -- it is not a library: $out"

# --- 2. sourcing makes no network call ------------------------------------
# A fake gh that records being run. If the library calls it at source time, the
# marker appears; a pure library leaves nothing behind.
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf '#!/usr/bin/env bash\ntouch "%s/CALLED"\n' "$W" > "$W/gh"; chmod +x "$W/gh"
DOSE_GH_BIN="$W/gh" bash -c ". '$LIB'" >/dev/null 2>&1
[ -e "$W/CALLED" ] && bad "sourcing invoked gh -- a source must not hit the network" \
  || ok "sourcing invoked gh zero times"

# --- 3. the functions it defines are actually there -----------------------
# Purity is worthless if it achieved it by defining nothing.
for fn in fetch_repo_file fetch_roster gh_as crontab_read crontab_write; do
  bash -c ". '$LIB'; declare -F $fn >/dev/null" 2>/dev/null \
    && ok "defines $fn" || bad "$fn is missing -- the library defines nothing useful"
done

# --- 4. no top-level statement may invoke anything ------------------------
# Structural, so a future edit that re-adds a side effect fails here rather
# than in whatever unlucky script sources it next.
if awk 'BEGIN{d=0} /^[a-z_]+\(\) *\{/{d=1} d&&/^}/{d=0;next} !d && /^[A-Za-z_]+=.*\$\(/ {print}' "$LIB" \
     | grep -vE '^(HOST|LOCAL_ACCOUNT)=' | grep -q .; then
  bad "a top-level assignment runs a command substitution -- side effect at source time"
else
  ok "no top-level statement runs anything but the two cheap local lookups"
fi

printf '\ndose-common-purity-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
