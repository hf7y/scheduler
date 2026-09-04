#!/usr/bin/env bash
# cutoff-ledger-witness.sh -- hf7y/scheduler#347 item 1: a NOT-DONE ledger row
# is typed WORKED-CUTOFF when run-record.sh's own git/gh-derived verdict for
# that exact run says so, so a run that pushed something before the ceiling
# stops being indistinguishable from one that touched nothing at all.
#
# Extracts rr_last_verdict() and typed_ledger_outcome() straight out of
# bin/usage-paced-runner.sh, same technique as resume-hint-witness.sh, so this
# tests the real function bodies rather than a reimplementation of them.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "cutoff-ledger-witness"

BLOCK="$TMP/funcs.sh"
awk '/^rr_last_verdict\(\) \{$/,/^\}$/' "$RUNNER"       >  "$BLOCK"
awk '/^typed_ledger_outcome\(\) \{$/,/^\}$/' "$RUNNER"  >> "$BLOCK"
grep -q 'rr_last_verdict'      "$BLOCK" || { echo "FAIL: could not extract rr_last_verdict() from $RUNNER"; exit 1; }
grep -q 'typed_ledger_outcome' "$BLOCK" || { echo "FAIL: could not extract typed_ledger_outcome() from $RUNNER"; exit 1; }
. "$BLOCK"

echo "== rr_last_verdict"

echo "-- 1. no file at all -- empty, not a guess"
out="$(rr_last_verdict never-seen "$TMP/nohome")"
[ -z "$out" ] && ok "missing JSONL prints nothing" || bad "expected nothing, got: $out"

echo "-- 2. one line, verdict_computed WORKED-CUTOFF"
mkdir -p "$TMP/home1/.local/share/scheduler-runs"
printf '{"schema":1,"job":"x","verdict_computed":"WORKED-CUTOFF","claimed_verdict":"none"}\n' \
  > "$TMP/home1/.local/share/scheduler-runs/proj.jsonl"
out="$(rr_last_verdict proj "$TMP/home1")"
[ "$out" = "WORKED-CUTOFF" ] && ok "reads WORKED-CUTOFF off the row" || bad "expected WORKED-CUTOFF, got: $out"

echo "-- 3. multiple lines -- the LAST one wins, not the first"
{
  printf '{"verdict_computed":"WORKED"}\n'
  printf '{"verdict_computed":"IDLE"}\n'
} > "$TMP/home1/.local/share/scheduler-runs/multi.jsonl"
out="$(rr_last_verdict multi "$TMP/home1")"
[ "$out" = "IDLE" ] && ok "tail -n1 semantics: most recent row wins" || bad "expected IDLE, got: $out"

echo "-- 4. empty file -- empty"
: > "$TMP/home1/.local/share/scheduler-runs/empty.jsonl"
out="$(rr_last_verdict empty "$TMP/home1")"
[ -z "$out" ] && ok "empty JSONL prints nothing" || bad "expected nothing, got: $out"

echo "-- 5. host-mode style read: acct set, goes through sudo"
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in -n) shift ;; -u) shift 2 ;; *) break ;; esac
done
exec "$@"
EOF
chmod +x "$FAKEBIN/sudo"
mkdir -p "$TMP/acct-home/.local/share/scheduler-runs"
printf '{"verdict_computed":"WORKED-CUTOFF"}\n' > "$TMP/acct-home/.local/share/scheduler-runs/hosted.jsonl"
out="$(PATH="$FAKEBIN:$PATH" rr_last_verdict hosted "$TMP/acct-home" someacct)"
[ "$out" = "WORKED-CUTOFF" ] && ok "acct given -- routed through sudo -n -u <acct>, still reads the row" \
  || bad "expected WORKED-CUTOFF via sudo path, got: $out"

echo "== typed_ledger_outcome"

echo "-- 6. outcome is NOT-DONE, run-record says WORKED-CUTOFF -- upgraded"
out="$(typed_ledger_outcome proj NOT-DONE "$TMP/home1")"
[ "$out" = "WORKED-CUTOFF" ] && ok "NOT-DONE + RR WORKED-CUTOFF upgrades the ledger outcome" \
  || bad "expected WORKED-CUTOFF, got: $out"

echo "-- 7. outcome is NOT-DONE, no run-record evidence at all -- stays NOT-DONE"
out="$(typed_ledger_outcome never-seen NOT-DONE "$TMP/nohome")"
[ "$out" = "NOT-DONE" ] && ok "no RR evidence -- outcome is left exactly as classified" \
  || bad "expected NOT-DONE, got: $out"

echo "-- 8. outcome is NOT-DONE, run-record says a non-cutoff verdict -- stays NOT-DONE"
mkdir -p "$TMP/home2/.local/share/scheduler-runs"
printf '{"verdict_computed":"IDLE"}\n' > "$TMP/home2/.local/share/scheduler-runs/idled.jsonl"
out="$(typed_ledger_outcome idled NOT-DONE "$TMP/home2")"
[ "$out" = "NOT-DONE" ] && ok "RR says IDLE, not WORKED-CUTOFF -- no upgrade" || bad "expected NOT-DONE, got: $out"

echo "-- 9. outcome is something other than NOT-DONE -- never touched, even with cutoff evidence"
for other in DONE BLOCKED GAVE-UP; do
  out="$(typed_ledger_outcome proj "$other" "$TMP/home1")"
  [ "$out" = "$other" ] && ok "an explicit '$other' verdict is left alone" || bad "expected $other, got: $out"
done

echo
echo "cutoff-ledger-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
