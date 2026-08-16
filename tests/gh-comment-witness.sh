#!/usr/bin/env bash
# Witness for lib/provenance.sh + bin/gh-comment.sh (hf7y/scheduler#172).
# Hermetic: a fake gh on PATH, never the live estate.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/gh-comment.sh"

echo "gh-comment-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "gh-comment-witness: 0 passed, 1 failed"
  exit 1
fi

# --- lib/provenance.sh, sourced directly -----------------------------------
# shellcheck source=../lib/provenance.sh
. "$PWD/lib/provenance.sh"

if provenance_is_stamped "hello

<!-- agent: scheduler/job 2026-08-14T00:00:00Z -->"; then
  ok "is_stamped: true on a trailing stamp"
else
  bad "is_stamped: should be true on a trailing stamp"
fi

if provenance_is_stamped "plain text, no stamp"; then
  bad "is_stamped: should be false with no stamp"
else
  ok "is_stamped: false with no stamp"
fi

if provenance_is_stamped "<!-- agent: scheduler/job 2026-08-14T00:00:00Z -->

more text after the stamp"; then
  bad "is_stamped: a stamp quoted mid-body must not count"
else
  ok "is_stamped: a stamp quoted mid-body does not count"
fi

got="$(provenance_format_stamp scheduler mytask 2026-08-14T01:02:03Z)"
want="<!-- agent: scheduler/mytask 2026-08-14T01:02:03Z -->"
[ "$got" = "$want" ] && ok "format_stamp: exact format" || bad "format_stamp: got [$got] want [$want]"

got="$(provenance_stamp_body "hi there" scheduler mytask 2026-08-14T01:02:03Z)"
want="hi there

<!-- agent: scheduler/mytask 2026-08-14T01:02:03Z -->"
[ "$got" = "$want" ] && ok "stamp_body: appended as trailing paragraph" || bad "stamp_body: got [$got] want [$want]"
provenance_is_stamped "$got" && ok "stamp_body: round-trips through is_stamped" || bad "stamp_body: round-trip through is_stamped failed"

got="$(provenance_stamp_body "" scheduler mytask 2026-08-14T01:02:03Z)"
[ "$got" = "<!-- agent: scheduler/mytask 2026-08-14T01:02:03Z -->" ] && ok "stamp_body: empty body -> bare stamp" || bad "stamp_body: empty body got [$got]"

# --- bin/gh-comment.sh CLI ---------------------------------------------------
WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
CAPTURE="$WORK/captured-body"

cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\${FAKE_GH_MODE:-ok}" = "fail" ]; then
  echo "fake gh: simulated failure" >&2
  exit 1
fi
if [ "\$1 \$2" = "issue comment" ]; then
  shift 2
  num="\$1"; shift
  bodyfile=""
  while [ \$# -gt 0 ]; do
    case "\$1" in
      --repo) shift; repo="\$1" ;;
      --body-file) shift; bodyfile="\$1" ;;
    esac
    shift
  done
  cp "\$bodyfile" "$CAPTURE"
  echo "https://github.com/\$repo/issues/\$num#issuecomment-1"
  exit 0
fi
echo "fake gh: unsupported args: \$*" >&2
exit 2
EOF
chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH"

# case: usage/help
out="$("$TARGET" --help 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "^usage:" <<<"$out" && ok "--help exits 0 and prints usage" || bad "--help: rc=$rc out=$out"

# case: no issue number -> usage error
"$TARGET" --repo o/r --job j --body hi >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "no issue number -> exit 2" || bad "no issue number -> rc=$rc, want 2"

# case: missing --repo -> usage error
"$TARGET" 5 --job j --body hi >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "missing --repo -> exit 2" || bad "missing --repo -> rc=$rc, want 2"

# case: both --body and --body-file -> usage error
"$TARGET" 5 --repo o/r --job j --body hi --body-file /dev/null >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "--body and --body-file together -> exit 2" || bad "--body+--body-file -> rc=$rc, want 2"

# case: posts with a stamp appended, project defaulted from --repo
rm -f "$CAPTURE"
out="$("$TARGET" 172 --repo hf7y/scheduler --job issue-triage --body "closing this out" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -f "$CAPTURE" ]; then
  body="$(cat "$CAPTURE")"
  if grep -q "^closing this out$" "$CAPTURE" \
     && tail -n1 "$CAPTURE" | grep -qE '^<!-- agent: scheduler/issue-triage [0-9T:Z-]+ -->$'; then
    ok "posts body with a trailing stamp, project defaulted from --repo's slug"
  else
    bad "captured body missing text or malformed stamp: [$body]"
  fi
else
  bad "post: rc=$rc out=$out"
fi

# case: --project override wins over the --repo-derived default
rm -f "$CAPTURE"
"$TARGET" 172 --repo hf7y/scheduler --project scheduler --job issue-triage --body "hi" >/dev/null 2>&1
if tail -n1 "$CAPTURE" | grep -qE '^<!-- agent: scheduler/issue-triage '; then
  ok "--project overrides the --repo-derived default"
else
  bad "--project override not honoured: [$(tail -n1 "$CAPTURE" 2>/dev/null)]"
fi

# case: --body-file works and is read from disk
rm -f "$CAPTURE"
printf 'from a file\n' > "$WORK/body.txt"
"$TARGET" 172 --repo hf7y/scheduler --job issue-triage --body-file "$WORK/body.txt" >/dev/null 2>&1
grep -q "^from a file$" "$CAPTURE" 2>/dev/null && ok "--body-file reads body from disk" || bad "--body-file did not carry the file's content"

# case: gh failure -> exit 5, nothing swallowed
FAKE_GH_MODE=fail "$TARGET" 172 --repo hf7y/scheduler --job issue-triage --body hi >/tmp/gh-comment-witness-out.$$ 2>&1; rc=$?
out="$(cat /tmp/gh-comment-witness-out.$$)"; rm -f /tmp/gh-comment-witness-out.$$
[ "$rc" -eq 5 ] && grep -qi "failed" <<<"$out" && ok "gh failure -> exit 5, says FAILED" || bad "gh failure: rc=$rc out=$out"

echo "gh-comment-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
