#!/usr/bin/env bash
# Witness for "EVERY RUNNER RUNS ONLY ITSELF" -- the rotation ownership filter
# in bin/usage-paced-runner.sh.
#
# THE RULE LANDED 2026-08-19 WITH NO WITNESS AT ALL, which is why the defect
# below survived three weeks of clone-free work aimed straight at it.
#
# `-x "$command_path"` was never the ownership question. It was a PROXY for it,
# and it held only while every row named a 0700 per-account clone that no other
# uid could execute. Both halves of that rot at once when the clones go:
#
#   * a row pointing at a path that does not exist is read as SOMEBODY ELSE'S.
#     Measured on vaporwave 2026-09-07, which has no clones: `dog`'s own row
#     failed `-x`, and the tick logged "1 row(s) belong to other accounts and
#     none to this one" about the account's own work. It exits 0, so it reads
#     as an idle rotation.
#   * a row pointing at the SERVED BUILD is executable by every account on the
#     host (one path, mode 0755), so the predicate stops discriminating in the
#     other direction and every account claims every row.
#
# The row's NAME is the account. hf7y/realisateur#996 measured that across all
# 23 ROSTER rows: `account` equals `project` in 23 of 23 -- a copy of the
# primary key. Host mode is unaffected and keeps `-x`: its rows carry a real
# account column and root runs them on every account's behalf.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$RUNNER" ] || { echo "runner not found: $RUNNER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

ME="$(id -un)"
HOSTN=testhost

# One tick, fully hermetic: HOME redirected so run.log lands in $TMP and never
# in the invoking account's real state dir; FORCE skips the gate and tempo so
# the answer is about ownership and nothing else; DRY_RUN suppresses the exec.
tick() {  # $1 = conf body ; echoes the run.log
  local dir="$TMP/run.$RANDOM"
  mkdir -p "$dir"
  printf '%s\n' "$1" > "$dir/conf"
  printf '%s | %s@%s | 20m | live\nnotme | notme@%s | 20m | live\n' \
    "$ME" "$ME" "$HOSTN" "$HOSTN" > "$dir/ROSTER"
  HOME="$dir" \
  PACED_CONF="$dir/conf" \
  SCHEDULER_ROSTER_FILE="$dir/ROSTER" \
  PACED_HOST="$HOSTN" \
  PACED_DRY_RUN=1 PACED_FORCE=1 PACED_MAX_PER_TICK=1 \
  MILESTONE_GATE_BLIND_HOLDS=0 \
    bash "$RUNNER" >/dev/null 2>&1
  cat "$dir/.local/share/scheduler-paced-runner/run.log" 2>/dev/null
}

echo "== account mode: the row this account owns"

# --- 1. THE VAPORWAVE BUG: my own row, command path absent ------------------
# This is the whole defect. Under `-x` this row was foreign and the tick was
# silent; the account is armed in ROSTER and does nothing, forever.
log="$(tick "$ME|1|/nonexistent/path/scheduler-run $ME batch")"
grep -q "WOULD-DISPATCH .* $ME " <<<"$log" \
  && ok "my own row dispatches even though its command path does not exist" \
  || bad "THE VAPORWAVE BUG: my own row was not dispatched: $log"
grep -q 'belong to other accounts' <<<"$log" \
  && bad "my own row was reported as belonging to another account: $log" \
  || ok "my own row is never reported as somebody else's"

# --- 2. THE SHARED-BUILD INVERSION: another account's row, executable ------
# /bin/true stands in for the served build: one path, executable by every
# account on the host. Under `-x` this row is claimed by everyone.
log="$(tick "notme|1|/bin/true notme batch")"
grep -q 'WOULD-DISPATCH' <<<"$log" \
  && bad "THE INVERSION: dispatched another account's row because its path is executable by all: $log" \
  || ok "another account's row is not claimed just because its path is executable"
grep -q 'belong to other accounts' <<<"$log" \
  && ok "...and the tick says so, rather than reading as an idle rotation" \
  || bad "a foreign-only rotation did not name itself as such: $log"

# --- 3. BOTH ROWS PRESENT: exactly mine, nothing else ----------------------
# Asserted on the ROTATION line, which IS the filter's output -- everything
# after it (gate, tempo, milestone) can hold a correctly-owned row for its own
# reasons, and this witness is about ownership alone.
log="$(tick "$(printf '%s|1|/bin/true %s batch\nnotme|1|/bin/true notme batch' "$ME" "$ME")")"
slots="$(sed -n 's/.*ROTATION .* slots=\([0-9]*\) :: \(.*\)$/\1 \2/p' <<<"$log" | head -1)"
[ "$slots" = "1 $ME" ] \
  && ok "with two runnable rows the rotation holds exactly one: mine" \
  || bad "rotation was '$slots', want '1 $ME': $log"

# --- 4. HOST MODE STILL ASKS THE PATH -------------------------------------
# Static, because host mode runs as root over every account. Its rows carry a
# real account column, so `-x` is still the right question there; this pins
# that the account-mode change did not quietly rewrite it.
echo "== host mode is unchanged"
BLOCK="$(sed -n '/^_me=/,/^done$/p' "$RUNNER")"
[ -n "$BLOCK" ] || bad "could not find the ownership filter block in $RUNNER -- this assertion is inert"
grep -q 'PACED_HOST_MODE" = 1' <<<"$BLOCK" \
  && ok "the filter branches on host mode rather than applying one rule to both" \
  || bad "the ownership filter no longer distinguishes host mode from account mode"
grep -q -- '-x "\$_prog"' <<<"$BLOCK" \
  && ok "host mode still resolves ownership by the command path" \
  || bad "host mode lost its -x test; its rows carry a real account column and need it"

printf '\nrunner-owns-its-own-row-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
