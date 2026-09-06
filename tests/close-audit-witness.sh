#!/usr/bin/env bash
# HERMETIC: a stub gh (CLOSE_AUDIT_GH_BIN) answers `repo view`/`api graphql`
# from fixture JSON -- no network, no live tracker.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/../bin/close-audit.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "close-audit-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

mkstub() {
  # $1 = graphql JSON body to emit
  cat > "$W/gh" <<STUB
#!/usr/bin/env bash
if [ "\$1 \$2" = "repo view" ]; then
  echo "hf7y/scheduler"
  exit 0
fi
if [ "\$1 \$2" = "api graphql" ]; then
  cat <<'JSON'
$1
JSON
  exit 0
fi
echo "stub gh: unexpected args: \$*" >&2
exit 1
STUB
  chmod +x "$W/gh"
}

echo "-- 1. a merged PR whose linked issue is still open"
mkstub '{"data":{"repository":{"pullRequests":{"nodes":[
  {"number":10,"url":"https://x/pr/10","closingIssuesReferences":{"nodes":[{"number":5,"state":"OPEN","url":"https://x/issues/5"}]}}
]}}}}'
out="$(CLOSE_AUDIT_GH_BIN="$W/gh" bash "$C" hf7y/scheduler 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "a merged PR with an open linked issue exits 1" || bad "exited $rc, want 1: $out"
grep -q 'pr/10 -> https://x/issues/5' <<<"$out" && ok "the mismatch names both the PR and the open issue" \
  || bad "mismatch row missing or malformed: $out"

echo "-- 2. a merged PR whose linked issue is closed: silent"
mkstub '{"data":{"repository":{"pullRequests":{"nodes":[
  {"number":11,"url":"https://x/pr/11","closingIssuesReferences":{"nodes":[{"number":6,"state":"CLOSED","url":"https://x/issues/6"}]}}
]}}}}'
out="$(CLOSE_AUDIT_GH_BIN="$W/gh" bash "$C" hf7y/scheduler 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a merged PR whose linked issue is closed exits 0" || bad "exited $rc, want 0: $out"
grep -qi 'clean' <<<"$out" && ok "reports clean" || bad "did not report clean: $out"

echo "-- 3. a PR closing nothing (no Fixes/Closes) is not a mismatch"
mkstub '{"data":{"repository":{"pullRequests":{"nodes":[
  {"number":12,"url":"https://x/pr/12","closingIssuesReferences":{"nodes":[]}}
]}}}}'
out="$(CLOSE_AUDIT_GH_BIN="$W/gh" bash "$C" hf7y/scheduler 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a PR with no linked issue is not flagged" || bad "exited $rc, want 0: $out"

echo "-- 4. --limit is validated"
out="$(bash "$C" --limit banana hf7y/scheduler 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "a non-numeric --limit is refused" || bad "exited $rc, want 2: $out"

echo "-- 5. a broken gh call is BROKEN, not silently clean"
cat > "$W/gh-fail" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "repo view" ] && { echo "hf7y/scheduler"; exit 0; }
echo "network unreachable" >&2
exit 1
STUB
chmod +x "$W/gh-fail"
out="$(CLOSE_AUDIT_GH_BIN="$W/gh-fail" bash "$C" hf7y/scheduler 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "a failed gh call exits 2 (BROKEN), not 0 (clean)" || bad "exited $rc, want 2: $out"

printf '\nclose-audit-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
