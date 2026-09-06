#!/usr/bin/env bash
# Witness for bin/roster-arm-audit.sh (#305). Hermetic: fake gh/sudo/crontab.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/roster-arm-audit.sh"

echo "roster-arm-audit-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "roster-arm-audit-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"

cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\${FAKE_GH_MODE:-ok}" = "fail" ]; then
  echo "gh: authentication failed" >&2
  exit 1
fi
if [ "\$1" = "api" ]; then
  case "\$2" in
    repos/*/contents/schedule/ROSTER*)
      printf '%s' "\$FAKE_ROSTER_CONTENT" | base64 -w0 ;;
    *)
      echo "scheduler" ;;
  esac
  exit 0
fi
echo "stub gh: unexpected args: \$*" >&2
exit 1
EOF
chmod +x "$FAKEBIN/gh"

# fake sudo passes -u's account through an env var so fake crontab below
# can pick the right fixture file per account.
cat > "$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
acct=""
while [ "$#" -gt 0 ]; do
  case "$1" in -n) shift ;; -u) acct="$2"; shift 2 ;; *) break ;; esac
done
[ -n "$acct" ] && export CRON_ACCT="$acct"
exec "$@"
EOF
chmod +x "$FAKEBIN/sudo"

cat > "$FAKEBIN/crontab" <<'EOF'
#!/usr/bin/env bash
: "${WORK:?}"
acct="${CRON_ACCT:-local}"
FILE="$WORK/cron-$acct"
if [ "$1" = "-l" ]; then
  [ -s "$FILE" ] || { echo "no crontab for $acct" >&2; exit 1; }
  cat "$FILE"
else
  echo "fake crontab: unsupported args: $*" >&2; exit 2
fi
EOF
chmod +x "$FAKEBIN/crontab"

export PATH="$FAKEBIN:$PATH"
export WORK
export DOSE_HOST_OVERRIDE="testhost"
export DOSE_SCHEDULE_DIR="$WORK/schedule"
mkdir -p "$DOSE_SCHEDULE_DIR"
printf 'RUNNER_JOB="scheduler-paced-runner"\nRUNNER_CMD="bin/usage-paced-runner.sh"\n' \
  > "$DOSE_SCHEDULE_DIR/_runner.conf"
TAG='# scheduler:scheduler-paced-runner:RUNNER (usage-paced dispatch)'

ROSTER="armed-and-running | ok-acct@testhost | 20m | live
armed-but-dark | dark-acct@testhost | 20m | live
parked-project | parked-acct@testhost | 20m | parked
elsewhere | else-acct@otherhost | 20m | live"

echo "-- 1. a live row whose account crontab carries the RUNNER line: ok, exit 0"
printf '0,20,40 * * * * /some/cmd %s\n' "$TAG" > "$WORK/cron-ok-acct"
: > "$WORK/cron-dark-acct"  # gets overwritten in test 2; empty here so test 1 alone would flag it
rm -f "$WORK/cron-dark-acct"
printf '0,20,40 * * * * /some/cmd %s\n' "$TAG" > "$WORK/cron-dark-acct"
export FAKE_GH_MODE=ok FAKE_ROSTER_CONTENT="$ROSTER"
out="$("$TARGET" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "both live rows on this host armed and running exits 0" || bad "exited $rc, want 0: $out"
grep -q "ok: 'armed-and-running'" <<<"$out" && ok "names the healthy row" || bad "missing healthy-row line: $out"
grep -q "elsewhere" <<<"$out" && bad "a row on a different host was checked at all: $out" \
  || ok "a row on a different host is skipped"
grep -q "parked-project" <<<"$out" && bad "a parked row was checked at all: $out" \
  || ok "a parked row is skipped"

echo "-- 2. a live row with no RUNNER line in its crontab: ARMED BUT NOT RUNNING, exit 1"
: > "$WORK/cron-dark-acct"
out="$("$TARGET" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "a live row missing its RUNNER line exits 1" || bad "exited $rc, want 1: $out"
grep -q "ARMED BUT NOT RUNNING: 'armed-but-dark'" <<<"$out" \
  && ok "names the project that is armed but not running" || bad "missing the ARMED BUT NOT RUNNING line: $out"
grep -q "dose armed-but-dark --apply" <<<"$out" && ok "names the fix" || bad "does not name the fix: $out"
grep -q "ok: 'armed-and-running'" <<<"$out" && ok "the healthy row is still reported alongside the bad one" \
  || bad "healthy row dropped once a bad one exists: $out"

echo "-- 3. no live row names this host: kept, exit 0"
export FAKE_ROSTER_CONTENT="only-elsewhere | acct@otherhost | 20m | live"
out="$("$TARGET" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "no live row on this host exits 0" || bad "exited $rc, want 0: $out"
grep -qi 'kept' <<<"$out" || bad "does not say kept when nothing applies here: $out"
export FAKE_ROSTER_CONTENT="$ROSTER"

echo "-- 4. an unreachable gh is BLIND (exit 6), not silently clean"
export FAKE_GH_MODE=fail
out="$("$TARGET" 2>&1)"; rc=$?
[ "$rc" -eq 6 ] && ok "unreachable gh exits 6 (blind)" || bad "exited $rc, want 6: $out"
grep -qi blind <<<"$out" && ok "BLIND is named in the output" || bad "exit 6 but BLIND never named: $out"
export FAKE_GH_MODE=ok

echo "-- 5. no usable RUNNER_JOB (missing _runner.conf) is BROKEN (exit 5)"
mv "$DOSE_SCHEDULE_DIR/_runner.conf" "$DOSE_SCHEDULE_DIR/_runner.conf.bak"
out="$("$TARGET" 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && ok "a missing _runner.conf exits 5 (broken)" || bad "exited $rc, want 5: $out"
mv "$DOSE_SCHEDULE_DIR/_runner.conf.bak" "$DOSE_SCHEDULE_DIR/_runner.conf"

printf '\nroster-arm-audit-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
