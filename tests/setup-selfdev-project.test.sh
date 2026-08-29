#!/usr/bin/env bash
#
# TRAPS (the rest of this header is in the vault):
#   * a failing repo makes the run REFUSE, non-zero, naming that repo;
#   * it refuses BEFORE landing and before the release bootstrap -- proven by
#     the stubs' own markers, not by reading the log;
#   * EVERY failing repo is named, not the first. "senechal failed" and
#     "senechal and scheduler failed" are different amounts of re-work, and
#     stopping at the first hides the difference.

set -uo pipefail
# shellcheck source=bin/tests/lib/harness.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"

check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/../bin/setup-selfdev-project.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJECT=fixtureproj
BIN="$TMP/bin"                 # stands in for the script's own $HERE
HOMES="$TMP/homes"             # what the stub `getent passwd` reports
PHOME="$HOMES/$PROJECT"
mkdir -p "$BIN" "$TMP/stub" "$PHOME"

cp "$SETUP" "$BIN/setup-selfdev-project.sh"

# --- the four scripts it sequences, as stubs -----------------------------
# Each records that it ran, where the harness can see it. The wiring stub is
# the only one with an opinion: it fails for any repo named in wire-fail-list,
# in the same shape the real one does (a BAD WITNESS FAILED row, exit 5).
cat > "$BIN/provision-selfdev-user.sh" <<'STUB'
#!/usr/bin/env bash
echo "provision stub: $*"
STUB

cat > "$BIN/wire-selfdev-git.sh" <<'STUB'
#!/usr/bin/env bash
# Staged into $HOME_DIR/.selfdev-setup/ by the script under test, so its own
# directory is where the harness leaves its control files. It cannot read an
# env var: run_as invokes it through `env -i`.
repo="$1"; d="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$repo" >> "$d/wire-calls"
echo "== wire-selfdev-git stub $repo =="
if grep -qxF "$repo" "$d/wire-fail-list" 2>/dev/null; then
  echo "  BAD     WITNESS FAILED: git@github-$repo did not serve -- the wiring is not live"
  exit 5
fi
echo "  OK      WITNESS: GitHub served $repo"
STUB

cat > "$BIN/land-selfdev.sh" <<'STUB'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
: > "$d/LANDED"
echo "land stub: $*"
STUB

