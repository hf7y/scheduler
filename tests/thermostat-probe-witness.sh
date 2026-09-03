#!/usr/bin/env bash
# Witness for bin/thermostat-probe.sh. Hermetic: a fixture git repo, a fake gh
# on PATH and a fixture ledger, never the live estate.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC="$PWD/bin/thermostat-probe.sh"

echo "thermostat-probe-witness"

if [ ! -x "$SRC" ]; then
  echo "  FAIL: $SRC missing or not executable"
  echo "thermostat-probe-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
REPO="$WORK/repo"; mkdir -p "$REPO/bin" "$REPO/schedule" "$REPO/lib"
cp "$SRC" "$REPO/bin/"
cp "$PWD/lib/run-ledger.sh" "$PWD/lib/blind-witness.sh" "$REPO/lib/"
printf 'REPO_URL="https://github.com/hf7y/quux.git"\n' > "$REPO/schedule/quux.conf"
printf '#TEMPO_BASE_MIN=120\n' > "$REPO/schedule/_tempo.conf"

git -C "$REPO" init -q
git -C "$REPO" config user.email w@example.com
git -C "$REPO" config user.name witness
git -C "$REPO" add -A
GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' \
  git -C "$REPO" commit -qm fixture

NOW="$(date +%s)"
OLD="$(date -u -d "@$((NOW - 90000))" +%Y-%m-%dT%H:%M:%SZ)"
MID="$(date -u -d "@$((NOW - 3600))" +%Y-%m-%dT%H:%M:%SZ)"

issue() { printf '{"number":%s,"state":"%s","createdAt":"%s","closedAt":%s,"labels":[]}' "$1" "$2" "$OLD" "$3"; }
cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
[ "\${FAKE_GH_MODE:-ok}" = fail ] && exit 1
if [ "\${FAKE_GH_MODE:-ok}" = still ]; then
  echo '[$(issue 1 OPEN null),$(issue 2 OPEN null)]'
else
  echo '[$(issue 1 OPEN null),$(issue 2 CLOSED "\"$MID\""),$(issue 3 CLOSED "\"$MID\"")]'
fi
EOF
chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH"

LEDGER_MOVED="$WORK/moved.tsv"
printf '%s\tmonkey\tquux\tquux\tbatch\t0\tCONTINUE\t\n' "$OLD" >  "$LEDGER_MOVED"
printf '%s\tmonkey\tquux\tquux\tbatch\t0\tCONTINUE\t\n' "$MID" >> "$LEDGER_MOVED"
LEDGER_STILL="$WORK/still.tsv"
printf '%s\tmonkey\tquux\tquux\tbatch\t0\tCONTINUE\t\n' "$OLD" >  "$LEDGER_STILL"

P="$REPO/bin/thermostat-probe.sh"

out="$("$P" --help 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^usage:' <<<"$out" && ok "--help exits 0 and prints usage" || bad "--help: rc=$rc"

"$P" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "no project -> exit 2" || bad "no project -> rc=$rc, want 2"

"$P" quux --window-hours 0 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "--window-hours 0 -> exit 2" || bad "--window-hours 0 -> rc=$rc, want 2"

out="$(THERMOSTAT_LEDGER_FILE="$LEDGER_MOVED" "$P" quux 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'verdict=OK .*want_min=480->1440 turns=1->2' <<<"$out"; then
  ok "work in a config-quiet window moves want_min and the turn count -> OK"
else
  bad "moved case: rc=$rc out=$out"
fi

out="$(FAKE_GH_MODE=still THERMOSTAT_LEDGER_FILE="$LEDGER_STILL" "$P" quux 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'verdict=DOWN .*reason=pace_and_turns_stood_still' <<<"$out"; then
  ok "no movement -> DOWN, never OK"
else
  bad "still case: rc=$rc out=$out"
fi

out="$(FAKE_GH_MODE=fail THERMOSTAT_LEDGER_FILE="$LEDGER_MOVED" "$P" quux 2>&1)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q 'verdict=BLIND' <<<"$out"; then
  ok "unreadable tracker -> BLIND, exit 6"
else
  bad "blind tracker: rc=$rc out=$out"
fi

out="$(THERMOSTAT_LEDGER_FILE="$WORK/nope.tsv" "$P" quux 2>&1)"; rc=$?
[ "$rc" -eq 6 ] && ok "unreadable ledger -> BLIND, exit 6" || bad "blind ledger: rc=$rc out=$out"

printf '#TEMPO_BASE_MIN=60\n' >> "$REPO/schedule/_tempo.conf"
git -C "$REPO" commit -qam knob
out="$(THERMOSTAT_LEDGER_FILE="$LEDGER_MOVED" "$P" quux 2>&1)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q 'reason=config_changed_in_window' <<<"$out"; then
  ok "a knob commit inside the window -> BLIND, so a human edit can never be read as the thermostat working"
else
  bad "config-changed case: rc=$rc out=$out"
fi

echo "thermostat-probe-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
