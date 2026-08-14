#!/usr/bin/env bash
# Witness for run_debroussaille_sweep() in bin/scheduler-dev-cycle.sh
# (hf7y/scheduler#37): scheduler's own paced rotation now clears its own
# provably-recoverable git debris every cycle. This exercises the WIRING
# (called how, on what, failure handling) -- debroussaille.sh's own branch
# and worktree logic is covered separately by tests/debroussaille-witness.sh.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/scheduler-dev-cycle.sh"
[ -f "$SRC" ] || { echo "script under test not found: $SRC"; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Pull the function's own bytes out of the script under test, so the test
# exercises shipped code rather than a copy that can drift from it (same
# approach as tests/reconcile-witness.sh).
FUNC="$(awk '/^run_debroussaille_sweep\(\) \{/,/^\}/' "$SRC")"
[ -n "$FUNC" ] || { echo "could not extract function"; exit 1; }
eval "$FUNC"

echo "== 1. debroussaille.sh present -> invoked with --apply \$SCHED_REPO"
SCHED_REPO="$TMP/repo1"; mkdir -p "$SCHED_REPO/bin"
CALLLOG="$TMP/calls1"
cat > "$SCHED_REPO/bin/debroussaille.sh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLLOG"
exit 0
EOF
chmod +x "$SCHED_REPO/bin/debroussaille.sh"
out="$(run_debroussaille_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "clean run exits 0" || bad "exited $rc"
[ -f "$CALLLOG" ] && grep -qF -- "--apply $SCHED_REPO" "$CALLLOG" \
  && ok "invoked with --apply and the repo path" || bad "wrong/missing invocation: $(cat "$CALLLOG" 2>/dev/null)"

echo "== 2. debroussaille.sh exits nonzero -> reported, cycle not aborted"
SCHED_REPO="$TMP/repo2"; mkdir -p "$SCHED_REPO/bin"
cat > "$SCHED_REPO/bin/debroussaille.sh" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 5
EOF
chmod +x "$SCHED_REPO/bin/debroussaille.sh"
out="$(run_debroussaille_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a failing sweep does not propagate a nonzero exit" || bad "function exited $rc"
grep -q "nonzero exit" <<<"$out" && ok "failure is named, not swallowed silently" || bad "silent failure: $out"

echo "== 3. debroussaille.sh missing -> skipped, named as a finding"
SCHED_REPO="$TMP/repo3"; mkdir -p "$SCHED_REPO/bin"
out="$(run_debroussaille_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a missing script does not fail the cycle" || bad "function exited $rc"
grep -q "SKIPPED" <<<"$out" && ok "the skip is named" || bad "silent skip: $out"

echo "== 4. debroussaille.sh present but not executable -> skipped, named"
SCHED_REPO="$TMP/repo4"; mkdir -p "$SCHED_REPO/bin"
cat > "$SCHED_REPO/bin/debroussaille.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod -x "$SCHED_REPO/bin/debroussaille.sh"
out="$(run_debroussaille_sweep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a non-executable script does not fail the cycle" || bad "function exited $rc"
grep -q "SKIPPED" <<<"$out" && ok "the skip is named" || bad "silent skip: $out"

echo
echo "==== debroussaille-sweep witness: $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
