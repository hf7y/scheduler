#!/usr/bin/env bash
# dose-common-human-session-witness.sh -- fetch_repo_file's BLIND/OK split is
# a function of WHOSE gh session happens to be sitting around, not of whether
# the caller supplied a credential (hf7y/scheduler#570). schedule/ROSTER no
# longer takes this path -- #432/#686 moved it to a credential-free HTTP
# call -- but _paced.*.conf/_tempo.conf/FREEZE still fall back to it when a
# served build ships no local schedule/ directory at all.
#
# gh_as() in lib/dose-common.sh borrows $SUDO_USER's `gh` session when running
# as root under sudo. On monkey that is a human's authenticated session, so
# `sudo dose <project> --check` looks hostless when it is not. This witness
# exercises the case #570 says monkey "structurally cannot": running with NO
# human session at all, as `dog` on vaporwave would.
#
# DIAGNOSTIC, NOT A FIX. #570 is a DECISION (`DEFAULT-AFTER 14d: none --
# every option is a credential decision`) -- a DECISION with no DEFAULT-AFTER
# is left alone, on purpose, until a human picks one of its three options.
# This locks in today's behaviour under all three identities #570 discusses,
# so whichever option lands has a red witness to turn green.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib/dose-common.sh"
source "$HERE/lib/witness-common.sh"
echo "dose-common-human-session-witness"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"

# Two DISTINCT gh's on the same box: one that has never authenticated (what
# root, or a fresh self-dev account, actually has) and one that has (a human
# at a terminal). gh_as picks between them only by way of $SUDO_USER.
cat > "$FAKEBIN/gh-unauthenticated" <<'EOF'
#!/usr/bin/env bash
echo "To get started with GitHub CLI, please run:  gh auth login" >&2
exit 1
EOF
cat > "$FAKEBIN/gh-human-session" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"repos/hf7y/scheduler/contents/schedule/ROSTER"*) echo "cm9zdGVyLWNvbnRlbnQ=" ;;
  *"repos/hf7y/scheduler "*|*"repos/hf7y/scheduler"$'\n'*) echo "scheduler" ;;
  *) echo "scheduler" ;;
esac
EOF
chmod +x "$FAKEBIN/gh-unauthenticated" "$FAKEBIN/gh-human-session"

# sudo -n -u <acct> gh ... -> dispatch to whichever fake gh represents that
# account's session. Anything else execs straight through.
cat > "$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-n" ] && [ "$2" = "-u" ]; then
  acct="$3"; shift 3
  case "$acct" in
    zach) exec "$FAKEBIN_SUDO_TARGET_HUMAN" "$@" ;;
    *)    exec "$FAKEBIN_SUDO_TARGET_NONE" "$@" ;;
  esac
fi
exec "$@"
EOF
chmod +x "$FAKEBIN/sudo"
export FAKEBIN_SUDO_TARGET_HUMAN="$FAKEBIN/gh-human-session"
export FAKEBIN_SUDO_TARGET_NONE="$FAKEBIN/gh-unauthenticated"

run_fetch() {  # <uid> <sudo_user-or-empty> <gh-binary> -> stdout+stderr, sets RC
  local uid="$1" su="$2" ghbin="$3"
  OUT="$(
    cat > "$WORK/id" <<EOF2
#!/usr/bin/env bash
[ "\$1" = "-u" ] && echo "$uid" || echo fakeuser
EOF2
    chmod +x "$WORK/id"
    PATH="$WORK:$FAKEBIN:$PATH" DOSE_GH_BIN="$ghbin" \
      SUDO_USER="$su" \
      bash -c ". '$LIB'; fetch_repo_file schedule/ROSTER" 2>&1
  )"
  RC=$?
}

# --- 1. a plain non-root account with no gh session: BLIND, as expected ----
# This is `dog` on vaporwave: its own account, its own (unauthenticated) gh.
run_fetch 3005 "" "$FAKEBIN/gh-unauthenticated"
[ "$RC" -eq 6 ] && ok "no-session account: BLIND (rc=6), same as #570 describes for vaporwave" \
  || bad "no-session account exited $RC, want 6 (BLIND): $OUT"

# --- 2. root, no SUDO_USER (a bare cron tick, nobody logged in): BLIND too -
run_fetch 0 "" "$FAKEBIN/gh-unauthenticated"
[ "$RC" -eq 6 ] && ok "root with no SUDO_USER: BLIND (rc=6) -- an armed cron row with nobody logged in" \
  || bad "root/no-SUDO_USER exited $RC, want 6 (BLIND): $OUT"

# --- 3. root, SUDO_USER=zach (a human at the terminal): SUCCEEDS -----------
# The exact shape #570 reports: this passes not because the mechanism is
# hostless, but because root borrowed zach's already-authenticated session.
run_fetch 0 "zach" "$FAKEBIN/gh-unauthenticated"
[ "$RC" -eq 0 ] && ok "root with SUDO_USER=zach: succeeds -- by borrowing zach's session, per #570" \
  || bad "root/SUDO_USER=zach exited $RC, want 0 (this is the borrowed-session path #570 names): $OUT"

# The point of #570 in one assertion: cases 1 and 3 differ ONLY in whether a
# human happens to be logged in as root's invoker, not in any credential the
# caller supplied.
if [ "$RC" -eq 0 ]; then
  ok "case 1 (BLIND) vs case 3 (OK) differ solely by \$SUDO_USER's session -- the design bug #570 names"
fi

printf '\ndose-common-human-session-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
