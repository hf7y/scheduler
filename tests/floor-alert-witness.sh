#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LIB="$REPO/lib/floor-alert.sh"
[ -r "$LIB" ] || { echo "FAIL: no lib at $LIB"; exit 1; }
source "$HERE/lib/witness-common.sh"

# shellcheck source=../lib/floor-alert.sh
. "$LIB"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STATE_DIR="$T/state"
SEND_LOG="$T/sends.log"
SEND_RESULT=0

floor_alert_send_zach() {
  printf '%s\t%s\n' "$1" "$2" >> "$SEND_LOG"
  return "$SEND_RESULT"
}

send_count() { wc -l < "$SEND_LOG" 2>/dev/null | tr -d ' '; }

echo "== a. first time at the floor sends exactly one ping"
rm -rf "$STATE_DIR"; : > "$SEND_LOG"; SEND_RESULT=0
floor_alert_maybe_ping proj "backlog-stuck" "$STATE_DIR" 12
[ "$(send_count)" = 1 ] && ok "one send on first arrival" || bad "expected 1 send, got $(send_count)"

echo "== b. same wall, next tick inside the persist window: no re-send"
floor_alert_maybe_ping proj "backlog-stuck" "$STATE_DIR" 12
[ "$(send_count)" = 1 ] && ok "still one send -- the window held it" || bad "re-sent inside the window: $(send_count)"

echo "== c. wall changes: pings again even inside the window"
floor_alert_maybe_ping proj "assignee-flood" "$STATE_DIR" 12
[ "$(send_count)" = 2 ] && ok "a changed wall re-pinged" || bad "expected 2 sends after a wall change, got $(send_count)"

echo "== d. after the persist window elapses at the SAME wall: re-pings"
STATE_FILE="$STATE_DIR/floor-alert-proj"
OLD_EPOCH=$(( $(date +%s) - 13 * 3600 ))
printf 'assignee-flood\t%s\n' "$OLD_EPOCH" > "$STATE_FILE"
floor_alert_maybe_ping proj "assignee-flood" "$STATE_DIR" 12
[ "$(send_count)" = 3 ] && ok "the window elapsing re-armed the same wall" || bad "expected 3 sends, got $(send_count)"

echo "== e. a failed delivery must not stamp -- the next tick retries"
rm -rf "$STATE_DIR"; : > "$SEND_LOG"; SEND_RESULT=1
floor_alert_maybe_ping proj "backlog-stuck" "$STATE_DIR" 12
[ "$(send_count)" = 1 ] && ok "attempted the send" || bad "did not even try: $(send_count)"
[ -r "$STATE_DIR/floor-alert-proj" ] && bad "a failed send still stamped the state file" \
  || ok "no stamp on a failed send"
floor_alert_maybe_ping proj "backlog-stuck" "$STATE_DIR" 12
[ "$(send_count)" = 2 ] && ok "the next opportunity retried rather than being swallowed" \
  || bad "expected a retry (2 sends), got $(send_count)"
SEND_RESULT=0
floor_alert_maybe_ping proj "backlog-stuck" "$STATE_DIR" 12
[ "$(send_count)" = 3 ] && [ -r "$STATE_DIR/floor-alert-proj" ] \
  && ok "a confirmed delivery finally stamps" || bad "a successful send did not stamp: $(send_count)"

echo "== f. the rendered message never exceeds 140 chars, structurally"
FROMS=(scheduler s a-considerably-longer-repo-name-than-usual)
BODY_LENS=(0 1 5 39 40 41 79 80 81 127 128 129 139 140 141 200 999)
F=0
for from in "${FROMS[@]}"; do
  for n in "${BODY_LENS[@]}"; do
    body="$(python3 -c "import sys; sys.stdout.write('q' * int(sys.argv[1]))" "$n")"
    fit="$(floor_alert_fit "$from" "$body")"
    rendered="$(floor_alert_render "$from" "$fit")"
    if [ "${#rendered}" -gt 140 ]; then
      bad "from='$from' body_len=$n -> rendered ${#rendered} chars, over 140: $rendered"
      F=1
    fi
  done
done
[ "$F" = 0 ] && ok "every from/body-length combination rendered at or under 140 chars"

echo "== g. wired: tempo.sh pings on HOLD at the floor, and only then"
GH_STUB_DIR="$T/bin"; mkdir -p "$GH_STUB_DIR"
cat > "$GH_STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = closed ] && { echo 0; exit 0; }; done
printf '40\t0\n'
EOF
chmod +x "$GH_STUB_DIR/gh"
TEMPO_STATE="$T/tempo-state"; mkdir -p "$TEMPO_STATE"
printf '%s\tmonkey\tacct\tfloor-fixture\tbatch\t0\tWORKED\tr\n' "$(date -Is -d '-1 min')" > "$T/ledger.tsv"
run_tempo() {
  PATH="$GH_STUB_DIR:$PATH" STATE_DIR="$TEMPO_STATE" RUN_LEDGER_FILE="$T/ledger.tsv" \
    TEMPO_REPO="fixture/floor" TEMPO_CACHE_MIN=0 TEMPO_BASE_MIN=1440 TEMPO_PIVOT_ISSUES=12 \
    TEMPO_MAX_MIN=60 TEMPO_MIN_MIN=20 FLOOR_ALERT_SEND_LOG="$T/wired-sends.log" \
    "$REPO/bin/tempo.sh" floor-fixture --quiet
}
: > "$T/wired-sends.log"
cat > "$GH_STUB_DIR/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FLOOR_ALERT_SEND_LOG"
data=""
prev=""
for a in "$@"; do
  [ "$prev" = -D ] && hdrfile="$a"
  [ "$prev" = -d ] && data="$a"
  prev="$a"
done
[ -n "${hdrfile:-}" ] && printf 'mcp-session-id: fake\r\n' > "$hdrfile"
case "$data" in
  *send_zach*) printf '{"result":{"content":[{"text":"{\\"status\\": \\"sent\\"}"}]}}' ;;
esac
exit 0
EOF
chmod +x "$GH_STUB_DIR/curl"
OUT1="$(run_tempo)"
[ "$OUT1" = HOLD ] && ok "the fixture holds at the floor as set up" || bad "fixture verdict=$OUT1, expected HOLD"
WIRED1="$(wc -l < "$T/wired-sends.log" | tr -d ' ')"
[ "$WIRED1" -ge 3 ] && ok "tempo.sh's floor hold drove a real send_zach attempt ($WIRED1 curl calls)" \
  || bad "expected the MCP handshake to run (>=3 curl calls), got $WIRED1"
run_tempo >/dev/null
WIRED2="$(wc -l < "$T/wired-sends.log" | tr -d ' ')"
[ "$WIRED2" = "$WIRED1" ] && ok "an unchanged wall on the very next tick made no second attempt" \
  || bad "expected no new curl calls on the second tick, went from $WIRED1 to $WIRED2"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
