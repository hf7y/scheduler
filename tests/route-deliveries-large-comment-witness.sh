#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/route-deliveries.sh"

echo "route-deliveries-large-comment-witness"

# hf7y/dcp-gate-site#34, observed live: a routed-delivery marker written
# early in a long comment thread stopped suppressing re-routes once the
# thread grew past a pipe buffer's worth of text, and the same issue got
# "is CLOSED" posted to it five times in one night. Root cause: `printf ... |
# grep -qF` under `set -o pipefail`. grep exits (and closes its read end) the
# instant it finds a match; if printf still has unwritten bytes queued for a
# reader that is gone, its next write() gets SIGPIPE (141), and pipefail
# promotes that into the pipeline's own exit status even though grep matched
# and exited 0. A short fixture comment thread never fills the pipe buffer
# before grep quits, so this never fired in the batch witness above -- it
# needs a comment thread too big to land in one write().

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "route-deliveries-large-comment-witness: 0 passed, 1 failed"
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

# The marker sits in the FIRST comment, followed by ~90KB of later, unrelated
# comment text -- comfortably past a 64KB pipe buffer -- so grep matches long
# before it has read to EOF and closes early on a printf still mid-write.
python3 - "$WORK/issues.json" <<'PY'
import json, sys
padding = "filler " * 13000  # ~90KB, well past a 64KB pipe buffer
issues = [{
    "number": 1,
    "labels": [{"name": "deferred"}],
    "body": "waiting.\n<!-- DEFERRED -->\n- hf7y/other#10\n<!-- /DEFERRED -->",
    "comments": [
        {"body": "<!-- routed-delivery:hf7y/other#10 -->"},
        {"body": padding},
    ],
}]
with open(sys.argv[1], "w") as f:
    json.dump(issues, f)
PY
ISSUES_JSON="$WORK/issues.json"

cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
set -u
case "\$1 \$2" in
  "issue list")
    echo "issue-list-call" >> "$CALLS"
    cat "$ISSUES_JSON"
    ;;
  "issue view")
    echo "issue-view-call \$*" >> "$CALLS"
    ;;
  "api graphql")
    echo "graphql-call" >> "$CALLS"
    echo '{"data":{"r0":{"issueOrPullRequest":{"__typename":"Issue","state":"CLOSED"}}}}'
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

[ "$rc" -eq 0 ] && ok "exits 0 on a --check run against a large comment thread" || bad "exit=$rc out=[$out]"
echo "$out" | grep -q "hf7y/other#10" \
  && bad "re-routed a dep whose marker is present but buried under 90KB of later comments" \
  || ok "the marker suppresses a re-route even ~90KB into the comment thread"
grep -q "^graphql-call" "$CALLS" \
  && bad "resolved the dep via graphql at all -- it was already marked routed, no lookup needed" \
  || ok "never calls graphql for an already-routed dep"

echo "route-deliveries-large-comment-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
