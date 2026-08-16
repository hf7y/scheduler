#!/usr/bin/env bash
# Witness for `scheduler -i --receipt <project> "text"` (hf7y/scheduler#41).
#
# What this fixes: every `-i` call opened its own GitHub issue, so a run
# that files N receipts (records of something that already happened, with
# no decision in them) buried real asks under N issues nobody has to close
# but everybody has to scroll past. `--receipt` comments on ONE open
# `receipts`-labelled issue per project instead -- opens it on the first
# receipt, comments on it thereafter.
#
# No real `gh`/network: a stub on PATH logs every invocation and answers
# `auth status`/`label create` as success; `issue list` is driven by a
# scratch STATE file so the same stub can answer "no open receipts issue
# yet" for the first call and "here's the one you just opened" for the
# second, exactly like the real API would after a real create.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

mkdir -p "$TMP/root/schedule" "$TMP/target-repo"
ln -s "$ROOT/bin" "$TMP/root/bin"
ln -s "$ROOT/lib" "$TMP/root/lib"
printf 'scheduler|1|3\n' > "$TMP/root/schedule/_paced.conf"
{
  echo "PROJECT_REPO_PATH=\"$TMP/target-repo\""
  echo 'REPO_URL="git@github.com:hf7y/targetproj.git"'
} > "$TMP/root/schedule/targetproj.conf"

GHLOG="$TMP/gh-calls.log"
STATE="$TMP/existing-issue-url"   # empty = no open receipts issue yet
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GHLOG"
case "\$1" in
  auth) exit 0 ;;
  label) exit 0 ;;
  issue)
    case "\$2" in
      list)
        cat "$STATE" 2>/dev/null || true
        exit 0 ;;
      create)
        echo "https://github.com/hf7y/targetproj/issues/999" | tee "$STATE"
        exit 0 ;;
      comment)
        exit 0 ;;
    esac
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gh"

run_receipt() {  # $1 = text
  ( cd "$TMP" && PATH="$TMP/bin:$PATH" SCHED_ROOT="$TMP/root" \
      "$ROOT/bin/scheduler" -i --receipt targetproj "$1" )
}

echo "== 1. first receipt: no open receipts issue yet -> opens one"
: > "$GHLOG"; : > "$STATE"
out="$(run_receipt "first thing happened" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0"; else bad "exited $rc: $out"; fi
if grep -q -- "issue create --repo hf7y/targetproj --title Receipts --label receipts --label from:zach" "$GHLOG"; then
  ok "opens a new Receipts issue labelled receipts + from:zach"
else
  bad "expected issue create call not found: $(grep '^issue create' "$GHLOG" || true)"
fi
if printf '%s' "$out" | grep -q "opened a new rolling receipts issue"; then
  ok "stdout reports a fresh issue was opened"
else
  bad "stdout did not report a fresh open: $out"
fi
if ! grep -q "^issue comment" "$GHLOG"; then
  ok "no comment call on the first receipt"
else
  bad "unexpectedly commented on the first receipt: $(cat "$GHLOG")"
fi

echo "== 2. second receipt: an open receipts issue exists -> comments, no new issue"
: > "$GHLOG"
out="$(run_receipt "second thing happened" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0"; else bad "exited $rc: $out"; fi
if grep -q "issue comment https://github.com/hf7y/targetproj/issues/999 --repo hf7y/targetproj" "$GHLOG"; then
  ok "comments on the existing open receipts issue"
else
  bad "expected issue comment call not found: $(cat "$GHLOG")"
fi
if grep -q "^issue create" "$GHLOG"; then
  bad "opened a SECOND issue instead of commenting: $(cat "$GHLOG")"
else
  ok "did not open a second issue"
fi
if printf '%s' "$out" | grep -q "receipted as a comment"; then
  ok "stdout reports the comment"
else
  bad "stdout did not report the comment: $out"
fi

echo "== 3. bare '--receipt' with no project/text: usage, not a crash"
out="$( ( cd "$TMP" && PATH="$TMP/bin:$PATH" SCHED_ROOT="$TMP/root" \
    "$ROOT/bin/scheduler" -i --receipt 2>&1 ) )"; rc=$?
if [ "$rc" -ne 0 ]; then ok "non-zero exit on missing project"; else bad "exited 0 with no project given"; fi
if printf '%s' "$out" | grep -q "usage: scheduler idea --receipt"; then
  ok "prints usage"
else
  bad "no usage message: $out"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
