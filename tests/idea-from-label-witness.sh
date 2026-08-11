#!/usr/bin/env bash
# Witness for the `from:<calling-project>` label on `scheduler -i` (2026-08-10).
#
# What this fixes: `scheduler -i <target> "text"` files a GitHub issue on the
# TARGET project's repo, labelled `idea` -- but the CALLING project (who typed
# the note) was only ever embedded as free prose by the caller's own
# discipline, never captured as data. Every issue was untriage-able by source
# without reading the full body. `project_for_path` already resolves "which
# registered project owns this filesystem path" for the busy-marker
# machinery; cmd_idea now reuses it against $PWD to attach a second label,
# `from:<calling-project>`, or `from:zach` when $PWD is outside every
# registered checkout.
#
# No real `gh`/network: a stub on PATH logs every invocation and answers
# `auth status` and `label create` as success, `issue create` with a fake
# URL -- same shape as the rest of this repo (SCHED_ROOT pointed at a scratch
# registry, no clone of any target project required).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# ---- scratch registry: a "caller" project (has a repo checkout on disk,
# resolvable by project_for_path) and a "target" project (has REPO_URL, the
# repo the issue actually gets filed against). ------------------------------
mkdir -p "$TMP/root/schedule" "$TMP/caller-repo/some/nested/dir" "$TMP/target-repo"
ln -s "$ROOT/bin" "$TMP/root/bin"
ln -s "$ROOT/lib" "$TMP/root/lib"
printf 'scheduler|1|3\n' > "$TMP/root/schedule/_paced.conf"
{
  echo "PROJECT_REPO_PATH=\"$TMP/caller-repo\""
  echo 'REPO_URL="git@github.com:hf7y/callerproj.git"'
} > "$TMP/root/schedule/callerproj.conf"
{
  echo "PROJECT_REPO_PATH=\"$TMP/target-repo\""
  echo 'REPO_URL="git@github.com:hf7y/targetproj.git"'
} > "$TMP/root/schedule/targetproj.conf"

# ---- fake `gh`: logs every call, never touches the network. ---------------
mkdir -p "$TMP/bin"
GHLOG="$TMP/gh-calls.log"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GHLOG"
case "$1" in
  auth) exit 0 ;;
  label) exit 0 ;;
  issue)
    if [ "$2" = "create" ]; then
      echo "https://github.com/hf7y/targetproj/issues/999"
      exit 0
    fi
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gh"

run_idea() {  # $1 = cwd for the call
  ( cd "$1" && GHLOG="$GHLOG" PATH="$TMP/bin:$PATH" SCHED_ROOT="$TMP/root" \
      "$ROOT/bin/scheduler" -i targetproj "note from the witness" )
}

echo "== 1. called from inside a registered project's checkout: from:callerproj"
: > "$GHLOG"
out="$(run_idea "$TMP/caller-repo/some/nested/dir" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0"; else bad "exited $rc: $out"; fi
if grep -q -- "--label idea --label from:callerproj" "$GHLOG"; then
  ok "gh issue create carries both labels, idea and from:callerproj"
else
  bad "expected labels not found in gh issue create call: $(grep '^issue create' "$GHLOG" || true)"
fi
if grep -q "label create from:callerproj --repo hf7y/targetproj" "$GHLOG"; then
  ok "from:callerproj label created on the TARGET repo before filing"
else
  bad "from:callerproj was never created via ensure_gh_labels: $(cat "$GHLOG")"
fi
if printf '%s' "$out" | grep -q "labels: idea, from:callerproj"; then
  ok "stdout reports the labels filed"
else
  bad "stdout did not report labels: $out"
fi

echo "== 2. called from outside every registered checkout: from:zach"
: > "$GHLOG"
out="$(run_idea "$TMP" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0"; else bad "exited $rc: $out"; fi
if grep -q -- "--label idea --label from:zach" "$GHLOG"; then
  ok "gh issue create carries from:zach when \$PWD matches no registered project"
else
  bad "expected from:zach not found: $(grep '^issue create' "$GHLOG" || true)"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
