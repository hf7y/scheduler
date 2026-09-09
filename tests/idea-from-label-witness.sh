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
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# The REAL gh, resolved BEFORE the fake one below shadows it on PATH. Case 3
# grades a composed body with it; it reads without writing, so nothing is filed.
REAL_GH="$(command -v gh 2>/dev/null || true)"

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

echo "== 3. the body cmd_idea composes is one gh-sign will ACCEPT"
# WHY (#732). The stub above answers `issue create` with a fake URL, so cases 1
# and 2 pass whether or not the body would survive the real write. It would not
# have: the gh-sign shim grades every body against lib/body-grammar.sh, and
# cmd_idea sent the note plus a footer -- no declaration, no ledgers. cmd_ask
# was migrated when that grammar landed and this path was missed, so every
# `scheduler -i` was refused for any caller whose `gh` resolves to the shim,
# and it took usage-paced-runner.sh's PULL FROZEN escalation down with it --
# `scheduler -i` is that escalation's first channel.
BODY_OUT="$TMP/idea-body.md"
rm -f "$BODY_OUT"
cat > "$TMP/bin/gh" <<'BODYSTUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GHLOG"
if [ "${1:-}" = issue ] && [ "${2:-}" = create ]; then
  prev=""
  for a in "$@"; do
    [ "$prev" = "--body-file" ] && cp "$a" "$BODY_OUT"
    prev="$a"
  done
  echo "https://github.com/hf7y/targetproj/issues/999"
fi
exit 0
BODYSTUB
chmod +x "$TMP/bin/gh"
: > "$GHLOG"
( cd "$TMP" && BODY_OUT="$BODY_OUT" GHLOG="$GHLOG" PATH="$TMP/bin:$PATH" \
    SCHED_ROOT="$TMP/root" "$ROOT/bin/scheduler" -i targetproj "a note from the witness" ) >/dev/null 2>&1
if [ -s "$BODY_OUT" ]; then
  ok "captured the body cmd_idea composes"
  case "$(head -1 "$BODY_OUT")" in
    DECISION:*|NO-DECISION:*) ok "line 1 declares a decision" ;;
    *) bad "line 1 declares nothing: $(head -c 60 "$BODY_OUT")" ;;
  esac
  for _b in DEFERRED DELIVERS; do
    if grep -qF "<!-- $_b -->" "$BODY_OUT" && grep -qF "<!-- /$_b -->" "$BODY_OUT"; then
      ok "body carries a complete $_b block"
    else bad "body has no complete <!-- $_b --> block"; fi
  done
  if grep -qF "a note from the witness" "$BODY_OUT"; then
    ok "the note itself survives -- the declaration did not displace the record"
  else bad "the note is gone from the body"; fi
  # The real grader when this host has one; never a substitute for the above.
  if [ -n "$REAL_GH" ] \
     && printf 'NO-DECISION: probe\n\n<!-- DEFERRED -->\n- none\n<!-- /DEFERRED -->\n\n<!-- DELIVERS -->\n- none\n<!-- /DELIVERS -->\n' > "$TMP/probe.md" \
     && "$REAL_GH" --check-body "$TMP/probe.md" 2>&1 | grep -qi 'well-formed'; then
    _v="$("$REAL_GH" --check-body "$BODY_OUT" 2>&1)"
    if printf '%s' "$_v" | grep -qi 'well-formed'; then
      ok "accepted by the real body-grammar.sh"
    else bad "REFUSED by the real body-grammar.sh -- $_v"; fi
  else
    echo "  (no --check-body grader on this host; structural assertions above still ran)"
  fi
else
  bad "cmd_idea wrote no body -- nothing to grade"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
