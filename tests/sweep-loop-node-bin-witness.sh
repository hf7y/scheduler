#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/../lib/sweep-loop-common.sh"
source "$HERE/lib/witness-common.sh"

echo "sweep-loop-node-bin-witness"

eval "$(sed -n '/^node_bin_dir() {/,/^}/p' "$ENGINE")"
if ! declare -F node_bin_dir >/dev/null; then
  bad "node_bin_dir could not be extracted from the engine -- the rest of this section tested nothing"
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

grep -q ': "\${NODE_BIN_DIR:=\$(node_bin_dir)}"' "$ENGINE" \
  && ok "an explicit NODE_BIN_DIR still overrides discovery, default routes through node_bin_dir()" \
  || bad "NODE_BIN_DIR default no longer routes through node_bin_dir()"

grep -q '\[ -d "\$NODE_BIN_DIR" \] && export PATH="\${NODE_BIN_DIR}:\$PATH"' "$ENGINE" \
  && ok "PATH is only prepended when NODE_BIN_DIR actually exists" \
  || bad "PATH prepend is still unconditional -- an absent dir would add a dead PATH entry"

if grep -q 'if ! command -v claude >/dev/null 2>&1; then' "$ENGINE"; then
  ok "the engine checks for \`claude\` on PATH after resolution"
else
  bad "the engine no longer checks for \`claude\` on PATH after resolution"
fi

grep -q 'CRITICAL: no \\`claude\\` on PATH after resolution' "$ENGINE" \
  && ok "a miss is logged as CRITICAL, not a quiet log() line" \
  || bad "a node-bin miss is no longer logged as CRITICAL"

grep -q 'notify -u critical "\$JOB_NAME: claude NOT FOUND"' "$ENGINE" \
  && ok "a miss pages via notify -u critical, same vocabulary as the auth-failure case" \
  || bad "a node-bin miss no longer pages via notify -u critical"

notify_line="$(grep -n '^notify() {' "$ENGINE" | head -1 | cut -d: -f1)"
path_line="$(grep -n '\[ -d "\$NODE_BIN_DIR" \] && export PATH=' "$ENGINE" | head -1 | cut -d: -f1)"
check_line="$(grep -n 'if ! command -v claude >/dev/null 2>&1; then' "$ENGINE" | head -1 | cut -d: -f1)"
if [ -n "$notify_line" ] && [ -n "$path_line" ] && [ -n "$check_line" ] \
   && [ "$check_line" -gt "$notify_line" ] && [ "$check_line" -gt "$path_line" ]; then
  ok "the loud check reads after both PATH resolution and notify() are defined"
else
  bad "the loud check's ordering relative to PATH resolution/notify() changed -- verify it still has both available (notify=$notify_line path=$path_line check=$check_line)"
fi

printf '\nsweep-loop-node-bin-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
