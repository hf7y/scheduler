#!/usr/bin/env bash
# deadman-switch.sh -- THE dead-man switch. One implementation, sourced.
#
# RETIRES: the hand-pasted copy in svc-vaporwave's
# aedile-nightly-batch-loop.sh, and the inline block that used to live in
# lib/sweep-loop-common.sh.
#
# WHY THIS FILE EXISTS
# --------------------
# On 2026-07-28 aedile was given a dead-man switch by pasting ~10 lines out
# of an audit script's printed patch, because aedile's wrapper is
# deliberately bespoke (a shared org repo, a dedicated clone, a PR flow) and
# so does not source lib/sweep-loop-common.sh. Within the same day the copy
# had already lost four things the original had:
#
#   1. no notify-send -- a tripped switch was silent on the desktop;
#   2. it was placed ABOVE the wrapper's own `LOG=` assignment, so its
#      notice went to cron mail instead of run.log, and `scheduler status`
#      -- which slices "last run" out of that log -- saw an expired job as
#      simply not having run;
#   3. no "=== <ts> ===" opening delimiter, so even reaching the log it
#      would not have formed the start/completion pair status parses;
#   4. it dropped the renewal warning, which is the one piece of prose that
#      stops the most likely wrong fix: bumping EXPIRY_DAYS does NOT renew
#      an existing stamp, because the stamp is only written when the file
#      is missing.
#
# It also sat above `mkdir -p "$STATE_DIR"`, so on a fresh install the
# stamp write would have failed on a directory that did not exist yet.
#
# None of that was carelessness; it is what copying does. The fix is not a
# better copy, it is one copy. A bespoke wrapper can still source a shared
# FUNCTION without adopting a shared ENGINE -- that distinction is the whole
# point, and it is why this is a small standalone file rather than a reason
# to force aedile onto sweep-loop-common.sh (whose clone/branch/push model
# is genuinely wrong for a shared monorepo).
#
# CONTRACT -- caller sets these before calling, and MUST have created
# STATE_DIR already:
#   JOB_NAME     required, used in the notification and the log record
#   STATE_DIR    required, must exist; holds the expires_at stamp
#   LOG          required, the run log `scheduler status` reads
#   EXPIRY_DAYS  optional, default 7
#
# On trip: writes a complete ===-delimited run record to $LOG, fires
# notify-send, and returns 3. On renewal/first run: stamps now+EXPIRY_DAYS
# and returns 0. The CALLER decides what to do with 3 -- this file never
# calls exit, so sourcing it can never terminate a caller by surprise.

deadman_check() {
  local expires_at_file expires_at now_is msg
  : "${EXPIRY_DAYS:=7}"

  # Fail loud on a broken contract rather than silently skipping the switch.
  # A switch that quietly does nothing is worse than no switch: it reads as
  # protection that is not there.
  if [ -z "${JOB_NAME:-}" ] || [ -z "${STATE_DIR:-}" ] || [ -z "${LOG:-}" ]; then
    echo "deadman_check: BROKEN CONTRACT -- JOB_NAME, STATE_DIR and LOG must all be set" >&2
    return 2
  fi
  if [ ! -d "$STATE_DIR" ]; then
    echo "deadman_check: BROKEN CONTRACT -- STATE_DIR ($STATE_DIR) does not exist; create it before calling" >&2
    return 2
  fi

  expires_at_file="$STATE_DIR/expires_at"
  if [ ! -f "$expires_at_file" ]; then
    date -d "+${EXPIRY_DAYS} days" -Is > "$expires_at_file" || {
      echo "deadman_check: could not write $expires_at_file" >&2
      return 2
    }
  fi
  expires_at="$(cat "$expires_at_file")"
  now_is="$(date -Is)"

  [[ "$now_is" > "$expires_at" ]] || return 0

  msg="Auto-disabled: dead-man switch tripped ($expires_at). Renew: rm $expires_at_file -- next run re-stamps now+${EXPIRY_DAYS}d. Bumping EXPIRY_DAYS alone does NOT renew (the stamp is only written when the file is missing)."
  # `|| true` guards against FAILING. It does not guard against NEVER
  # RETURNING, and those are different. Found live 2026-07-28: under
  # svc-vaporwave the dbus socket at $XDG_RUNTIME_DIR/bus exists but nothing
  # is listening, so notify-send blocks forever -- the first attempt to
  # source this switch into aedile's wrapper hung until the test's timeout
  # killed it. A service account has no desktop session to notify; the
  # notification is best-effort garnish and must never be able to wedge the
  # job it is decorating.
  timeout 5 notify-send "$JOB_NAME" "$msg" 2>/dev/null || true
  {
    echo "=== $now_is ==="
    echo "expired -- dead-man switch tripped; no work attempted (no clone, no claude). $msg"
    echo "note: bin/sync-crontab.sh prunes this job's crontab line on its next --apply run; this script never touches crontab itself"
    echo "=== skipped (expired $expires_at) $now_is (0s) ==="
  } >> "$LOG"
  return 3
}
