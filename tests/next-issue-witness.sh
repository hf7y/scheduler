#!/usr/bin/env bash
# Witness for bin/next-issue.sh (#150, adopted in #177). Hermetic: a fake gh
# on PATH, never the live estate; that script's header carries the reasoning.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/next-issue.sh"

echo "next-issue-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "next-issue-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"

# Fixture, eligible unless noted: #10 no deps (oldest), #11 dep CLOSED, #12 dep
# OPEN -> SKIP, #13 dep unreadable -> SKIP (blind), #14 alt "Blocked by", #15
# self-ref (ignored), #16 assigned -> SKIP (#663), #17 assignees: [] is no claim.
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
  {"number": 15, "title": "self-referential dep", "createdAt": "2026-08-06T00:00:00Z", "body": "Depends on #15"},
  {"number": 16, "title": "claimed by a human", "createdAt": "2026-08-07T00:00:00Z", "body": "no deps here", "assignees": [{"login": "hf7y"}]},
  {"number": 17, "title": "explicitly unassigned", "createdAt": "2026-08-08T00:00:00Z", "body": "no deps here", "assignees": []},
  {"number": 18, "title": "cross-repo dep, open", "createdAt": "2026-08-09T00:00:00Z", "body": "Depends on hf7y/other#40"},
  {"number": 19, "title": "unparseable dep phrase", "createdAt": "2026-08-10T00:00:00Z", "body": "Depends on the container landing"}
]
JSON
  exit 0
fi
if [ "$1 $2" = "issue view" ]; then
  case "$3" in
    10) echo "CLOSED"; exit 0 ;;
    99) echo "OPEN"; exit 0 ;;
    40) echo "OPEN"; exit 0 ;;
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
15
17"
if [ "$nums" = "$want" ]; then
  ok "eligible issues printed oldest-first, exactly {10,11,14,15,17}"
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

if grep -q "SKIP  #18  waiting on hf7y/other#40 (open)" <<<"$stderr"; then
  ok "#18 skipped, cross-repo owner/repo#N dependency parsed and resolved"
else
  bad "#18 skip line missing or wrong: [$stderr]"
fi

if grep -q 'SKIP  #19  waiting on unparsed dependency text: "Depends on the container landing"' <<<"$stderr"; then
  ok "#19 skipped, unparseable dependency phrase refused loudly instead of passing silently"
else
  bad "#19 skip line missing or wrong: [$stderr]"
fi

# --- case 4b: a claimed issue is skipped; absent/empty assignees are not (#663) ---
if grep -q "SKIP  #16  claimed by hf7y" <<<"$stderr"; then
  ok "#16 skipped, names who claimed it"
else
  bad "#16 claim-skip line missing or wrong: [$stderr]"
fi

# Absent (#10-15) and empty (#17) both mean "nobody claimed this", never
# "unreadable" -- inverting that drops every legacy issue out at once.
if grep -qE '^#17\b' <<<"$out" && ! grep -q "SKIP  #10" <<<"$stderr"; then
  ok "missing and empty assignee lists both read as unclaimed"
else
  bad "absent/empty assignees did not read as unclaimed: out=[$out] stderr=[$stderr]"
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

echo "next-issue-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
