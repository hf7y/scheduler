#!/usr/bin/env bash
# questions-answer-registry-witness.sh -- `scheduler questions <proj>`'s relay
# posts a comment AND records a typed row (hf7y/scheduler#149 build item 2),
# so the answer is more than a tracker comment nobody is guaranteed to open.
#
# End-to-end against the REAL bin/scheduler and lib/answer-registry.sh, with
# only `gh` and $EDITOR faked -- a fixture SCHED_ROOT symlinks lib/ and bin/
# from this checkout so the wiring under test is the wiring that ships, not a
# restatement of it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/witness-common.sh"
echo "questions-answer-registry-witness"

command -v jq >/dev/null 2>&1 || { echo "  FAIL: jq missing -- this witness cannot look, which is not a pass"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# --- fixture SCHED_ROOT: real bin/ and lib/, a throwaway project conf -----
FAKE_ROOT="$W/sched-root"
mkdir -p "$FAKE_ROOT/schedule"
ln -s "$ROOT/bin" "$FAKE_ROOT/bin"
ln -s "$ROOT/lib" "$FAKE_ROOT/lib"
: > "$FAKE_ROOT/schedule/_paced.conf"   # resolve_paced_conf just needs it to exist
cat > "$FAKE_ROOT/schedule/proj.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/proj.git"
ANSWER_CHANNEL=issues
EOF

# --- fake HOME, so mark_seen / seen.tsv / ANSWER_REGISTRY_FILE stay local -
FAKE_HOME="$W/home"; mkdir -p "$FAKE_HOME"
export ANSWER_REGISTRY_FILE="$W/registry.tsv"

# --- fake gh -- list one open question issue, accept the comment/label/labels
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
    # \$3 is the issue number; the --body-file path is the last arg.
    cp "\${@: -1}" "$COMMENT_BODY"
    exit 0
    ;;
  "issue edit") exit 0 ;;
  *) echo "fake gh: unhandled: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$FAKEBIN/gh"

# --- fake $EDITOR -- fills issue 42's blank "> " answer slot -------------
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

# --- the load-bearing assertion: a typed row landed, not just a comment ---
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

# --- a registry write failure must not turn a posted answer into a FAILED one
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
