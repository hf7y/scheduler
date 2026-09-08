#!/usr/bin/env bash
# host-mode-job-state-witness.sh -- bin/usage-paced-runner.sh's job_state_for (#707).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/../bin/usage-paced-runner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "host-mode-job-state-witness"

eval "$(sed -n '/^job_state_for() {/,/^}/p' "$RUNNER")"
if ! declare -F job_state_for >/dev/null; then
  bad "job_state_for could not be extracted from the runner -- the rest of this file tested nothing"
  printf '\nhost-mode-job-state-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
  exit 1
fi

# A stub standing in for lib/dose-common.sh's real one: keyed by the
# schedule/<project>.conf path, same shape sweep-loop-common.sh would source.
fetch_repo_file() {
  case "$1" in
    schedule/dog.conf)   printf 'BATCH_JOB_NAME="dog-nightly-batch"\n' ;;
    schedule/blank.conf) printf 'BATCH_SCRIPT="legacy.sh"\n' ;;
    *) return 4 ;;
  esac
}

got="$(PACED_HOST_MODE=1 job_state_for dog /home/dog /usr/local/share/verb-builds/current/scheduler/bin/scheduler-run)"
[ "$got" = "/home/dog/.local/share/dog-nightly-batch" ] \
  && ok "host mode reads BATCH_JOB_NAME, not the shared build path's basename" \
  || bad "got '$got', want /home/dog/.local/share/dog-nightly-batch"

got="$(PACED_HOST_MODE=1 job_state_for blank /home/blank /usr/local/share/verb-builds/current/scheduler/bin/scheduler-run)"
[ "$got" = "/home/blank/.local/share/scheduler-run" ] \
  && ok "host mode with no BATCH_JOB_NAME in the conf falls open to the old basename convention" \
  || bad "got '$got', want the basename fallback: $got"

got="$(PACED_HOST_MODE=1 job_state_for ghost /home/ghost /usr/local/share/verb-builds/current/scheduler/bin/scheduler-run)"
[ "$got" = "/home/ghost/.local/share/scheduler-run" ] \
  && ok "host mode with an unfetchable conf falls open, same as no BATCH_JOB_NAME" \
  || bad "got '$got', want the basename fallback: $got"

got="$(PACED_HOST_MODE=0 job_state_for dog /home/dog /home/dog/Documents/Projects/scheduler/dog-nightly-batch-loop.sh)"
[ "$got" = "/home/dog/.local/share/dog-nightly-batch" ] \
  && ok "account mode is unchanged: the <job>-loop.sh convention, never fetched" \
  || bad "got '$got', want the account-mode convention: $got"

unset -f fetch_repo_file
got="$(PACED_HOST_MODE=1 job_state_for dog /home/dog /usr/local/share/verb-builds/current/scheduler/bin/scheduler-run)"
[ "$got" = "/home/dog/.local/share/scheduler-run" ] \
  && ok "host mode with fetch_repo_file unavailable falls open rather than erroring" \
  || bad "got '$got', want the basename fallback: $got"

printf '\nhost-mode-job-state-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
