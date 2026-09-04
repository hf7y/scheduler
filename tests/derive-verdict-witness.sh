#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$RUNNER" ] || { echo "runner not found: $RUNNER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "derive-verdict-witness"

BLOCK="$TMP/derive-verdict.sh"
# TWO functions: #541 moved the slug sed out; lift both or all tests test "".
awk '/^repo_slug_of\(\) \{/,/^\}/' "$RUNNER"            > "$BLOCK"
awk '/^derive_no_verdict_reason\(\) \{/,/^\}/' "$RUNNER" >> "$BLOCK"
grep -q 'repo_slug_of()' "$BLOCK" \
  || { echo "FAIL: no repo_slug_of() extracted -- derive cannot resolve a repo without it"; exit 1; }
grep -q 'derive_no_verdict_reason' "$BLOCK" \
  || { echo "FAIL: no derive_no_verdict_reason() extracted -- lift failed"; exit 1; }
grep -q 'DERIVED-CONTINUE' "$BLOCK" \
  || { echo "FAIL: the extracted block never spells DERIVED-CONTINUE"; exit 1; }
grep -q 'DERIVED-SILENT' "$BLOCK" \
  || { echo "FAIL: the extracted block never spells DERIVED-SILENT"; exit 1; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "fake gh $*" >> "$FAKE_GH_LOG"
jqexpr=""
prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && jqexpr="$a"
  prev="$a"
done
body() {
case "$FAKE_GH_MODE" in
  red-pr)
    cat <<'JSON'
[{"number": 42, "updatedAt": "2999-01-01T00:00:00Z", "statusCheckRollup": [{"conclusion": "FAILURE"}]}]
JSON
    ;;
  green-pr)
    cat <<'JSON'
[{"number": 43, "updatedAt": "2999-01-01T00:00:00Z", "statusCheckRollup": [{"conclusion": "SUCCESS"}]}]
JSON
    ;;
  old-red-pr)
    cat <<'JSON'
[{"number": 44, "updatedAt": "2000-01-01T00:00:00Z", "statusCheckRollup": [{"conclusion": "FAILURE"}]}]
JSON
    ;;
  none)
    echo '[]'
    ;;
  fail)
    exit 1
    ;;
esac
}
if [ -n "$jqexpr" ]; then
  body | jq -e "$jqexpr" 2>/dev/null
else
  body
fi
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

REPO_ROOT="$TMP/repo"
mkdir -p "$REPO_ROOT/schedule"
cat > "$REPO_ROOT/schedule/hasrepo.conf" <<'EOF'
PROJECT="hasrepo"
REPO_URL="https://github.com/hf7y/hasrepo.git"
EOF
cat > "$REPO_ROOT/schedule/norepo.conf" <<'EOF'
PROJECT="norepo"
EOF
export REPO_ROOT
FAKE_GH_LOG="$TMP/gh.log"
export FAKE_GH_LOG

SINCE=1798761600  # 2027-01-01, so 2999-dated fixture PRs read as "since this run"

run_derive() {  # $1=name $2=gh-mode
  FAKE_GH_MODE="$2" bash -c '
    REPO_ROOT="'"$REPO_ROOT"'"
    '"$(cat "$BLOCK")"'
    derive_no_verdict_reason "'"$1"'" "'"$SINCE"'"
  '
}

echo "== 1. an open PR this run touched, with a red check -> DERIVED-CONTINUE, names the PR"
: > "$FAKE_GH_LOG"
out="$(run_derive hasrepo red-pr)"
if grep -q '^DERIVED-CONTINUE' <<<"$out"; then ok "classified DERIVED-CONTINUE"
else bad "expected DERIVED-CONTINUE, got: $out"; fi
if grep -q '#42' <<<"$out"; then ok "names the PR number"
else bad "does not name the PR: $out"; fi
if [ -s "$FAKE_GH_LOG" ]; then ok "gh was actually consulted"
else bad "gh was never called"; fi

echo "== 2. an open PR with a green/pending check -> DERIVED-SILENT, not DERIVED-CONTINUE"
out="$(run_derive hasrepo green-pr)"
if grep -q '^DERIVED-SILENT' <<<"$out"; then ok "classified DERIVED-SILENT (no red check)"
else bad "expected DERIVED-SILENT, got: $out"; fi
if grep -q 'DERIVED-CONTINUE' <<<"$out"; then bad "must not also read as DERIVED-CONTINUE: $out"
else ok "does not claim CONTINUE"; fi

echo "== 3. a failing PR that predates this run -> DERIVED-SILENT (not this run's doing)"
out="$(run_derive hasrepo old-red-pr)"
if grep -q '^DERIVED-SILENT' <<<"$out"; then ok "an old failure is not attributed to this run"
else bad "expected DERIVED-SILENT for a pre-existing failure, got: $out"; fi

echo "== 4. no open PRs at all -> DERIVED-SILENT"
out="$(run_derive hasrepo none)"
if grep -q '^DERIVED-SILENT' <<<"$out"; then ok "classified DERIVED-SILENT"
else bad "expected DERIVED-SILENT, got: $out"; fi

echo "== 5. gh itself fails (rate-limited/unauthenticated) -> degrades to DERIVED-SILENT, not a crash"
out="$(run_derive hasrepo fail)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^DERIVED-SILENT' <<<"$out"; then ok "gh failure degrades to DERIVED-SILENT"
else bad "gh failure did not degrade cleanly: rc=$rc out=$out"; fi

echo "== 6. no REPO_URL in the project's conf -> DERIVED-SILENT, gh never called"
: > "$FAKE_GH_LOG"
out="$(run_derive norepo none)"
if grep -q '^DERIVED-SILENT' <<<"$out"; then ok "no REPO_URL -> DERIVED-SILENT"
else bad "expected DERIVED-SILENT, got: $out"; fi
if [ ! -s "$FAKE_GH_LOG" ]; then ok "gh was never invoked with nothing to ask it"
else bad "gh was called despite no REPO_URL: $(cat "$FAKE_GH_LOG")"; fi

echo "== 7. the two spellings never collide with a self-reported verdict's own vocabulary"
for word in DONE CONTINUE IMPOSSIBLE; do
  if grep -qx "$word" <<<"DERIVED-CONTINUE
DERIVED-SILENT"; then bad "DERIVED- output collides with the bare word '$word'"
  else ok "'DERIVED-*' does not read as bare '$word'"; fi
done

echo
echo "derive-verdict-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
