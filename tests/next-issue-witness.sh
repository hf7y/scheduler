#!/usr/bin/env bash
# Witness for bin/next-issue.sh (hf7y/scheduler#150 draft). Hermetic: a fake
# gh on PATH, never the live estate. See bin/next-issue.sh's own header for
# the reasoning this exercises.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/next-issue.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS: $*"; }
bad() { fail=$((fail+1)); echo "  FAIL: $*"; }

echo "next-issue-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "next-issue-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"

# Fixture queue:
#   #10  no deps                                        (oldest)
#   #11  "Depends on #10"        -- #10 is CLOSED        -> eligible
#   #12  "Depends on #99"        -- #99 is OPEN          -> SKIP
#   #13  "Depends on #999"       -- #999 unreadable       -> SKIP (blind, fails closed)
#   #14  "Blocked by #10"        -- alt phrasing, CLOSED  -> eligible
#   #15  "Depends on #15"        -- self-reference        -> eligible (ignored)
cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_GH_MODE:-ok}" = "listfail" ] && [ "$1 $2" = "issue list" ]; then
  exit 1
fi
if [ "$1 $2" = "issue list" ]; then
  cat <<'JSON'
[
  {"number": 10, "title": "root, no deps", "createdAt": "2026-08-01T00:00:00Z", "body": "no deps here"},
  {"number": 11, "title": "deps on closed #10", "createdAt": "2026-08-02T00:00:00Z", "body": "Depends on #10"},
  {"number": 12, "title": "deps on open #99", "createdAt": "2026-08-03T00:00:00Z", "body": "Depends on #99"},
  {"number": 13, "title": "deps on unreadable #999", "createdAt": "2026-08-04T00:00:00Z", "body": "Depends on #999"},
  {"number": 14, "title": "alt phrasing, closed", "createdAt": "2026-08-05T00:00:00Z", "body": "Blocked by #10"},
  {"number": 15, "title": "self-referential dep", "createdAt": "2026-08-06T00:00:00Z", "body": "Depends on #15"}
]
JSON
  exit 0
fi
if [ "$1 $2" = "issue view" ]; then
  case "$3" in
    10) echo "CLOSED"; exit 0 ;;
    99) echo "OPEN"; exit 0 ;;
    999) exit 1 ;;
    *) exit 1 ;;
  esac
fi
echo "fake gh: unsupported args: $*" >&2
exit 2
EOF
chmod +x "$FAKEBIN/gh"

export PATH="$FAKEBIN:$PATH"

# --- case 1: usage/help ------------------------------------------------------
out="$("$TARGET" --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "^usage:" <<<"$out"; then
  ok "--help exits 0 and prints usage"
else
  bad "--help: rc=$rc out=$out"
fi

# --- case 2: no repo named -> usage error -----------------------------------
"$TARGET" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "no repo argument -> exit 2" || bad "no repo argument -> rc=$rc, want 2"

# --- case 3: unknown flag -> usage error ------------------------------------
"$TARGET" --nope owner/repo >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "unknown flag -> exit 2" || bad "unknown flag -> rc=$rc, want 2"

# --- case 4: ordering + dependency gating -----------------------------------
out="$(FAKE_GH_MODE=ok "$TARGET" owner/repo --limit 10 2>/tmp/next-issue-witness-stderr.$$)"
stderr="$(cat /tmp/next-issue-witness-stderr.$$)"; rm -f /tmp/next-issue-witness-stderr.$$
nums="$(grep -oE '^#[0-9]+' <<<"$out" | tr -d '#')"
want="10
11
14
15"
if [ "$nums" = "$want" ]; then
  ok "eligible issues printed oldest-first, exactly {10,11,14,15}"
else
  bad "eligible set/order: got [$nums] want [$(tr '\n' ',' <<<"$want")]"
fi

if grep -q "SKIP  #12  waiting on #99 (open)" <<<"$stderr"; then
  ok "#12 skipped, names the open blocker #99"
else
  bad "#12 skip line missing or wrong: [$stderr]"
fi

if grep -q "SKIP  #13  waiting on #999 (blind)" <<<"$stderr"; then
  ok "#13 skipped, unreadable dependency treated as blind (fails closed, not open-by-default)"
else
  bad "#13 skip line missing or wrong: [$stderr]"
fi

# --- case 5: --limit is honoured ---------------------------------------------
out="$("$TARGET" owner/repo --limit 2 2>/dev/null)"
n="$(grep -cE '^#[0-9]+' <<<"$out")"
[ "$n" -eq 2 ] && ok "--limit 2 prints exactly 2 suggestions" || bad "--limit 2 printed $n"

# --- case 6: queue itself unreadable -> BLIND, exit 6 -----------------------
FAKE_GH_MODE=listfail "$TARGET" owner/repo >/tmp/next-issue-witness-out.$$ 2>&1; rc=$?
out="$(cat /tmp/next-issue-witness-out.$$)"; rm -f /tmp/next-issue-witness-out.$$
if [ "$rc" -eq 6 ] && grep -q "^BLIND:" <<<"$out"; then
  ok "unreadable queue -> exit 6, says BLIND"
else
  bad "unreadable queue: rc=$rc out=$out (want rc=6, BLIND: ...)"
fi

echo "next-issue-witness: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
