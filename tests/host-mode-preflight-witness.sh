#!/usr/bin/env bash
# host-mode-preflight-witness.sh -- `--check` must measure the identity the ARMED
# CRON ROW uses, and its parser must be defined before anything that can abort
# the tick. Rationale is in the code this pins.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "host-mode-preflight-witness"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/lib" "$TMP/repo"

echo
echo "A. ordering: the escalation string cannot outrun its variable"
assign_ln="$(grep -n '^PACED_HOST="${PACED_HOST:-' "$R" | head -1 | cut -d: -f1)"
gate_ln="$(grep -n '^# >>> pull gate$' "$R" | head -1 | cut -d: -f1)"
esc_ln="$(grep -n 'file_to_realisateur "the pull freeze"' "$R" | head -1 | cut -d: -f1)"
[ -n "$assign_ln" ] && ok "A1 PACED_HOST is assigned (line $assign_ln)" \
  || bad "A1 no PACED_HOST assignment found at all"
[ -n "$gate_ln" ] && ok "A2 the pull gate opens at line $gate_ln" \
  || bad "A2 the pull-gate marker was not found -- this witness is testing nothing"
if [ -n "$esc_ln" ] && [ -n "$gate_ln" ]; then
  [ "$esc_ln" -gt "$gate_ln" ] \
    && ok "A3 its escalation expands \$PACED_HOST at line $esc_ln, inside that gate" \
    || bad "A3 the escalation is not inside the pull gate; this assertion no longer means what it says"
else
  bad "A3 the escalation line was not found"
fi
if [ -n "$assign_ln" ] && [ -n "$gate_ln" ]; then
  [ "$assign_ln" -lt "$gate_ln" ] \
    && ok "A4 assignment ($assign_ln) precedes the gate ($gate_ln)" \
    || bad "A4 PACED_HOST is not assigned until $assign_ln, after the pull gate opens at $gate_ln -- under set -u the third consecutive blocked tick aborts on an unbound variable instead of filing"
fi

BLOCK="$(sed -n '/= --check \]; then$/,/^fi$/p' "$R")"
[ -n "$BLOCK" ] || { bad "the --check block could not be located in $R"; echo; exit 1; }
grep -q 'fetch_roster' <<<"$BLOCK" || { bad "the block found is not the --check block"; echo; exit 1; }
ok "A5 the --check block was located by its anchors"

CHECK="$TMP/check.sh"
{ printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'PACED_HOST="testhost"\n'
  printf 'SELF_DIR="%s/bin"\nREPO_ROOT="%s/repo"\n' "$TMP" "$TMP"
  printf 'id() { case "${1:-}" in -u) echo "$FAKE_UID" ;; -un) echo "$FAKE_UNAME" ;; esac; }\n'
  sed -n '/^roster_rows() {/,/^}/p' "$R"
  printf '%s\n' "$BLOCK"
  printf 'echo FELL-THROUGH\n'; } > "$CHECK"
chmod +x "$CHECK"

SEEN="$TMP/seen-sudo-user"
cat > "$TMP/lib/dose-common.sh" <<EOF
fetch_roster() {
  printf '%s' "\${SUDO_USER-<unset>}" > "$SEEN"
  [ -n "\${STUB_ROSTER:-}" ] || { echo "BLIND: stub refuses" >&2; return 6; }
  printf '%s\n' "\$STUB_ROSTER"
}
EOF

run() { FAKE_UID="$1" FAKE_UNAME="$2" "$CHECK" --check >"$TMP/out" 2>&1; echo $?; }

echo
echo "B. refusals"
rc="$(PACED_HOST_MODE=0 STUB_ROSTER='x | x@testhost | 2h | live' run 0 root)"
[ "$rc" = 2 ] && ok "B1 PACED_HOST_MODE=0 exits 2" || bad "B1 expected 2, got $rc"
grep -q 'PACED_HOST_MODE is not 1' "$TMP/out" && ok "B2 and says so" || bad "B2 message: $(cat "$TMP/out")"

rc="$(PACED_HOST_MODE=1 STUB_ROSTER='x | x@testhost | 2h | live' run 1000 someone)"
[ "$rc" = 2 ] && ok "B3 non-root exits 2" || bad "B3 expected 2, got $rc"
grep -q 'not root' "$TMP/out" && ok "B4 and says host mode needs root" || bad "B4 message: $(cat "$TMP/out")"

echo
echo "C. the cron identity, not the invoking one"
: > "$SEEN"
rc="$(PACED_HOST_MODE=1 SUDO_USER=ahuman STUB_ROSTER='x | x@testhost | 2h | live' run 0 root)"
got="$(cat "$SEEN")"
[ "$got" = "<unset>" ] \
  && ok "C1 fetch_roster ran with SUDO_USER unset -- the identity the cron row has" \
  || bad "C1 fetch_roster saw SUDO_USER='$got' -- the preflight borrows a credential the armed row will not have"
grep -q 'ignoring SUDO_USER=ahuman' "$TMP/out" \
  && ok "C2 and it says out loud whose credential it declined" \
  || bad "C2 it dropped SUDO_USER silently: $(cat "$TMP/out")"

echo
echo "D. an unreadable roster refuses rather than dispatching"
rc="$(PACED_HOST_MODE=1 run 0 root)"          # no STUB_ROSTER -> stub returns 6
[ "$rc" = 2 ] && ok "D1 a BLIND fetch exits 2" || bad "D1 expected 2, got $rc"
grep -q 'BLIND as root' "$TMP/out" \
  && ok "D2 and reports it as BLIND *as root*, not as an anonymous failure" \
  || bad "D2 message: $(cat "$TMP/out")"

echo
echo "E. it says whether tick 1 dispatches"
PARKED='a | a@testhost | 2h | parked
b | b@testhost | 2h | parked'
rc="$(PACED_HOST_MODE=1 STUB_ROSTER="$PARKED" run 0 root)"
[ "$rc" = 0 ] && ok "E1 an all-parked roster is a PASS (arming is safe)" || bad "E1 expected 0, got $rc: $(cat "$TMP/out")"
grep -q '0 live, 2 parked' "$TMP/out" && ok "E2 counts them: 0 live, 2 parked" || bad "E2 counts: $(cat "$TMP/out")"
grep -q 'dispatches NOTHING' "$TMP/out" && ok "E3 and says tick 1 dispatches nothing" || bad "E3 message: $(cat "$TMP/out")"

MIXED='a | a@testhost | 2h | live
b | b@testhost | 2h | parked
c | c@otherhost | 2h | live'
rc="$(PACED_HOST_MODE=1 STUB_ROSTER="$MIXED" run 0 root)"
[ "$rc" = 0 ] && ok "E4 a roster with live rows passes" || bad "E4 expected 0, got $rc"
grep -q '1 live, 1 parked' "$TMP/out" \
  && ok "E5 counts only THIS host's rows (c@otherhost excluded)" \
  || bad "E5 counts: $(cat "$TMP/out")"

rc="$(PACED_HOST_MODE=1 STUB_ROSTER='c | c@otherhost | 2h | live' run 0 root)"
[ "$rc" = 2 ] && ok "E6 a roster naming no row for this host refuses" || bad "E6 expected 2, got $rc"

echo
echo "F. a reader can tell which surface armed a dispatch"
dl="$(grep -n 'log "DISPATCH \[\$idx/\$n\]' "$R" | head -1)"
[ -n "$dl" ] && ok "F1 the DISPATCH log line exists" || bad "F1 no DISPATCH log line found"
if [ -n "$dl" ]; then
  grep -q 'PACED_CONF_SRC' <<<"$dl" \
    && ok "F2 it carries \$PACED_CONF_SRC -- in host mode conf= is an mktemp path and names no surface" \
    || bad "F2 the DISPATCH line logs only conf=\$PACED_CONF, an mktemp path in host mode: a reader cannot tell which surface armed it"
fi

printf '\nhost-mode-preflight-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
