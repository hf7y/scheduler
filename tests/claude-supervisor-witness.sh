#!/usr/bin/env bash
set -uo pipefail  # witness for bin/claude-supervised.sh, hf7y/scheduler#339 -- hermetic: fake `claude`/`sleep` on PATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUP="$ROOT/bin/claude-supervised.sh"
[ -x "$SUP" ] || { echo "not found or not executable: $SUP"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "claude-supervisor-witness"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"

cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
n=0; [ -f "$FAKE_CLAUDE_COUNTER" ] && n="$(cat "$FAKE_CLAUDE_COUNTER")"
n=$((n + 1)); echo "$n" > "$FAKE_CLAUDE_COUNTER"
printf '%s\n' "$*" >> "$FAKE_CLAUDE_CALL_LOG"
if [ "$n" -le "${FAKE_CLAUDE_FAIL_COUNT:-0}" ]; then
  hm="$(date -u -d "+${FAKE_CLAUDE_RESET_AHEAD_SEC:-70} seconds" +'%I:%M%P')"
  echo "You've hit your session limit · resets ${hm} (UTC)"
  exit 1
fi
echo "OK RESUMED call=$n"
EOF
chmod +x "$FAKEBIN/claude"

cat > "$FAKEBIN/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SLEEP_LOG"
EOF
chmod +x "$FAKEBIN/sleep"

run_sup() {
  PATH="$FAKEBIN:$PATH" FAKE_CLAUDE_COUNTER="$WORK/counter" FAKE_CLAUDE_CALL_LOG="$WORK/calls" \
    FAKE_SLEEP_LOG="$WORK/sleeps" CLAUDE_SUPERVISED_LOG="$WORK/sup.log" \
    CLAUDE_SUPERVISED_MAX_RESUMES="${FAKE_MAX_RESUMES:-6}" \
    "$SUP" --session-id 11111111-1111-1111-1111-111111111111 --no-claim -- "$@"
}

echo
echo "== A. one session-limit death, then a clean resume"
rm -f "$WORK"/counter "$WORK"/calls "$WORK"/sleeps "$WORK"/sup.log
out="$(FAKE_CLAUDE_FAIL_COUNT=1 run_sup say-ok)"; rc=$?
[ "$rc" -eq 0 ] && ok "A1 exits 0 once the resume succeeds" || bad "A1 rc=$rc: $out"
case "$out" in *"OK RESUMED call=2"*) ok "A2 the SECOND call succeeded" ;; *) bad "A2 output: $out" ;; esac
grep -q -- "--resume 11111111-1111-1111-1111-111111111111" "$WORK/calls" \
  && ok "A3 the retry passed --resume with the same session id" || bad "A3 calls: $(cat "$WORK/calls")"
[ -s "$WORK/sleeps" ] && ok "A4 it slept before resuming" || bad "A4 no sleep recorded"
grep -q "WAIT session=11111111.*attempt=1" "$WORK/sup.log" && ok "A5 WAIT is logged" || bad "A5 log: $(cat "$WORK/sup.log")"
grep -q "RESUME session=11111111.*attempt=1" "$WORK/sup.log" && ok "A6 RESUME is logged" || bad "A6 log: $(cat "$WORK/sup.log")"

echo
echo "== B. a message with no parseable reset time gives up rather than guessing"
rm -f "$WORK"/counter "$WORK"/calls "$WORK"/sleeps "$WORK"/sup.log
cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "You've hit your session limit, no clock in this one"
exit 1
EOF
chmod +x "$FAKEBIN/claude"
out="$(run_sup say-ok)"; rc=$?
[ "$rc" -eq 1 ] && ok "B1 refuses (rc=1) rather than guessing a wait" || bad "B1 rc=$rc"
[ ! -s "$WORK/sleeps" ] && ok "B2 never slept" || bad "B2 slept: $(cat "$WORK/sleeps")"
grep -q "GIVE-UP" "$WORK/sup.log" && ok "B3 logs GIVE-UP" || bad "B3 log: $(cat "$WORK/sup.log")"

echo
echo "== C. MAX_RESUMES caps a run that never stops hitting the limit"
rm -f "$WORK"/counter "$WORK"/calls "$WORK"/sleeps "$WORK"/sup.log
cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "call" >> "$FAKE_CLAUDE_CALL_LOG"
echo "You've hit your session limit · resets 11:59pm (UTC)"
exit 1
EOF
chmod +x "$FAKEBIN/claude"
out="$(FAKE_MAX_RESUMES=2 run_sup say-ok)"; rc=$?
[ "$rc" -eq 1 ] && ok "C1 gives up (rc=1) rather than looping forever" || bad "C1 rc=$rc"
n="$(wc -l < "$WORK/calls")"
[ "$n" -eq 3 ] && ok "C2 tried exactly MAX_RESUMES+1 times (n=$n)" || bad "C2 calls=$n"
grep -q "GIVE-UP.*after 2 resume" "$WORK/sup.log" && ok "C3 names the cap it hit" || bad "C3 log: $(cat "$WORK/sup.log")"

echo
echo "== D. a claim already held elsewhere is refused before claude ever runs"
rm -f "$WORK"/counter "$WORK"/calls
CLAIMDIR="$WORK/claim"; mkdir -p "$CLAIMDIR"
(
  export USAGE_CLAIM_DIR="$CLAIMDIR"
  . "$ROOT/lib/usage-claim.sh"
  usage_claim_acquire "someone-else"
  sleep 5
) &
HP=$!
sleep 1
out="$(PATH="$FAKEBIN:$PATH" FAKE_CLAUDE_COUNTER="$WORK/counter" FAKE_CLAUDE_CALL_LOG="$WORK/calls" \
       USAGE_CLAIM_DIR="$CLAIMDIR" "$SUP" --session-id 22222222-2222-2222-2222-222222222222 -- say-ok 2>&1)"
rc=$?
kill -9 "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
[ "$rc" -eq 3 ] && ok "D1 refuses (rc=3) when the claim is already held" || bad "D1 rc=$rc: $out"
[ ! -f "$WORK/calls" ] && ok "D2 claude was never invoked" || bad "D2 calls: $(cat "$WORK/calls")"

echo
echo "claude-supervisor-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
