#!/usr/bin/env bash
# Witness: no surviving path in this repo writes a `.idea` file -- the channel
# `scheduler -i realisateur` fed. Why it went, and what: hf7y/scheduler#376.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

mkdir -p "$TMP/root/schedule" "$TMP/realisateur-repo" "$TMP/bin"
ln -s "$ROOT/bin" "$TMP/root/bin"
ln -s "$ROOT/lib" "$TMP/root/lib"
printf 'realisateur|1|3\n' > "$TMP/root/schedule/_paced.conf"
{
  echo "PROJECT_REPO_PATH=\"$TMP/realisateur-repo\""
  echo 'REPO_URL="https://github.com/hf7y/realisateur.git"'
} > "$TMP/root/schedule/realisateur.conf"

cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  auth|label) exit 0 ;;
  issue)
    case "$2" in
      create) echo "https://github.com/hf7y/realisateur/issues/999"; exit 0 ;;
      list) exit 0 ;;
    esac ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gh"

idea_files() { find "$TMP" -name '*.idea' 2>/dev/null; }

run_sched() {
  ( cd "$TMP" && PATH="$TMP/bin:$PATH" SCHED_ROOT="$TMP/root" HOME="$TMP" \
      "$ROOT/bin/scheduler" "$@" )
}

echo "== 1. \`scheduler idea realisateur \"text\"\` (was bin/scheduler:1235)"
out="$(run_sched idea realisateur "a note that used to become a file" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0"; else bad "exited $rc: $out"; fi
found="$(idea_files)"
if [ -z "$found" ]; then ok "wrote no .idea file"; else bad "wrote: $found"; fi
if printf '%s' "$out" | grep -q "filed as a GitHub issue on hf7y/realisateur"; then
  ok "filed a GitHub issue on hf7y/realisateur instead"
else
  bad "did not report filing an issue: $out"
fi
if printf '%s' "$out" | grep -qi "dropped:\|inbox convention"; then
  bad "still advertises the file inbox: $out"
else
  ok "stdout does not mention a dropped file"
fi

echo "== 2. \`scheduler -i realisateur\` -- the form usage-paced-runner.sh calls"
out="$(run_sched -i realisateur "PULL FROZEN on monkey as realisateur: has not pulled for 3 consecutive dispatcher ticks" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0 (the runner branches on exactly this)"; else bad "exited $rc: $out"; fi
found="$(idea_files)"
if [ -z "$found" ]; then ok "wrote no .idea file"; else bad "wrote: $found"; fi

echo "== 3. \`scheduler weight realisateur 5\` (was bin/scheduler:1883)"
out="$(run_sched weight realisateur 5 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0"; else bad "exited $rc: $out"; fi
found="$(idea_files)"
if [ -z "$found" ]; then ok "wrote no .idea file"; else bad "wrote: $found"; fi
if grep -q '^realisateur|1|5|' "$TMP/root/schedule/_paced.conf"; then
  ok "still edits the rotation file (5 written)"
else
  bad "weight edit lost: $(cat "$TMP/root/schedule/_paced.conf")"
fi
if printf '%s' "$out" | grep -q "flagged for realisateur"; then
  bad "still announces a flag file: $out"
else
  ok "does not announce a flag file"
fi

echo "== 4. source: nothing in bin/ or lib/ writes a .idea path"
writers="$(grep -rnE '(>|>>)[[:space:]]*"?[^"]*\.idea|\.idea"[[:space:]]*$|=[^=]*\.idea' \
             "$ROOT/bin" "$ROOT/lib" 2>/dev/null | grep -v '^\s*#' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
if [ -z "$writers" ]; then
  ok "no .idea assignment or redirection in bin/ or lib/"
else
  bad "a .idea writer is back:"$'\n'"$writers"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
