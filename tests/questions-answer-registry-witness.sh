#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/witness-common.sh"
echo "questions-answer-registry-witness"

command -v jq >/dev/null 2>&1 || { echo "  FAIL: jq missing -- this witness cannot look, which is not a pass"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

FAKE_ROOT="$W/sched-root"
mkdir -p "$FAKE_ROOT/schedule"
ln -s "$ROOT/bin" "$FAKE_ROOT/bin"
ln -s "$ROOT/lib" "$FAKE_ROOT/lib"
: > "$FAKE_ROOT/schedule/_paced.conf"
cat > "$FAKE_ROOT/schedule/proj.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/proj.git"
ANSWER_CHANNEL=issues
EOF

FAKE_HOME="$W/home"; mkdir -p "$FAKE_HOME"
export ANSWER_REGISTRY_FILE="$W/registry.tsv"

FAKEBIN="$W/fakebin"; mkdir -p "$FAKEBIN"
GH_LOG="$W/gh-calls.log"; : > "$GH_LOG"
COMMENT_BODY="$W/comment-body.txt"
cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
set -u
echo "\$*" >> "$GH_LOG"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "label create") exit 0 ;;
  "issue list")
    cat <<'JSON'
[{"number": 42, "title": "Which bucket for staging uploads?", "body": "Need a default bucket.", "labels": [], "comments": []}]
JSON
    ;;
  "issue comment")
    cp "\${@: -1}" "$COMMENT_BODY"
    exit 0
    ;;
  "issue edit") exit 0 ;;
  *) echo "fake gh: unhandled: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$FAKEBIN/gh"

cat > "$FAKEBIN/fake-editor.sh" <<'EOF'
#!/usr/bin/env bash
awk '
  /^<!-- scheduler:issue 42 -->$/ { in42=1 }
  /^<!-- scheduler:issue [0-9]+ -->$/ && !/issue 42 -->$/ { in42=0 }
  in42 && /^> $/ { print "> Use the staging-uploads bucket."; next }
  { print }
' "$1" > "$1.new" && mv "$1.new" "$1"
EOF
chmod +x "$FAKEBIN/fake-editor.sh"

out="$(PATH="$FAKEBIN:$PATH" HOME="$FAKE_HOME" SCHED_ROOT="$FAKE_ROOT" EDITOR="$FAKEBIN/fake-editor.sh" \
  "$ROOT/bin/scheduler" questions proj 2>&1)"; rc=$?

[ "$rc" -eq 0 ] && ok "scheduler questions proj exits 0" || bad "exit=$rc out=[$out]"
echo "$out" | grep -q "posted: #42 answered" && ok "reports the post" || bad "missing post confirmation, out=[$out]"
grep -q "^issue comment 42" "$GH_LOG" && ok "posted the comment to the real issue" || bad "no issue-comment call in [$GH_LOG]"
grep -qF "Use the staging-uploads bucket." "$COMMENT_BODY" 2>/dev/null \
  && ok "the posted comment carries Zach's typed answer" || bad "comment body missing the answer"

[ -s "$ANSWER_REGISTRY_FILE" ] && ok "the answer registry got a row" || bad "no row written to $ANSWER_REGISTRY_FILE"
row="$(grep -P '\tproj\t42\t' "$ANSWER_REGISTRY_FILE" 2>/dev/null || true)"
[ -n "$row" ] && ok "the row is keyed by this project and this issue" || bad "no proj/42 row found in [$(cat "$ANSWER_REGISTRY_FILE" 2>/dev/null)]"
echo "$row" | grep -q "relay" && ok "the row is marked 'relay' -- this IS the trusted \$EDITOR path" \
  || bad "row missing the relay marker: [$row]"
text_field="$(printf '%s' "$row" | cut -f5-)"
rendered="$(printf '%b' "$text_field")"
[ "$rendered" = "Use the staging-uploads bucket." ] \
  && ok "the row's text decodes back to exactly what was typed" \
  || bad "decoded text was [$rendered]"

export ANSWER_REGISTRY_FILE="$W/unwritable/registry.tsv"
mkdir -p "$W/unwritable"; chmod 000 "$W/unwritable"
out2="$(PATH="$FAKEBIN:$PATH" HOME="$FAKE_HOME" SCHED_ROOT="$FAKE_ROOT" EDITOR="$FAKEBIN/fake-editor.sh" \
  "$ROOT/bin/scheduler" questions proj 2>&1)"; rc2=$?
chmod 755 "$W/unwritable"
[ "$rc2" -eq 0 ] && ok "an unwritable registry does not fail the run (the comment still posted)" \
  || bad "exit=$rc2 -- a registry write failure must be best-effort, out=[$out2]"
echo "$out2" | grep -qi "registry write failed" && ok "and it says so" || bad "silent registry failure: out=[$out2]"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