cat > "$BIN/wire-release-channel.sh" <<'STUB'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/.." && pwd)"
: > "$d/RELEASE-BOOTSTRAPPED"
echo "release-channel stub: $*"
STUB
chmod +x "$BIN"/*.sh

# --- the privileged surface, stubbed -------------------------------------
REAL_INSTALL="$(PATH=/usr/bin:/bin command -v install)"
[ -n "$REAL_INSTALL" ] || { echo "setup-selfdev-project.test: BLIND: no /usr/bin/install to delegate to" >&2; exit 2; }

cat > "$TMP/stub/id" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  -u)  echo 0 ;;      # the script's root check; nothing here needs real root
  -un) echo fixturehands ;;
  *)   echo fixturehands ;;
esac
STUB

cat > "$TMP/stub/getent" <<STUB
#!/usr/bin/env bash
[ "\${1:-}" = passwd ] || exit 2
printf '%s:x:4242:4242:fixture:%s/%s:/bin/bash\n' "\$2" "$HOMES" "\$2"
STUB

cat > "$TMP/stub/install" <<STUB
#!/usr/bin/env bash
# -o/-g need root and the ownership is not what this suite is about; every
# other flag (-d, -m, the paths) goes to the real install unchanged.
args=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o|-g) shift 2 ;;
    *)     args+=("\$1"); shift ;;
  esac
done
exec "$REAL_INSTALL" "\${args[@]}"
STUB

cat > "$TMP/stub/sudo" <<'STUB'
#!/usr/bin/env bash
# Drop sudo's own flags and run the command as whoever we already are.
while [ $# -gt 0 ]; do
  case "$1" in
    -u) shift 2 ;;
    -H|-E|-n) shift ;;
    *) break ;;
  esac
done
exec "$@"
STUB
chmod +x "$TMP/stub"/*

# setup <failing repo>... -- one run of the script under test.
setup() {
    rm -f "$PHOME/wire-calls" "$PHOME/LANDED" "$TMP/RELEASE-BOOTSTRAPPED"
    : > "$PHOME/wire-fail-list"
    for r in "$@"; do printf '%s\n' "$r" >> "$PHOME/wire-fail-list"; done
    PATH="$TMP/stub:$PATH" SUDO_USER=fixturehands \
      bash "$BIN/setup-selfdev-project.sh" "$PROJECT" --apply --no-key \
      > "$TMP/out" 2> "$TMP/err"
}

echo "setup-selfdev-project step-3 gate"

# --- 1. the clean run still runs ----------------------------------------
# A gate that fires on a healthy provisioning is worse than the silence it
# replaced, so this case is not a formality.
setup
check "every repo wiring cleanly exits 0" "$?" "0"
check "...all four repos were wired" "$(sort -u "$PHOME/wire-calls" | tr '\n' ' ')" \
      "fixtureproj realisateur scheduler senechal "
check "...landing ran" "$([ -f "$PHOME/LANDED" ] && echo ran || echo skipped)" "ran"
check "...and the release bootstrap ran" \
      "$([ -f "$TMP/RELEASE-BOOTSTRAPPED" ] && echo ran || echo skipped)" "ran"

# --- 2. ONE repo failing stops the run and names it ----------------------
# This is the account-#4 case exactly: the deploy key for one repo does not
# serve, wire-selfdev-git.sh says so and exits 5, and everything downstream
# used to proceed as if it had not.
setup senechal
rc=$?
check "one repo failing to wire refuses the run" "$([ "$rc" -ne 0 ] && echo refused || echo "exited 0")" "refused"
case "$(cat "$TMP/err")" in
    *"git wiring FAILED"*senechal*) ok "...naming the repo that failed" ;;
    *) bad "the refusal names the repo" "stderr: $(cat "$TMP/err")" ;;
esac
check "...and did NOT land the account" \
      "$([ -f "$PHOME/LANDED" ] && echo landed || echo stopped)" "stopped"
check "...nor run the release bootstrap" \
      "$([ -f "$TMP/RELEASE-BOOTSTRAPPED" ] && echo ran || echo stopped)" "stopped"
case "$(cat "$TMP/out")" in
    *"WITNESS FAILED"*) ok "...and the underlying witness failure is still shown, not swallowed by the gate" ;;
    *) bad "the wiring script's own output survives" "stdout: $(cat "$TMP/out")" ;;
esac

# --- 3. EVERY failing repo is named, not the first -----------------------
# The issue asks for all of them, and it is the difference between one repo to
# re-wire and three. The loop must therefore run to the end and refuse after.
setup realisateur senechal "$PROJECT"
rc=$?
check "three repos failing still refuses" "$([ "$rc" -ne 0 ] && echo refused || echo "exited 0")" "refused"
named=0
for r in realisateur senechal "$PROJECT"; do
    case "$(cat "$TMP/err")" in *"$r"*) named=$((named+1)) ;; esac
done
check "...naming all three, not just the first" "$named" "3"
check "...having tried all four repos rather than stopping at the first failure" \
      "$(sort -u "$PHOME/wire-calls" | wc -l | tr -d ' ')" "4"
case "$(cat "$TMP/err")" in
    *scheduler*) bad "the refusal names only what failed" "scheduler wired fine and is named: $(cat "$TMP/err")" ;;
    *) ok "...and NOT the repo that wired cleanly" ;;
esac

echo
echo "-- 9. the project's own runtime secrets: declared, never supplied -------"
mkdir -p "$PHOME/Documents/Projects/$PROJECT"
setup; OUT="$(cat "$TMP/out" "$TMP/err")"
case "$OUT" in
  *"declares no runtime secrets"*) ok "9a a project with no declaration says so, rather than saying nothing" ;;
  *) bad "9a expected the no-declaration line" "got: $(printf '%s' "$OUT" | tail -3)" ;;
esac

printf '%s/creds/ha_token\n' "$PHOME" > "$PHOME/Documents/Projects/$PROJECT/.selfdev-secrets"
setup; OUT="$(cat "$TMP/out" "$TMP/err")"
case "$OUT" in
  *"MISSING"*ha_token*) ok "9b a declared secret that is absent is reported MISSING, by path" ;;
  *) bad "9b expected a MISSING line naming ha_token" "got: $(printf '%s' "$OUT" | tail -3)" ;;
esac
case "$OUT" in
  *"will not"*) ok "9c ...and it says plainly that this script does not supply them" ;;
  *) bad "9c expected the refusal-to-supply line" "got: $(printf '%s' "$OUT" | tail -3)" ;;
esac

mkdir -p "$PHOME/creds" && : > "$PHOME/creds/ha_token"
setup; OUT="$(cat "$TMP/out" "$TMP/err")"
case "$OUT" in
  *"MISSING $PHOME/creds/ha_token"*) bad "9d a present secret should not be reported missing" "got: $(printf '%s' "$OUT" | grep MISSING | head -1)" ;;
  *) ok "9d a declared secret that IS present stops being a finding" ;;
esac

echo
summary
