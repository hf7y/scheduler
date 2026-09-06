#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/route-deliveries.sh"

echo "route-deliveries-batch-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "route-deliveries-batch-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN" "$WORK/repo/bin" "$WORK/repo/schedule"
CALLS="$WORK/gh-calls.log"

cat > "$WORK/repo/schedule/proj.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/proj.git"
EOF

ISSUES_JSON="$WORK/issues.json"
cat > "$ISSUES_JSON" <<'EOF'
[
  {"number": 1, "labels": [{"name": "deferred"}],
   "body": "waiting.\n<!-- DEFERRED -->\n- hf7y/other#10\n<!-- /DEFERRED -->",
   "comments": []},
  {"number": 2, "labels": [{"name": "deferred"}],
   "body": "waiting.\n<!-- DEFERRED -->\n- hf7y/other#11\n<!-- /DEFERRED -->",
   "comments": [{"body": "<!-- routed-delivery:hf7y/other#11 -->"}]},
  {"number": 3, "labels": [{"name": "deferred"}],
   "body": "waiting.\n<!-- DEFERRED -->\n- hf7y/other#10\n- hf7y/wide#20\n<!-- /DEFERRED -->",
   "comments": []},
  {"number": 4, "labels": [],
   "body": "waiting.\n<!-- DEFERRED -->\n- hf7y/other#10\n<!-- /DEFERRED -->",
   "comments": [{"body": "<!-- routed-delivery:hf7y/other#10 -->"}]}
]
EOF

cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
set -u
if [ "\${FAKE_GH_MODE:-ok}" = "list-fail" ] && [ "\$1 \$2" = "issue list" ]; then
  echo "fake gh: simulated failure" >&2; exit 1
fi
if [ "\${FAKE_GH_MODE:-ok}" = "graphql-fail" ] && [ "\$1 \$2" = "api graphql" ]; then
  echo "fake gh: simulated failure" >&2; exit 1
fi
case "\$1 \$2" in
  "issue list")
    echo "issue-view-or-list-call" >> "$CALLS"
    cat "$ISSUES_JSON"
    ;;
  "issue view")
    echo "issue-view-call \$*" >> "$CALLS"
    echo "{}"
    ;;
  "api graphql")
    echo "graphql-call" >> "$CALLS"
    query="\$*"
    out="{\"data\":{"
    first=1
    while read -r frag; do
      [ -n "\$frag" ] || continue
      alias="\${frag%%:*}"
      num="\$(printf '%s' "\$frag" | grep -oE 'number: [0-9]+' | grep -oE '[0-9]+')"
      case "\$num" in
        10) state=CLOSED ;;
        11) state=OPEN ;;
        20) state=MERGED ;;
        *) continue ;;
      esac
      [ "\$first" -eq 1 ] || out+=","
      first=0
      out+="\"\$alias\":{\"issueOrPullRequest\":{\"__typename\":\"Issue\",\"state\":\"\$state\"}}"
    done < <(printf '%s' "\$query" | grep -oE 'r[0-9]+: repository\(owner: "[^"]+", name: "[^"]+"\) \{ issueOrPullRequest\(number: [0-9]+\)')
    out+="}}"
    printf '%s' "\$out"
    ;;
  "issue comment")
    echo "comment-call \$3 \$*" >> "$CALLS"
    ;;
  "issue edit")
    echo "edit-call \$3 \$*" >> "$CALLS"
    ;;
  *)
    echo "fake gh: unhandled: \$*" >&2; exit 1
    ;;
esac
EOF
chmod +x "$FAKEBIN/gh"

cp "$TARGET" "$WORK/repo/bin/route-deliveries.sh"
chmod +x "$WORK/repo/bin/route-deliveries.sh"

: > "$CALLS"
out="$(PATH="$FAKEBIN:$PATH" "$WORK/repo/bin/route-deliveries.sh" --check proj 2>&1)"
rc=$?

[ "$rc" -eq 0 ] && ok "exits 0 on a clean --check run" || bad "exit=$rc out=[$out]"

grep -q "^issue-view-call" "$CALLS" && bad "gh issue view was called at all -- batching regressed" \
  || ok "gh issue view is never called"

list_calls="$(grep -c "^issue-view-or-list-call" "$CALLS")"
[ "$list_calls" -eq 1 ] && ok "exactly one gh issue list call" || bad "expected 1 issue-list call, got $list_calls"

graphql_calls="$(grep -c "^graphql-call" "$CALLS")"
[ "$graphql_calls" -eq 1 ] && ok "exactly one gh api graphql call regardless of ref count" \
  || bad "expected 1 graphql call, got $graphql_calls"

echo "$out" | grep -q "WOULD ROUTE  hf7y/proj#1 <- hf7y/other#10 closed" \
  && ok "routes issue #1 off its closed dep" || bad "missing route for #1, out=[$out]"
echo "$out" | grep -q "WOULD ROUTE  hf7y/proj#3 <- hf7y/other#10 closed" \
  && ok "routes issue #3 off the SAME dep, resolved once and reused" || bad "missing route for #3 (dedup), out=[$out]"
echo "$out" | grep -q "WOULD ROUTE  hf7y/proj#3 <- hf7y/wide#20 closed" \
  && ok "routes issue #3's second, distinct ref (MERGED counts as delivered)" || bad "missing wide#20 route, out=[$out]"
echo "$out" | grep -q "hf7y/other#11" \
  && bad "issue #2 re-routed despite already carrying the routed-delivery marker" \
  || ok "issue #2's already-routed marker (read off the batched comments) suppresses a re-route"
echo "$out" | grep -q "proj#4" \
  && bad "issue #4 (no labels, already routed) re-routed -- the empty-labels field-collapse regression is back" \
  || ok "issue #4's marker suppresses a re-route even with an empty labels field (hf7y/wtul#128, #120 live bug)"

: > "$CALLS"
out="$(FAKE_GH_MODE=list-fail PATH="$FAKEBIN:$PATH" "$WORK/repo/bin/route-deliveries.sh" --check proj 2>&1)"; rc=$?
[ "$rc" -eq 6 ] && ok "BLIND (exit 6) when gh issue list fails" || bad "expected exit 6, got $rc"

: > "$CALLS"
out="$(FAKE_GH_MODE=graphql-fail PATH="$FAKEBIN:$PATH" "$WORK/repo/bin/route-deliveries.sh" --check proj 2>&1)"; rc=$?
[ "$rc" -eq 6 ] && ok "BLIND (exit 6) when the batched graphql call fails" || bad "expected exit 6, got $rc"

echo "route-deliveries-batch-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
