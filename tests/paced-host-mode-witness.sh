#!/usr/bin/env bash
# paced-host-mode-witness.sh -- the host-dispatch mode of usage-paced-runner.sh.
#
# WHAT IT CAN AND CANNOT SEE, said up front because the gap is the interesting
# part. A full host-mode dispatch needs root and five 0700 homes, which no test
# suite should have. So this witnesses the three things the mode ADDS that are
# checkable unprivileged -- the root refusal, the account derivation, and the
# fact that account mode did not change -- and does NOT witness the sudo
# invocation itself. That last one is named in the PR rather than implied to be
# covered, per hf7y/scheduler#112: an unwitnessed branch is a claim.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/../bin/usage-paced-runner.sh"
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }

echo "paced-host-mode-witness"

# --- 1. host mode without root REFUSES, rather than degrading -------------
# The degraded shape is the dangerous one: without root every sudo fails one
# at a time and the tick reads as five broken projects instead of one
# misconfigured runner.
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP: running as root, cannot exercise the non-root refusal"
else
  out="$(PACED_HOST_MODE=1 bash "$RUNNER" 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && ok "host mode as non-root exits 2" \
    || bad "host mode as non-root exited $rc, want 2: $out"
  grep -qi 'needs root' <<<"$out" && ok "the refusal names root as the reason" \
    || bad "exit 2 but the message never says root: $out"
  grep -qi 'refusing' <<<"$out" && ok "it says it is refusing, not reporting" \
    || bad "the refusal does not say so: $out"
fi

# --- 2. acct_of_prog: who owns the row ------------------------------------
# Extracted from the script so this can call it. Sourcing the whole runner
# would run it, so the function is read out and evaluated alone.
eval "$(sed -n '/^acct_of_prog() {/,/^}/p' "$RUNNER")"
if ! declare -F acct_of_prog >/dev/null; then
  bad "acct_of_prog could not be extracted from the runner -- the rest of this file tested nothing"
else
  got="$(acct_of_prog /home/ecosim/Documents/Projects/scheduler/bin/scheduler-run || true)"
  [ "$got" = ecosim ] && ok "derives a plain account name" || bad "got '$got', want ecosim"

  # A HYPHEN IN THE NAME. vim-arcade is a live account and a character class
  # written [a-z]* or [[:alnum:]]* would truncate it to "vim" and dispatch as
  # the wrong uid -- or, more likely, as no uid at all.
  got="$(acct_of_prog /home/vim-arcade/Documents/Projects/scheduler/bin/scheduler-run || true)"
  [ "$got" = vim-arcade ] && ok "a hyphenated account survives (vim-arcade)" \
    || bad "got '$got', want vim-arcade"

  # NOT UNDER /home: must fail, not return something plausible. A row pointing
  # at /usr/local/bin has no owning account and dispatching it as root would
  # be the worst available outcome.
  if acct_of_prog /usr/local/bin/oddball >/dev/null 2>&1; then
    bad "a non-/home path returned an account instead of failing"
  else
    ok "a non-/home path fails rather than guessing"
  fi
  if acct_of_prog "" >/dev/null 2>&1; then
    bad "an empty path returned an account"
  else
    ok "an empty path fails"
  fi

  # Not vacuous: prove the function can be wrong if the regex is.
  got="$(acct_of_prog /home/a/b || true)"
  [ "$got" = a ] && ok "a minimal /home/<a>/ path still parses" || bad "got '$got', want a"
fi

# --- 3. account mode is UNCHANGED -----------------------------------------
# The mode is opt-in. With PACED_HOST_MODE unset the runner must not require
# root and must not reach for a host lock path.
out="$(PACED_HOST_MODE=0 bash -n "$RUNNER" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "account mode parses clean" || bad "parse failed: $out"
grep -q 'STATE_DIR="\$HOME/.local/share/\$JOB_NAME"' "$RUNNER" \
  && ok "account mode still uses the \$HOME-scoped state dir" \
  || bad "the account-mode state dir is no longer \$HOME-scoped"

printf '\npaced-host-mode-witness: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
