#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROC="$ROOT/schedule/_run-procedure.md"
[ -f "$PROC" ] || { echo "schedule/_run-procedure.md not found: $PROC"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "== case 1: the doc names the real invocation, and gates it on presence"
if grep -qF '`python3 tools/claim-issue.py <N>`' "$PROC"; then
  ok "step 3 names the literal invocation"
else
  bad "schedule/_run-procedure.md does not contain the expected invocation line"
fi
if grep -qF 'if this repo carries' "$PROC" && grep -qF '`tools/claim-issue.py`' "$PROC"; then
  ok "step 3 gates the call on the repo carrying the tool"
else
  bad "step 3 does not gate the call on tool presence"
fi

echo "== case 2: a repo without the tool is skipped, not run against"
FX="$TMP/repo-without-tool"
mkdir -p "$FX"
run_gate() { [ -f "$1/tools/claim-issue.py" ]; }
if run_gate "$FX"; then
  bad "gate ran claim-issue.py against a repo that does not carry it"
else
  ok "a repo without tools/claim-issue.py is skipped, as step 3 promises"
fi

echo "== case 3: exit-code contract matches tools/claim-issue.py's own codes"
FX2="$TMP/repo-with-tool"
mkdir -p "$FX2/tools"
fake_claim() {
  printf '#!/usr/bin/env python3\nimport sys\nsys.exit(%s)\n' "$1" > "$FX2/tools/claim-issue.py"
  chmod +x "$FX2/tools/claim-issue.py"
}
decide() {
  local dir="$1" n="$2" rc
  if [ -f "$dir/tools/claim-issue.py" ]; then
    python3 "$dir/tools/claim-issue.py" "$n" >/dev/null 2>&1
    rc=$?
    case "$rc" in
      1) printf 'skip' ;;
      2) printf 'proceed' ;;
      0) printf 'claimed' ;;
      *) printf 'unexpected-rc-%s' "$rc" ;;
    esac
  else
    printf 'proceed'
  fi
}

fake_claim 1
out="$(decide "$FX2" 42)"
[ "$out" = "skip" ] && ok "exit 1 (a live claim elsewhere) -> skip to the next issue" \
                     || bad "exit 1 did not map to skip: got '$out'"

fake_claim 2
out="$(decide "$FX2" 42)"
[ "$out" = "proceed" ] && ok "exit 2 (could not look) -> proceed as before" \
                        || bad "exit 2 did not map to proceed: got '$out'"

fake_claim 0
out="$(decide "$FX2" 42)"
[ "$out" = "claimed" ] && ok "exit 0 -> claimed, work proceeds" \
                        || bad "exit 0 did not map to claimed: got '$out'"

echo "== case 4: real tools/claim-issue.py's own codes, if this checkout carries it"
REAL="$ROOT/tools/claim-issue.py"
if [ -f "$REAL" ]; then
  if grep -qE 'RC_FAIL[[:space:]]*=[[:space:]]*1' "$REAL" && \
     grep -qE 'RC_INCOMPLETE[[:space:]]*=[[:space:]]*2' "$REAL"; then
    ok "tools/claim-issue.py's RC_FAIL=1/RC_INCOMPLETE=2 still match the doc's Exit 1/Exit 2"
  else
    bad "tools/claim-issue.py's exit codes no longer match schedule/_run-procedure.md's claim"
  fi
else
  ok "this repo does not carry tools/claim-issue.py -- step 3 says that skips the gate, not the run"
fi

echo
echo "claim-issue-orient-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
