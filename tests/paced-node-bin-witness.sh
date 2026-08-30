#!/usr/bin/env bash
# paced-node-bin-witness.sh -- how usage-paced-runner.sh finds `claude`, and
# what it says when it cannot.
#
# THE DEFECT THIS PINS: a literal /home/zach/.nvm/.../v25.2.1/bin behind
# `[ -d ... ] && export PATH=...`, which on any host without that exact
# directory did nothing AND SAID NOTHING -- so a dispatcher that could not
# reach `claude` wrote a run.log byte-identical to one that could. The silence
# is the bug; section 3 reproduces it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/../bin/usage-paced-runner.sh"
source "$HERE/lib/witness-common.sh"

echo "paced-node-bin-witness"

# --- 1. node_bin_dir: discovery, not assumption ----------------------------
# Extracted and evaluated alone, the way paced-host-mode-witness.sh reads out
# acct_of_prog: sourcing the whole runner would run it.
eval "$(sed -n '/^node_bin_dir() {/,/^}/p' "$RUNNER")"
if ! declare -F node_bin_dir >/dev/null; then
  bad "node_bin_dir could not be extracted from the runner -- the rest of this section tested nothing"
else
  fake="$(mktemp -d)"
  trap 'rm -rf "$fake"' EXIT

  # No nvm at all (dexter, every monkey self-dev account): the old literal is
  # what is left -- and it must be LAST, not what was tried first.
  got="$(HOME="$fake" node_bin_dir)"
  [ "$got" = /home/zach/.nvm/versions/node/v25.2.1/bin ] \
    && ok "no nvm under \$HOME falls back to the historical mandark path" \
    || bad "no-nvm fallback returned '$got'"

  # This account's own nvm outranks the literal: /home/zach is not every
  # account's home.
  mkdir -p "$fake/.nvm/versions/node/v22.9.0/bin"
  got="$(HOME="$fake" node_bin_dir)"
  [ "$got" = "$fake/.nvm/versions/node/v22.9.0/bin" ] \
    && ok "an nvm under \$HOME wins over the hardcoded home" \
    || bad "own-nvm resolution returned '$got'"

  # NEWEST, by version order not string order -- v9 sorts after v22 lexically,
  # which is how a pin gets re-introduced by accident.
  mkdir -p "$fake/.nvm/versions/node/v9.11.2/bin" "$fake/.nvm/versions/node/v25.2.1/bin"
  got="$(HOME="$fake" node_bin_dir)"
  [ "$got" = "$fake/.nvm/versions/node/v25.2.1/bin" ] \
    && ok "the newest installed version wins (v25.2.1 over v9.11.2, not string order)" \
    || bad "version ordering returned '$got'"
fi

# --- 2. the knob still wins ------------------------------------------------
grep -q 'NODE_BIN_DIR="\${NODE_BIN_DIR:-\$(node_bin_dir)}"' "$RUNNER" \
  && ok "an explicit NODE_BIN_DIR still overrides discovery" \
  || bad "NODE_BIN_DIR is no longer an override of the discovered value"

# --- 3. A MISS IS LOUD ------------------------------------------------------
# The real dispatcher, in a sandbox with no `claude` anywhere. Hermetic: the
# copy sits outside a git checkout so the pull and schedule/-clean gates skip,
# PACED_CONF is explicit, and its one row names an unrunnable program -- the
# tick ends at "no runnable participant" without probing the gate.
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$fake" "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"
cp "$RUNNER" "$SANDBOX/bin/"
printf 'nobody|1|/nonexistent/scheduler-run nobody batch\n' > "$SANDBOX/paced.conf"

run_tick() {  # $1 = NODE_BIN_DIR to hand it; prints the resulting run.log
  rm -rf "$SANDBOX/home"; mkdir -p "$SANDBOX/home"
  env -i HOME="$SANDBOX/home" PATH=/usr/bin:/bin NODE_BIN_DIR="$1" \
    PACED_CONF="$SANDBOX/paced.conf" PACED_HOST=witnesshost \
    bash "$SANDBOX/bin/usage-paced-runner.sh" >/dev/null 2>&1
  cat "$SANDBOX/home/.local/share/scheduler-paced-runner/run.log" 2>/dev/null
}

if env -i PATH=/usr/bin:/bin bash -c 'command -v claude' >/dev/null 2>&1; then
  echo "  SKIP: \`claude\` is in /usr/bin or /bin here, so absence cannot be fabricated"
else
  missing_log="$(run_tick "$SANDBOX/no-such-node-bin")"
  grep -q 'NODE-BIN MISS' <<<"$missing_log" \
    && ok "an unreachable \`claude\` is REPORTED, not silently skipped" \
    || bad "an absent node dir still produces no line about it: ${missing_log:-<empty log>}"
  grep -q 'NODE-BIN MISS.*ABSENT' <<<"$missing_log" \
    && ok "the line names the directory it looked in and that it was absent" \
    || bad "the miss line does not say the resolved dir was absent: $missing_log"
  grep -q 'no runnable participant\|no enabled participants' <<<"$missing_log" \
    && ok "the tick still finishes -- a miss is loud, not fatal" \
    || bad "the tick did not reach its normal end after a miss: $missing_log"

  # NOT VACUOUS: with a `claude` in the node dir the line must be absent, or
  # the three above would pass on a runner that logged unconditionally.
  mkdir -p "$SANDBOX/nodebin"
  printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/nodebin/claude"; chmod +x "$SANDBOX/nodebin/claude"
  found_log="$(run_tick "$SANDBOX/nodebin")"
  grep -q 'NODE-BIN MISS' <<<"$found_log" \
    && bad "a reachable \`claude\` still logged a miss: $found_log" \
    || ok "a \`claude\` in NODE_BIN_DIR logs no miss (the check is not unconditional)"
fi

# --- 4. USAGE_GATE does not resolve through root's $HOME in host mode -------
# Host mode refuses anything but root, so `$HOME/.local/bin` there is /root's.
grep -q 'USAGE_GATE="\${USAGE_GATE:-\$SELF_DIR/usage-gate.sh}"' "$RUNNER" \
  && ok "host mode resolves the gate beside the script, not through \$HOME" \
  || bad "host mode still resolves usage-gate.sh through the invoking user's \$HOME"
grep -q 'USAGE_GATE="\${USAGE_GATE:-\$HOME/.local/bin/usage-gate.sh}"' "$RUNNER" \
  && grep -q '\[ -x "\$USAGE_GATE" \] || USAGE_GATE="\$SELF_DIR/usage-gate.sh"' "$RUNNER" \
  && ok "account mode keeps ~/.local/bin first and beside-the-script second" \
  || bad "account-mode gate resolution changed -- all 18 self-dev accounts use it"

printf '\npaced-node-bin-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
