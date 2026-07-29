#!/usr/bin/env bash
# freeze-check.sh -- the migration abort handle. ONE definition of "is dispatch
# frozen right now", called by every consumer at DISPATCH time.
#
# Built 2026-07-29, Zach-directed ("initiate the freeze"), as M1(a) of THE PLAY
# (scheduler .scheduler/FOCUS.md; rationale realisateur dd11360 / bde9e62).
# M1(b), the readiness probe, was retired before being built. This is the ONLY
# surviving pre-move mechanism, which is why it is wired rather than documented.
#
# WHY A FILE AND NOT A COMMENTED-OUT CRONTAB: a freeze has to be (a) visible to
# both hosts, (b) revertable by one commit, (c) auditable after the fact. A
# hand-commented crontab is none of those and cannot be reviewed. Zach's call
# 2026-07-28: "a git-tracked file both hosts read and refuse loudly on".
#
# CONTRACT
#   exit 0  -- not frozen; the caller may dispatch.
#   exit 1  -- FROZEN. The caller MUST NOT dispatch. Reason goes to stderr.
#   exit 2  -- the freeze file exists but could not be read/parsed. Treated as
#              FROZEN by every caller. An unreadable abort handle is engaged,
#              never disengaged -- failing open here would make the one
#              mechanism that stops a bad run the one that silently does not.
#
# TO ENGAGE:   create schedule/FREEZE with a reason, commit, push. Both hosts
#              pick it up on their next pull (<= 5 min).
# TO RELEASE:  git rm schedule/FREEZE, commit, push.
#
# WHAT THIS DOES NOT COVER -- stated here because M1(a) requires it to, and
# because an unstated gap in an abort handle is worse than a missing one:
#
#   1. svc-vaporwave's fixed-cron jobs (aedile 03:00, vkv-inventory 04:00).
#      Zach 2026-07-29 answered "freeze" to the scope question (7fccdc1 q2),
#      so they are DECLARED in scope. They are NOT mechanically enforced: that
#      crontab lives under a second account, requires sudo, and has never been
#      read by this project (BRIEF-dexter-migration.md sec 0 lists it BLIND).
#      A freeze therefore does NOT stop those two jobs. This is declared
#      coverage without enforcement and must be read as such.
#   2. Anything invoked by a human directly. This checks automated dispatch.
#   3. Work already in flight when the freeze lands. It stops the NEXT
#      dispatch; it does not kill a running job.
#
# Sourceable (`. freeze-check.sh` then `freeze_check`) or runnable standalone.

set -uo pipefail

_freeze_file() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  printf '%s\n' "${SCHEDULER_FREEZE_FILE:-$here/../schedule/FREEZE}"
}

freeze_check() {
  local f reason
  f="$(_freeze_file)"

  [ -e "$f" ] || return 0          # the common case: no file, not frozen

  if [ ! -r "$f" ]; then
    printf 'FROZEN (unreadable) -- %s exists but cannot be read. Treating as
FROZEN: an abort handle that fails open is not an abort handle.\n' "$f" >&2
    return 2
  fi

  reason="$(grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null | head -5)"
  [ -n "$reason" ] || reason='(no reason recorded in the freeze file)'

  printf 'FROZEN -- dispatch refused by %s\n%s\nRelease: git rm %s && commit && push (both hosts pick it up within 5 min).\nNOT covered by this freeze: svc-vaporwave fixed-cron (aedile 03:00, vkv-inventory 04:00) -- declared in scope, NOT enforced; and jobs already running.\n' \
    "$f" "$reason" "$f" >&2
  return 1
}

# --selftest: the negative-test bar every mechanism here is held to. A freeze
# that has never been observed to refuse has not been shown able to refuse.
if [ "${1:-}" = "--selftest" ]; then
  fails=0
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/schedule"

  SCHEDULER_FREEZE_FILE="$tmp/schedule/FREEZE"
  export SCHEDULER_FREEZE_FILE

  freeze_check >/dev/null 2>&1
  [ $? -eq 0 ] || { echo "FAIL: absent freeze file should exit 0"; fails=$((fails+1)); }

  printf '# comment only\n\nmigration wave 1 rollback\n' > "$SCHEDULER_FREEZE_FILE"
  out="$(freeze_check 2>&1)"; rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: present freeze file should exit 1, got $rc"; fails=$((fails+1)); }
  case "$out" in *"migration wave 1 rollback"*) ;; *)
    echo "FAIL: reason not surfaced (comments/blanks must be stripped)"; fails=$((fails+1));; esac
  case "$out" in *"svc-vaporwave"*) ;; *)
    echo "FAIL: refusal must state what it does not cover"; fails=$((fails+1));; esac

  chmod 000 "$SCHEDULER_FREEZE_FILE" 2>/dev/null
  if [ ! -r "$SCHEDULER_FREEZE_FILE" ]; then
    freeze_check >/dev/null 2>&1
    [ $? -eq 2 ] || { echo "FAIL: unreadable freeze file must exit 2 (fail closed)"; fails=$((fails+1)); }
  fi
  chmod 644 "$SCHEDULER_FREEZE_FILE" 2>/dev/null

  printf '\n# nothing but comments\n' > "$SCHEDULER_FREEZE_FILE"
  out="$(freeze_check 2>&1)"; rc=$?
  [ $rc -eq 1 ] || { echo "FAIL: reasonless freeze still freezes, got $rc"; fails=$((fails+1)); }
  case "$out" in *"no reason recorded"*) ;; *)
    echo "FAIL: reasonless freeze must say so rather than printing an empty reason"; fails=$((fails+1));; esac

  if [ "$fails" -eq 0 ]; then echo "ok -- 6 assertions, 0 failure(s)"; else
    echo "$fails failure(s)"; exit 1; fi
  exit 0
fi

# Standalone invocation.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  freeze_check
  exit $?
fi
