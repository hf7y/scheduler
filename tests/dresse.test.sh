#!/usr/bin/env bash
#
# Cases:
#   A --check runs every host step and writes nothing
#   B a step that exits nonzero under --check is a GAP, not a refusal
#   C exit 6 from a step is BLIND -- never folded into GAP, never "ok"
#   D --apply as non-root refuses (exit 2); no step runs
#   E a provision-class script no step reaches is PRINTED as uncovered
#   F a step whose script is not declared in the provision set is a BAD plan (exit 1)
#   G no provision set -> BLIND, exit 6
#
# Usage: tests/dresse.test.sh   (exit 0 = all pass)

set -uo pipefail
# shellcheck source=tests/lib/harness.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"
REPO_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"  # tests/ -> bin/ (was bin/tests/ in realisateur)
[ -f "$REPO_BIN/dresse.sh" ] || { echo "FAIL: no dresse.sh"; exit 1; }
harness_tmp

# A stub estate: dresse.sh, the cli-guard it sources, and stand-in steps whose
# exit codes the cases drive. Real steps would need root and a real host.
# bin/ and lib/ as SIBLINGS, which is this repo's layout: dresse.sh reaches
# both through ../lib. In realisateur they were bin/ and bin/lib/.
mkdir -p "$T/bin" "$T/lib"
cp "$REPO_BIN/dresse.sh" "$T/bin/"
cp "$REPO_BIN/../lib/cli-guard.sh" "$T/lib/"
D="$T/bin/dresse.sh"
RAN="$T/ran.log"

stub() { # stub <name> <exit code>
  printf '#!/usr/bin/env bash\necho "%s: $*" >> "%s"\nexit %s\n' "$1" "$RAN" "$2" > "$T/bin/$1"
  chmod +x "$T/bin/$1"
}

# The provision set the stub reads. Same variable name and same
# provision_channel contract as lib/provision-set.sh; nothing else is needed.
write_set() { # write_set <provision-list>
  cat > "$T/lib/provision-set.sh" <<EOF
PROVISION_SCRIPTS="
$1
"
provision_channel() {
  local n="\$1" s
  for s in \$PROVISION_SCRIPTS; do [ "\$s" = "\$n" ] && { echo provision; return 0; }; done
  return 1
}
EOF
}

STEPS='dresse.sh
setup-selfdev-project.sh
selfdev-app-key.sh
selfdev-claude-token.sh
wire-release-channel.sh
selfdev-permissions-provision.sh
selfdev-hooks-provision.sh'

write_set "$STEPS
pivot.sh"
for s in selfdev-app-key.sh selfdev-claude-token.sh wire-release-channel.sh \
         selfdev-permissions-provision.sh selfdev-hooks-provision.sh; do stub "$s" 0; done
# The indirect set is READ OUT of this file, so the stub names what it runs.
stub setup-selfdev-project.sh 0
printf '# runs provision-selfdev-user.sh wire-selfdev-git.sh land-selfdev.sh\n' >> "$T/bin/setup-selfdev-project.sh"

section "A. --check runs the plan and writes nothing"
: > "$RAN"
out="$(bash "$D" --host --check 2>&1)"; rcv=$?
rc "A1 exit 0 when every step is satisfied" 0 "$rcv"
has "A2 the App key step ran" "$(cat "$RAN")" "selfdev-app-key.sh: --check"
has "A3 the channel step ran with --host" "$(cat "$RAN")" "wire-release-channel.sh: --host --check"
has "A4 says nothing was done" "$out" "nothing done (--check)"
APPLY_FLAG=--apply
hasnt "A5 no step was told --apply" "$(cat "$RAN")" "$APPLY_FLAG"

section "B. nonzero under --check is a GAP, not a refusal"
stub selfdev-app-key.sh 1
out="$(bash "$D" --host --check 2>&1)"; rcv=$?
has "B1 reported as GAP" "$out" "GAP     selfdev-app-key.sh"
rc  "B2 still exit 0 -- work to do is not a refusal" 0 "$rcv"

section "C. exit 6 is BLIND and is never clean"
stub selfdev-app-key.sh 6
out="$(bash "$D" --host --check 2>&1)"; rcv=$?
has "C1 reported as BLIND" "$out" "BLIND   selfdev-app-key.sh"
hasnt "C2 not called a gap" "$out" "GAP     selfdev-app-key.sh"
rc  "C3 exit 1 -- a step that could not look fails the run" 1 "$rcv"
stub selfdev-app-key.sh 0

section "D. --apply as non-root refuses before any step"
: > "$RAN"
out="$(bash "$D" --host --apply 2>&1)"; rcv=$?
rc "D1 exit 2" 2 "$rcv"
has "D2 names root" "$out" "must run as root"
eq  "D3 no step ran" "$(cat "$RAN")" ""

section "E. an unreached provision-class script is printed"
out="$(bash "$D" --host --check 2>&1)"
has "E1 pivot.sh named as uncovered" "$out" "not covered by dresse: pivot.sh"
hasnt "E2 dresse does not report itself" "$out" "not covered by dresse: dresse.sh"

section "F. a step outside the provisioning set is a bad plan"
: > "$RAN"
write_set "dresse.sh
setup-selfdev-project.sh
selfdev-app-key.sh"
out="$(bash "$D" --host --check 2>&1)"; rcv=$?
has "F1 names the undeclared step" "$out" "is not declared in lib/provision-set.sh"
rc  "F2 exit 1" 1 "$rcv"
eq  "F3 no step ran on a bad plan" "$(cat "$RAN")" ""

section "F2. coverage is derived, not recorded"
write_set "$STEPS
pivot.sh
provision-selfdev-user.sh"
out="$(bash "$D" --host --check 2>&1)"
hasnt "F2a a script setup-selfdev-project.sh runs is not called uncovered" "$out" "not covered by dresse: provision-selfdev-user.sh"
mv "$T/bin/setup-selfdev-project.sh" "$T/bin/setup-selfdev-project.sh.away"
out="$(bash "$D" --host --check 2>&1)"; rcv=$?
has "F2b with that file gone, coverage is BLIND rather than assumed" "$out" "coverage is unverifiable"
rc  "F2c and the run is BLIND (6), not a finding" 6 "$rcv"
mv "$T/bin/setup-selfdev-project.sh.away" "$T/bin/setup-selfdev-project.sh"

section "G. no provision set is BLIND, never clean"
rm -f "$T/lib/provision-set.sh"
out="$(bash "$D" --host --check 2>&1)"; rcv=$?
rc "G1 exit 6" 6 "$rcv"
has "G2 says BLIND" "$out" "BLIND"

summary
