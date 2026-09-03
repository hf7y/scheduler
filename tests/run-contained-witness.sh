#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

command -v systemd-run >/dev/null 2>&1 || { echo "SKIP: no systemd-run on this host -- cannot witness the containment path"; echo "PASS=0 FAIL=0"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
awk '/^run_contained\(\) \{$/,/^\}$/' "$LIB" > "$TMP/fn.sh"
grep -q 'systemd-run' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract run_contained() from $LIB"; exit 1; }
. "$TMP/fn.sh"  # shellcheck disable=SC1090

echo "== 1. happy path: a real cgroup cap is actually applied, not just claimed"
unset CONTAIN_CPU_QUOTA CONTAIN_MEM_MAX
OUT="$(run_contained bash -c '
  cg="/sys/fs/cgroup$(awk -F: "{print \$3}" /proc/self/cgroup)"
  cat "$cg/cpu.max" "$cg/memory.max" 2>/dev/null
  case "$(awk -F: "{print \$3}" /proc/self/cgroup)" in *.scope) echo IN_SCOPE ;; esac
' 2>&1)"
printf '%s\n' "$OUT" | grep -q '^containment: systemd --user scope, CPUQuota=150% MemoryMax=3G$' \
  && ok "prints the containment line with the built-in default cap" \
  || bad "no/wrong containment line in: $OUT"
printf '%s\n' "$OUT" | grep -q 'IN_SCOPE' \
  && ok "the wrapped command actually ran inside a systemd scope cgroup" \
  || bad "wrapped command's own cgroup was not a .scope: $OUT"
printf '%s\n' "$OUT" | grep -qE '^[0-9]+ 100000$' \
  && ok "cpu.max reflects a real (not unlimited) CPU quota" \
  || bad "cpu.max did not show a bounded quota: $OUT"

echo "== 2. a host-configured cap is honored, not just the default"
OUT2="$(CONTAIN_CPU_QUOTA=37% CONTAIN_MEM_MAX=123M bash -c '. "'"$TMP"'/fn.sh"; run_contained true' 2>&1)"
printf '%s\n' "$OUT2" | grep -q 'CPUQuota=37% MemoryMax=123M' \
  && ok "CONTAIN_CPU_QUOTA/CONTAIN_MEM_MAX override the default" \
  || bad "override not honored: $OUT2"

echo "== 3. exit status is exactly the wrapped command's own"
run_contained bash -c 'exit 0'; RC0=$?
run_contained bash -c 'exit 17'; RC17=$?
[ "$RC0" = 0 ] && [ "$RC17" = 17 ] \
  && ok "exit codes (0 and 17) pass through the systemd-run wrapper unchanged" \
  || bad "got rc0=$RC0 rc17=$RC17, wanted 0 and 17"

echo "== 4. capability probe fails -> loud WARNING, job still runs (fallback), exit code still correct"
systemd-run() { return 1; }
OUT3="$(run_contained bash -c 'echo ran; exit 5' 2>&1)"; RC3=$?
printf '%s\n' "$OUT3" | grep -q '^WARNING: containment:' \
  && ok "prints a loud WARNING when the scope probe fails" \
  || bad "no WARNING on probe failure: $OUT3"
printf '%s\n' "$OUT3" | grep -q '^ran$' \
  && ok "the job still runs under the fallback (fail-open, not fail-closed)" \
  || bad "job did not run under fallback: $OUT3"
[ "$RC3" = 5 ] \
  && ok "exit code (5) still passes through the nice/ionice fallback" \
  || bad "fallback exit code wrong: got $RC3, wanted 5"
unset -f systemd-run

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
