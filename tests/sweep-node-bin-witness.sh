#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's node bin resolution -- hf7y/scheduler#366.
#
# THE DEFECT THIS PINS: a literal /home/zach/.nvm/.../v25.2.1/bin behind an
# UNCONDITIONAL `export PATH=...` -- no `[ -d ]` test at all, unlike
# bin/usage-paced-runner.sh's own copy of this problem (#282/#366). On any
# host without that exact directory the prepend did nothing AND SAID NOTHING,
# and this file's whole job is calling `claude -p` a few lines later, so the
# silence here is worse than the dispatcher's: section 3 reproduces it.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "sweep-node-bin-witness"

# --- 1. node_bin_dir: discovery, not assumption ----------------------------
eval "$(sed -n '/^node_bin_dir() {/,/^}/p' "$LIB")"
if ! declare -F node_bin_dir >/dev/null; then
  bad "node_bin_dir could not be extracted from $LIB -- the rest of this section tested nothing"
else
  fake="$(mktemp -d)"
  trap 'rm -rf "$fake"' EXIT

  got="$(HOME="$fake" node_bin_dir)"
  [ "$got" = /home/zach/.nvm/versions/node/v25.2.1/bin ] \
    && ok "no nvm under \$HOME falls back to the historical mandark path" \
    || bad "no-nvm fallback returned '$got'"

  mkdir -p "$fake/.nvm/versions/node/v22.9.0/bin"
  got="$(HOME="$fake" node_bin_dir)"
  [ "$got" = "$fake/.nvm/versions/node/v22.9.0/bin" ] \
    && ok "an nvm under \$HOME wins over the hardcoded home" \
    || bad "own-nvm resolution returned '$got'"

  mkdir -p "$fake/.nvm/versions/node/v9.11.2/bin" "$fake/.nvm/versions/node/v25.2.1/bin"
  got="$(HOME="$fake" node_bin_dir)"
  [ "$got" = "$fake/.nvm/versions/node/v25.2.1/bin" ] \
    && ok "the newest installed version wins (v25.2.1 over v9.11.2, not string order)" \
    || bad "version ordering returned '$got'"
fi

# --- 2. the knob still wins, and the prepend is now guarded ----------------
grep -q ': "\${NODE_BIN_DIR:=\$(node_bin_dir)}"' "$LIB" \
  && ok "an explicit NODE_BIN_DIR still overrides discovery" \
  || bad "NODE_BIN_DIR is no longer an override of the discovered value"
grep -q '\[ -d "\$NODE_BIN_DIR" \] && export PATH="\$NODE_BIN_DIR:\$PATH"' "$LIB" \
  && ok "the PATH prepend is guarded on the dir existing" \
  || bad "the PATH prepend is still unconditional"

# --- 3. A MISS IS LOUD, on both channels this file already uses -------------
# node_bin_miss_check() and notify() extracted together, same technique as
# tests/claude-failure-detail-witness.sh: sourcing the whole engine would
# require JOB_NAME/PROJECT_KEY/REPO_URL/PROMPT and would run a real job.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  sed -n '/^notify() {/,/^}/p' "$LIB"
  sed -n '/^node_bin_miss_check() {/,/^}/p' "$LIB"
} > "$TMP/fns.sh"
grep -q 'node_bin_miss_check' "$TMP/fns.sh" \
  || { echo "FAIL: could not extract notify()/node_bin_miss_check() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fns.sh"

LOG="$TMP/sweep.log"; JOB_NAME="witnessjob"
NODE_BIN_DIR="$TMP/no-such-node-bin"

if command -v claude >/dev/null 2>&1; then
  echo "  SKIP: a real \`claude\` is already on PATH here, so absence cannot be fabricated"
else
  : > "$LOG"
  node_bin_miss_check
  grep -q 'CRITICAL: no `claude` on PATH' "$LOG" \
    && ok "an unreachable claude is CRITICAL in the log, not silent" \
    || bad "no CRITICAL line after a miss: $(cat "$LOG")"
  grep -q 'NODE_BIN_DIR=.*ABSENT' "$LOG" \
    && ok "the line names the resolved dir and that it was absent" \
    || bad "the CRITICAL line does not say the dir was ABSENT: $(cat "$LOG")"

  # NOT VACUOUS: with a `claude` in NODE_BIN_DIR the check must stay quiet, or
  # the assertions above would pass on a check that fires unconditionally.
  mkdir -p "$TMP/nodebin"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/nodebin/claude"; chmod +x "$TMP/nodebin/claude"
  : > "$LOG"
  PATH="$TMP/nodebin:$PATH" NODE_BIN_DIR="$TMP/nodebin" node_bin_miss_check
  [ -s "$LOG" ] \
    && bad "a reachable claude still wrote to the log: $(cat "$LOG")" \
    || ok "a claude on PATH logs nothing (the check is not unconditional)"
fi

printf '\nsweep-node-bin-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
