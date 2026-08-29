#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"
ROOT="$(cd "$(dirname "$0")/../bin" && pwd)"  # tests/ -> bin/ (was bin/tests/ in realisateur)
SCRIPT="$ROOT/vault-group-provision.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

harness_tmp

echo "vault-group-provision.test.sh"

section "A. the argument contract"
"$SCRIPT" --not-a-real-flag >/dev/null 2>&1; eq "A1 unknown flag exits 2" "$?" "2"
"$SCRIPT" --help >/dev/null 2>&1;            eq "A2 --help exits 0" "$?" "0"
OUT="$("$SCRIPT" --help 2>&1)"
has "A3 --help documents the BLIND exit" "$OUT" "BLIND"
has "A4 --help documents the refused-without-root exit" "$OUT" "refused"

section "B. an empty roster is BLIND, not a silent pass"
mkdir -p "$T/emptyhome"
OUT="$(HOME_ROOT="$T/emptyhome" SUDO='' "$SCRIPT" --check 2>&1)"; RC=$?
eq  "B1 no accounts under HOME_ROOT exits 6" "$RC" "6"
has "B2 and says BLIND" "$OUT" "BLIND"
has "B3 and says nothing was measured" "$OUT" "nothing was measured"

section "C. a roster with one account, no privilege needed to read it (SUDO='')"
mkdir -p "$T/home/proj/.claude" "$T/home/zach/.claude"
OUT="$(HOME_ROOT="$T/home" SUDO='' "$SCRIPT" --check --group nonexistent-test-group 2>&1)"; RC=$?
has "C1 the fixture account is listed" "$OUT" "proj"
hasnt "C2 zach is excluded from the roster" "$OUT" "  ..      zach"
eq  "C3 a group that does not exist is a finding (exit 1), not exit 6" "$RC" "1"

section "D. --apply without root is refused, --check never needs it"
if [ "$(id -u)" -eq 0 ]; then
  ok "D1 skipped: running as root"
else
  OUT="$("$SCRIPT" --apply 2>&1)"; RC=$?
  eq  "D1 --apply without root exits 5" "$RC" "5"
  has "D1b and says so" "$OUT" "needs root"
fi
grep -q 'rm -rf' "$SCRIPT" && bad "D2 the script contains an rm -rf" || ok "D2 no rm -rf anywhere in the script"

section "E. it is declared, so it reaches a host by a named channel"
. "$ROOT/../lib/provision-set.sh"
ch="$(provision_channel vault-group-provision.sh 2>/dev/null)" || ch=""
eq "E1 the provision set declares it -- a human runs this once, on nobody's clock" "$ch" "provision"

echo
summary
