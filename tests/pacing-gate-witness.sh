#!/usr/bin/env bash
set -uo pipefail  # scheduler pacing's live-gate ladder (#727): $USAGE_GATE, then ~/.local/bin, then $SCHED_ROOT/bin

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHED="$ROOT/bin/scheduler"
[ -f "$SCHED" ] || { echo "script under test not found: $SCHED"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

FIXROOT="$TMP/fixroot"  # real lib/ (safe, functions only); bin/ we control so the gate under test is a deterministic stub
mkdir -p "$FIXROOT/bin" "$FIXROOT/schedule"
ln -s "$ROOT/lib" "$FIXROOT/lib"
: > "$FIXROOT/bin/usage-paced-runner.sh"  # the repo-unique marker bin/scheduler checks for
printf 'witnessproj|1|1\n' > "$FIXROOT/schedule/_paced.conf"  # else the front door refuses before dispatch

stub_gate() {  # <path> <label>
  cat > "$1" <<STUB
#!/usr/bin/env bash
echo "verdict=STUB label=$2"
STUB
  chmod +x "$1"
}

run_sched() {  # HOME must be set by the caller first
  ( SCHED_ROOT="$FIXROOT" EDITOR=true "$SCHED" pacing "$@" 2>&1 )
}

echo "== 1. \$HOME/.local/bin/usage-gate.sh absent, \$SCHED_ROOT/bin/usage-gate.sh present -> falls back to it"
rm -f "$FIXROOT/bin/usage-gate.sh"
stub_gate "$FIXROOT/bin/usage-gate.sh" sched-root
HOME="$TMP/home1"; mkdir -p "$HOME"
unset USAGE_GATE
out="$(HOME="$HOME" run_sched)"
if grep -qF "resolved: $FIXROOT/bin/usage-gate.sh" <<<"$out"; then
  ok "header names the resolved \$SCHED_ROOT/bin/usage-gate.sh path"
else
  bad "header did not name the fallback path: $out"
fi
grep -q "label=sched-root" <<<"$out" \
  && ok "ran the \$SCHED_ROOT copy, not a phantom" \
  || bad "did not run the resolved gate: $out"
grep -q "not deployed" <<<"$out" \
  && bad "still claims not deployed while a gate is live" \
  || ok "no longer claims not deployed"

echo "== 2. \$USAGE_GATE override wins even though \$SCHED_ROOT/bin/usage-gate.sh also exists"
GATE2="$TMP/override-gate.sh"; stub_gate "$GATE2" override
HOME="$TMP/home2"; mkdir -p "$HOME"
out="$(USAGE_GATE="$GATE2" HOME="$HOME" run_sched)"
grep -qF "resolved: $GATE2" <<<"$out" \
  && ok "an explicit \$USAGE_GATE override is honoured over the ladder" \
  || bad "override ignored: $out"

echo "== 3. none of the three exist -> not-deployed names every path tried"
rm -f "$FIXROOT/bin/usage-gate.sh"
HOME="$TMP/home3"; mkdir -p "$HOME"
unset USAGE_GATE
out="$(HOME="$HOME" run_sched)"
if grep -q "not deployed" <<<"$out" \
  && grep -qF "\$USAGE_GATE=<unset>" <<<"$out" \
  && grep -qF "$HOME/.local/bin/usage-gate.sh" <<<"$out" \
  && grep -qF "$FIXROOT/bin/usage-gate.sh" <<<"$out"; then
  ok "not-deployed message names all three tried paths"
else
  bad "not-deployed message is missing a tried path: $out"
fi

echo
echo "==== pacing-gate witness: $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
