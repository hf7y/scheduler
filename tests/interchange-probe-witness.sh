#!/usr/bin/env bash
# Witness for bin/interchange-probe.sh. Hermetic: a fixture schedule/ and a
# fake gh on PATH, never the live estate.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SRC="$PWD/bin/interchange-probe.sh"

echo "interchange-probe-witness"

if [ ! -x "$SRC" ]; then
  echo "  FAIL: $SRC missing or not executable"
  echo "interchange-probe-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
CONF="$WORK/schedule"; mkdir -p "$CONF"
printf 'REPO_URL="https://github.com/hf7y/alpha.git"\n' > "$CONF/alpha.conf"
printf 'REPO_URL="https://github.com/hf7y/beta.git"\n'  > "$CONF/beta.conf"
printf '# not a project\n' > "$CONF/_tempo.conf"
export TEMPO_CONF_DIR="$CONF"

NOW="$(date +%s)"
RECENT="$(date -u -d "@$((NOW - 3600))" +%Y-%m-%dT%H:%M:%SZ)"
STALE="$(date -u -d "@$((NOW - 900000))" +%Y-%m-%dT%H:%M:%SZ)"

cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
[ "\${FAKE_GH_MODE:-ok}" = fail ] && exit 1
repo=""
for a in "\$@"; do case "\$prev" in --repo) repo="\$a" ;; esac; prev="\$a"; done
case "\$repo" in
  hf7y/alpha)
    cat <<'JSON'
[
 {"number":1,"state":"CLOSED","createdAt":"@STALE@","closedAt":"@RECENT@","url":"https://github.com/hf7y/alpha/issues/1","title":"cross-filed, closed in window","body":"found by beta#9"},
 {"number":2,"state":"CLOSED","createdAt":"@STALE@","closedAt":"@STALE@","url":"https://github.com/hf7y/alpha/issues/2","title":"cross-filed, closed before window","body":"see beta#4"},
 {"number":3,"state":"CLOSED","createdAt":"@STALE@","closedAt":"@RECENT@","url":"https://github.com/hf7y/alpha/issues/3","title":"self-reference only","body":"see alpha#1"},
 {"number":4,"state":"OPEN","createdAt":"@RECENT@","closedAt":null,"url":"https://github.com/hf7y/alpha/issues/4","title":"cross-filed, still open","body":"filed from hf7y/beta#7"}
]
JSON
    ;;
  hf7y/beta) echo '[]' ;;
  *) echo "fake gh: unknown repo \$repo" >&2; exit 2 ;;
esac
EOF
sed -i "s|@STALE@|$STALE|g; s|@RECENT@|$RECENT|g" "$FAKEBIN/gh"
chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH"

out="$("$SRC" --help 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^usage:' <<<"$out" && ok "--help exits 0 and prints usage" || bad "--help: rc=$rc"

"$SRC" --window-hours nope >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "non-numeric --window-hours -> exit 2" || bad "bad window -> rc=$rc, want 2"

out="$("$SRC" --window-hours 24 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'verdict=OK .*cross_closed=1 cross_open=1 repos=2' <<<"$out"; then
  ok "counts only cross-filed issues, only inside the window; _*.conf is not a project"
else
  bad "count case: rc=$rc out=$out"
fi
grep -q 'CLOSED  filed-by=beta .*alpha/issues/1' <<<"$out" \
  && ok "prints the cross-reference naming the filing repo" || bad "cross-reference row missing: $out"
grep -q 'alpha/issues/3' <<<"$out" && bad "a self-reference was counted as interchange" \
  || ok "a self-reference is not interchange"

out="$("$SRC" --window-hours 1 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'verdict=DOWN .*reason=no_cross_filed_issue_was_closed_in_window' <<<"$out"; then
  ok "no cross-filed close in window -> DOWN"
else
  bad "down case: rc=$rc out=$out"
fi

out="$(FAKE_GH_MODE=fail "$SRC" 2>&1)"; rc=$?
if [ "$rc" -eq 6 ] && grep -q 'verdict=BLIND' <<<"$out"; then
  ok "an unreadable tracker -> BLIND, exit 6, never DOWN and never OK"
else
  bad "blind case: rc=$rc out=$out"
fi

echo "interchange-probe-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
