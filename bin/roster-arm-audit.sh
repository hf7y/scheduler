#!/usr/bin/env bash
# roster-arm-audit.sh -- catches a ROSTER row marked 'live' whose crontab
# never got the memo (#305): `--arm` merges a PR but does not, itself,
# converge any crontab -- that's a separate, easy-to-forget `--apply`.
# Read-only; the tag it checks for comes from dose-common.sh's runner_tag()
# so it can't drift from what `dose --apply` actually converges to.
#
# RUNNER: tests/roster-arm-audit-witness.sh
set -uo pipefail

CLI_NAME="roster-arm-audit.sh"

usage() {
  cat <<EOF
usage: $CLI_NAME

Reads schedule/ROSTER fresh from GitHub. For every row whose host is THIS
host and whose state is 'live', checks that account's crontab for the
RUNNER line dose-project.sh converges to. Prints one line per project;
writes nothing.

exit: 0 clean   1 armed-but-not-running row(s) found, printed   5 broken   6 blind
EOF
}
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -*) echo "$CLI_NAME: unknown flag $1" >&2; usage >&2; exit 2 ;;
esac

DOSE_LIB_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/dose-common.sh
. "$DOSE_LIB_DIR/lib/dose-common.sh"

DOSE_SCHEDULE_DIR="${DOSE_SCHEDULE_DIR:-$DOSE_LIB_DIR/schedule}"
TAG="$(runner_tag "$DOSE_SCHEDULE_DIR" "$HOST")"
if [ -z "$TAG" ]; then
  echo "BROKEN: no usable RUNNER_JOB in $DOSE_SCHEDULE_DIR/_runner.conf (or its $HOST override) -- nothing to check against" >&2
  exit 5
fi

ROSTER_CONTENT="$(fetch_roster)" || exit $?

FOUND=0
BROKEN=0
CHECKED=0
while IFS='|' read -r f1 f2 f3 f4 || [ -n "$f1" ]; do
  case "$f1" in ''|\#*) continue ;; esac
  proj="$(xargs <<<"$f1")"; accthost="$(xargs <<<"$f2")"; state="$(xargs <<<"$f4")"
  [ -n "$proj" ] || continue
  [ "${accthost##*@}" = "$HOST" ] || continue
  [ "$state" = "live" ] || continue
  acct="${accthost%@*}"
  CHECKED=$((CHECKED + 1))

  cron="$(crontab_read "$acct")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "BROKEN: could not read $acct's crontab -- $cron" >&2
    BROKEN=1
    continue
  fi
  if grep -qF "$TAG" <<<"$cron"; then
    echo "ok: '$proj' is live and $acct's crontab carries the RUNNER line"
  else
    echo "ARMED BUT NOT RUNNING: '$proj' is live in schedule/ROSTER but $acct's crontab on $HOST has no RUNNER line -- run: dose $proj --apply"
    FOUND=1
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' <<<"$ROSTER_CONTENT")

if [ "$BROKEN" -eq 1 ]; then exit 5; fi
if [ "$CHECKED" -eq 0 ]; then
  echo "kept: no live schedule/ROSTER row names $HOST"
  exit 0
fi
[ "$FOUND" -eq 0 ] && echo "clean: $CHECKED live row(s) on $HOST all have their RUNNER line"
exit "$FOUND"
