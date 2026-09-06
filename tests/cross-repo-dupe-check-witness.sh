#!/usr/bin/env bash
set -uo pipefail  # HERMETIC: stub gh below answers from fixture JSON, no network
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/../bin/cross-repo-dupe-check.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "cross-repo-dupe-check-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

mkstub() {  # $1 = pr-list JSON rows (already -q formatted), $2 = issue-list rows
  cat > "$W/gh" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "list" ]; then
  printf '%s'"$1"
  exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "list" ]; then
  printf '%s'"$2"
  exit 0
fi
echo "stub gh: unexpected args: \$*" >&2
exit 1
STUB
  chmod +x "$W/gh"
}

echo "-- 1. no open PR or issue matches: clear to proceed"
mkstub '' ''
out="$(CROSS_REPO_DUPE_CHECK_GH_BIN="$W/gh" bash "$C" hf7y/scheduler "route-deliveries" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "no matches exits 0" || bad "exited $rc, want 0: $out"
grep -qi 'clean' <<<"$out" && ok "reports clean" || bad "did not report clean: $out"

echo "-- 2. an open issue already names the same fix: exit 1, named"
mkstub '' '  #606 Standing rule 5 sends agents to write in another repo -- https://github.com/hf7y/scheduler/issues/606
'
out="$(CROSS_REPO_DUPE_CHECK_GH_BIN="$W/gh" bash "$C" hf7y/scheduler "route-deliveries" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "an existing issue match exits 1" || bad "exited $rc, want 1: $out"
grep -q '#606' <<<"$out" && ok "the matching issue is named in the output" || bad "issue #606 missing from output: $out"

echo "-- 3. an open PR already carries the fix: exit 1, named"
mkstub '  #599 fix tab-IFS field collapse -- https://github.com/hf7y/scheduler/pull/599
' ''
out="$(CROSS_REPO_DUPE_CHECK_GH_BIN="$W/gh" bash "$C" hf7y/scheduler "route-deliveries" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "an existing PR match exits 1" || bad "exited $rc, want 1: $out"
grep -q '#599' <<<"$out" && ok "the matching PR is named in the output" || bad "PR #599 missing from output: $out"

echo "-- 4. repo must be owner/name"
out="$(bash "$C" notaslash "term" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "a bare repo name without owner/ is refused" || bad "exited $rc, want 2: $out"

echo "-- 5. needs at least one search term"
out="$(bash "$C" hf7y/scheduler 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "no search term is refused" || bad "exited $rc, want 2: $out"

echo "-- 6. a broken gh call is BLIND (exit 2), not silently clean"
cat > "$W/gh-fail" <<'STUB'
#!/usr/bin/env bash
echo "network unreachable" >&2
exit 1
STUB
chmod +x "$W/gh-fail"
out="$(CROSS_REPO_DUPE_CHECK_GH_BIN="$W/gh-fail" bash "$C" hf7y/scheduler "term" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "a failed gh call exits 2 (BLIND), not 0 (clean)" || bad "exited $rc, want 2: $out"

printf '\ncross-repo-dupe-check-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
