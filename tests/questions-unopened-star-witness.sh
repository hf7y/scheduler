#!/usr/bin/env bash
# Witness for #461: questions_unopened()'s `*` stat-ed the questions/ mirror
# #244 deleted, so it always read qmtime=0 and could never fire. Now takes
# the changed-at epoch as $3 (issues_counts()'s new 3rd field) instead.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHED="$ROOT/bin/scheduler"
[ -f "$SCHED" ] || { echo "script under test not found: $SCHED"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

command -v jq >/dev/null 2>&1 || { echo "  FAIL: jq missing -- this witness cannot look, which is not a pass"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Extracted, not sourced whole (would run bin/scheduler's dispatch case).
for fn in conf_field gh_repo_slug issues_counts questions_unopened get_seen mark_seen; do
  sed -n "/^${fn}() {/,/^}/p" "$SCHED" >> "$TMP/fns.sh"
done
[ -s "$TMP/fns.sh" ] || { echo "could not extract functions from $SCHED"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fns.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/provenance.sh"

HOME="$TMP/home"; mkdir -p "$HOME"
SEEN_FILE="$HOME/.local/share/scheduler-glance/seen.tsv"
XDG_CACHE_HOME="$TMP/cache"

SCHED_ROOT="$TMP/root"; mkdir -p "$SCHED_ROOT/schedule"
printf 'PROJECT="witnessproj"\nREPO_URL="git@github.com:hf7y/witnessproj.git"\n' \
  > "$SCHED_ROOT/schedule/witnessproj.conf"

# Fake `gh` on PATH -- hermetic (same approach as tests/gh-comment-witness.sh).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "issue list --repo hf7y/witnessproj --label question --state all --limit 200 --json number,state,labels,comments,updatedAt")
    cat "$FAKE_GH_ISSUES"
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
FAKE
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"

FAKE_GH_ISSUES="$TMP/issues.json"
cat > "$FAKE_GH_ISSUES" <<'JSON'
[
  {"number": 1, "state": "OPEN", "labels": [], "comments": [], "updatedAt": "2026-08-20T00:00:00Z"},
  {"number": 2, "state": "OPEN", "labels": [], "comments": [], "updatedAt": "2026-09-01T10:00:00Z"}
]
JSON
export FAKE_GH_ISSUES

echo "== issues_counts emits a real third field, not the file-mtime stub"
counts="$(issues_counts witnessproj)"
read -r qu qa qchanged <<<"$counts"
[ "$qu" = "2" ] && ok "2 unanswered counted" || bad "expected 2 unanswered, got '$qu' (counts='$counts')"
[ "$qchanged" = "1788256800" ] \
  && ok "third field is the newest unanswered issue's updatedAt as an epoch (2026-09-01T10:00:00Z)" \
  || bad "expected 1788256800, got '$qchanged' (counts='$counts')"

echo "== questions_unopened: never-seen project stars"
if questions_unopened witnessproj "$qu" "$qchanged"; then
  ok "unstarred project with real unanswered questions and no seen record stars"
else
  bad "should have starred -- never seen, qu=$qu qchanged=$qchanged"
fi

echo "== questions_unopened: seen AFTER the newest change does not star"
mark_seen witnessproj "$(( qchanged + 1 ))"
if questions_unopened witnessproj "$qu" "$qchanged"; then
  bad "starred even though it was seen after the newest change"
else
  ok "seen after the newest change -- no star"
fi

echo "== questions_unopened: a later comment re-stars"
mark_seen witnessproj "$(( qchanged - 1 ))"
if questions_unopened witnessproj "$qu" "$qchanged"; then
  ok "seen before the newest change -- stars again"
else
  bad "should have starred -- seen before the newest change"
fi

echo "== questions_unopened: zero unanswered never stars, whatever the timestamp"
if questions_unopened witnessproj 0 "$qchanged"; then
  bad "starred a project with zero unanswered questions"
else
  ok "zero unanswered -- no star, regardless of the changed-at timestamp"
fi

echo "== the retired \$SCHED_ROOT/questions/ stat must not come back"
if sed -n '/^questions_unopened() {/,/^}/p' "$SCHED" | grep -q 'SCHED_ROOT/questions'; then
  bad "questions_unopened still stats the retired \$SCHED_ROOT/questions/ path (#244)"
else
  ok "questions_unopened no longer reaches into the retired questions/ mirror"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
