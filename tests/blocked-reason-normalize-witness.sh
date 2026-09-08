#!/usr/bin/env bash
set -uo pipefail  # #671: BLOCKED-HOLD must double for a repeated reason differing only in volatile tokens, not for a genuinely different one

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNNER="$REPO/bin/usage-paced-runner.sh"
[ -x "$RUNNER" ] || { echo "FAIL: no runner at $RUNNER"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

H="$T/home"; mkdir -p "$H"
cat > "$H/own-run" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$H/own-run"

conf="$T/paced.conf"
printf 'same|1|%s same batch\ndiffer|1|%s differ batch\n' "$H/own-run" "$H/own-run" > "$conf"
roster="$T/ROSTER"
printf 'same | same@monkey | 20m | live\ndiffer | differ@monkey | 20m | live\n' > "$roster"

cat > "$H/gate.sh" <<'EOF'
#!/usr/bin/env bash
echo "verdict=RUN"
exit 0
EOF
chmod +x "$H/gate.sh"

STATE="$H/.local/share/scheduler-paced-runner"; mkdir -p "$STATE"
LOG="$STATE/run.log"
LEDGER="$STATE/ledger.tsv"
cat > "$LEDGER" <<EOF
2026-09-01T10:01:03-05:00	monkey	acct	same	batch	1	BLOCKED	ssh dexter refused at 10:01:03, PR #101, probe 42
2026-09-01T14:22:59-05:00	monkey	acct	same	batch	1	BLOCKED	ssh dexter refused at 14:22:59, PR #101, probe 187
2026-09-01T10:01:03-05:00	monkey	acct	differ	batch	1	BLOCKED	ssh dexter refused, no route to host
2026-09-01T14:22:59-05:00	monkey	acct	differ	batch	1	BLOCKED	docker missing on host, cannot run container
EOF

HOME="$H" PACED_CONF="$conf" PACED_HOST=monkey PACED_MAX_PER_TICK=2 \
  SCHEDULER_ROSTER_FILE="$roster" LEDGER_BLOCKED_HOLD=6 \
  USAGE_GATE="$H/gate.sh" "$RUNNER" >/dev/null 2>&1

grep -q 'BLOCKED-HOLD same -- 0/24 opportunit' "$LOG" \
  || fail "same wall (differs only in numbers) should double the hold to 24: $(grep 'BLOCKED-HOLD same' "$LOG")"

grep -q 'BLOCKED-HOLD differ -- 0/12 opportunit' "$LOG" \
  || fail "genuinely different walls should NOT double the hold, want 12: $(grep 'BLOCKED-HOLD differ' "$LOG")"

if [ "$FAILED" -ne 0 ]; then
  echo "--- run.log ---"
  sed 's/^/  /' "$LOG" 2>/dev/null
  exit 1
fi
echo "OK: BLOCKED-HOLD doubles for a repeated reason that differs only in numbers, and does not double for a genuinely different one"
