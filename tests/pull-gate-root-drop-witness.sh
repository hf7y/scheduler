#!/usr/bin/env bash
# Witness for the pull gate's privilege drop -- bin/usage-paced-runner.sh.
#
# THE BUG THIS EXISTS TO PREVENT: hf7y/scheduler#596. PACED_HOST_MODE=1 runs
# the dispatcher as root (it dispatches AS each account via sudo), but the
# pull gate's own self-update -- `git -C "$REPO_ROOT" fetch/merge` -- ran
# BARE, before any privilege drop, against a checkout owned by an
# unprivileged account. Every remote-tracking ref it wrote came out
# root-owned, and root cannot rewrite its own lockfiles on the next fetch:
# `refs/remotes/origin/dose-park-crt-...` inside realisateur's own checkout
# aborted every dispatch for two days with "Permission denied" on the lock.
#
# The fix: when running as root (`id -u` = 0) and $REPO_ROOT is owned by
# someone else, every git call in the pull gate routes through
# `sudo -n -u <owner>` -- the same de-escalation pattern the rest of this
# file already uses for per-account dispatch. This lifts the REAL block (the
# marker pair pull-escalation-witness.sh also lifts) so drift between the
# two witnesses is impossible.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/usage-paced-runner.sh"
[ -f "$RUNNER" ] || { echo "runner not found: $RUNNER"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# --- lift the real block -----------------------------------------------------
BLOCK="$TMP/pull-gate.sh"
awk '/^# >>> pull gate/,/^# <<< pull gate/' "$RUNNER" > "$BLOCK"
grep -q 'REPO_ROOT/.git' "$BLOCK" \
  || { echo "FAIL: could not find the pull gate's git block in $RUNNER"; exit 1; }

REALGIT="$(command -v git)"
REALID="$(command -v id)"
REALSTAT="$(command -v stat)"
mkdir -p "$TMP/bin"

# `id -u` lies: reports root. Everything else passes through, so `id -un`
# (used elsewhere for logging) still names the real invoking account.
cat > "$TMP/bin/id" <<STUB
#!/usr/bin/env bash
[ "\$1" = "-u" ] && { echo 0; exit 0; }
exec "$REALID" "\$@"
STUB
chmod +x "$TMP/bin/id"

# `sudo -n -u <owner> -H git -C <root> <args...>` is logged, then the leading
# sudo flags are stripped and the real command runs for real -- so the ticks
# below still genuinely fetch/merge, and the rest of the pull gate's own
# behaviour (advance, freeze, escalate) stays honest.
SUDOLOG="$TMP/sudo.log"
cat > "$TMP/bin/sudo" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SUDOLOG"
while [ \$# -gt 0 ]; do
  case "\$1" in
    -n|-H) shift ;;
    -u) shift 2 ;;
    *) break ;;
  esac
done
exec "\$@"
SHIM
chmod +x "$TMP/bin/sudo"
: > "$SUDOLOG"
export PATH="$TMP/bin:$PATH"

GATE="$TMP/bin/gate.sh"
{ printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'STATE_DIR="$1"; REPO_ROOT="$2"\n'
  printf 'JOB_NAME="scheduler-paced-runner"\nPACED_HOST="witnesshost"\n'
  printf 'LOG="$STATE_DIR/run.log"\nmkdir -p "$STATE_DIR"\n'
  printf 'log() { echo "$(date -Is) $*" >> "$LOG"; }\n'
  cat "$BLOCK"; } > "$GATE"
chmod +x "$GATE"

# --- fixture: a real origin the clone is genuinely behind, owned by the
# invoking (unprivileged, in real life) account -----------------------------
git_q() { "$REALGIT" -c init.defaultBranch=main -c user.email=w@w -c user.name=w "$@"; }
ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; CLONE="$TMP/clone"
git_q init --bare -q "$ORIGIN"
git_q init -q "$SEED"
echo v1 > "$SEED/code.sh"
git_q -C "$SEED" add -A; git_q -C "$SEED" commit -qm seed
git_q -C "$SEED" remote add origin "$ORIGIN"; git_q -C "$SEED" push -q origin main
git_q clone -q "$ORIGIN" "$CLONE"
echo v2 > "$SEED/code.sh"
git_q -C "$SEED" commit -qam "the fix that must reach this host"
git_q -C "$SEED" push -q origin main

REAL_OWNER="$("$REALSTAT" -c '%U' "$CLONE")"

STATE="$TMP/state"
tick() { "$GATE" "$STATE" "$CLONE" >/dev/null 2>&1; }

echo "== 1. id -u reports 0 (root); the checkout is owned by someone else"
tick
if [ -s "$SUDOLOG" ]; then ok "the pull gate routed through sudo at all"
else bad "sudo was never invoked -- git ran bare as root"; fi
if grep -q -- "-u $REAL_OWNER" "$SUDOLOG"; then
  ok "sudo -u names the checkout's actual owner ($REAL_OWNER), not a hardcoded account"
else bad "sudo log does not name -u $REAL_OWNER: $(cat "$SUDOLOG")"; fi
if grep -q 'git -C .*fetch' "$SUDOLOG"; then ok "the fetch itself went through sudo -u $REAL_OWNER"
else bad "no fetch in the sudo log: $(cat "$SUDOLOG")"; fi
if grep -q -- "-n " "$SUDOLOG"; then ok "sudo is non-interactive (-n) -- a missing NOPASSWD rule fails closed, not with a hang"
else bad "sudo invoked without -n: $(cat "$SUDOLOG")"; fi

echo "== 2. the fetch still genuinely advanced the clone despite routing through the stub"
if git_q -C "$CLONE" merge-base --is-ancestor "$(git_q -C "$SEED" rev-parse HEAD)" HEAD 2>/dev/null; then
  ok "clone fast-forwarded to the new commit -- the drop did not just log, the real op still ran"
else bad "clone did not advance -- the sudo shim broke the underlying operation"; fi
if grep -q 'PULL fast-forwarded' "$STATE/run.log" 2>/dev/null; then ok "logged the fast-forward as usual"
else bad "no fast-forward log line: $(cat "$STATE/run.log" 2>/dev/null)"; fi

echo "== 3. id -u reports the real (non-root) uid: no privilege to drop, no sudo needed"
rm -rf "$STATE" "$SUDOLOG"; : > "$SUDOLOG"
cat > "$TMP/bin/id" <<STUB
#!/usr/bin/env bash
exec "$REALID" "\$@"
STUB
chmod +x "$TMP/bin/id"
echo v3 > "$SEED/code.sh"; git_q -C "$SEED" commit -qam "second fix"; git_q -C "$SEED" push -q origin main
tick
if [ ! -s "$SUDOLOG" ]; then ok "account-mode (non-root) run never touches sudo -- unchanged behaviour"
else bad "sudo invoked even though id -u was not 0: $(cat "$SUDOLOG")"; fi
if grep -q 'PULL fast-forwarded' "$STATE/run.log" 2>/dev/null; then ok "still fast-forwards normally without root"
else bad "account-mode fetch/merge broke: $(cat "$STATE/run.log" 2>/dev/null)"; fi

echo
echo "pull-gate-root-drop-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
