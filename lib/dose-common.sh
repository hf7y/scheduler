#!/usr/bin/env bash
# dose-common.sh -- the half `dose <project>` and `dose host` must agree on.
#
# WHY IT EXISTS. Both forms read the SAME roster from the SAME place and write
# crontabs through the SAME rules. Written twice they drift, and the drift is
# silent: hf7y/scheduler#119 is that exact failure caught one commit early --
# `dose <project>` kept converging five staggered per-account crontabs for six
# hours after hf7y/scheduler#55 decided there should be one host tick, and it
# exited 0 the whole time.
#
# Sourced, never executed. Callers set nothing; every knob below already reads
# from the environment so a witness can point it at fixtures.
#
# RUNNER: tests/dose-project-witness.sh, tests/dose-host-witness.sh
set -uo pipefail

REPO_SLUG="${DOSE_REPO_SLUG:-hf7y/scheduler}"
ROSTER_REF="${DOSE_ROSTER_REF:-main}"
GH_BIN="${DOSE_GH_BIN:-gh}"
CRONTAB_BIN="${DOSE_CRONTAB_BIN:-crontab}"
HOST="${DOSE_HOST_OVERRIDE:-$(hostname -s 2>/dev/null || echo unknown)}"
LOCAL_ACCOUNT="$(id -un)"

# --- stagger: IDENTICAL formula to cron_spec_for() in realisateur's
# bin/wire-release-channel.sh (cksum % 60 of the name). Not sourced -- that
# script is a CLI entry point that consumes $@ on load, not a library -- but
# the transform is copied verbatim so dose and the release-channel tick can
# never disagree about which minute a given name lands on.
stagger_minute() {
  printf '%d' "$(( $(cksum <<<"$1" | cut -d' ' -f1) % 60 ))"
}

# Roster rate ("6h" / "1h" / "30m", per hf7y/scheduler#81) -> 5-field cron,
# minute(s) staggered by project name. Echoes the fields; returns 1 on a rate
# this dose does not understand (a broken roster row, not a usage error).
cron_fields_for_rate() {
  local rate="$1" name="$2" m n v i count vals
  m="$(stagger_minute "$name")"
  if [[ "$rate" =~ ^([0-9]+)h$ ]]; then
    n="${BASH_REMATCH[1]}"
    if [ "$n" -eq 1 ]; then printf '%s * * * *' "$m"; else printf '%s */%s * * *' "$m" "$n"; fi
    return 0
  fi
  if [[ "$rate" =~ ^([0-9]+)m$ ]]; then
    n="${BASH_REMATCH[1]}"
    { [ "$n" -ge 1 ] && [ "$n" -lt 60 ] && [ $((60 % n)) -eq 0 ]; } || return 1
    count=$((60 / n)); v=$m; vals="$m"
    for ((i = 1; i < count; i++)); do v=$(( (v + n) % 60 )); vals="$vals,$v"; done
    vals="$(printf '%s\n' "${vals//,/$'\n'}" | sort -n | paste -sd, -)"
    printf '%s * * * *' "$vals"
    return 0
  fi
  return 1
}

validate_cron() { [ "$(awk '{print NF}' <<<"$1")" -eq 5 ]; }

# --- crontab access, one account's at a time. "no crontab for" is a
# successful read of nothing (crontab -l's own exit 1 for that case); anything
# else nonzero is a real failure and must not be swallowed into "empty".
crontab_read() {
  local acct="$1" out rc
  if [ "$acct" = "$LOCAL_ACCOUNT" ]; then
    "$CRONTAB_BIN" -l 2>/dev/null || true
    return 0
  fi
  out="$(sudo -n -u "$acct" "$CRONTAB_BIN" -l 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$out" in
      *"no crontab for"*) printf ''; return 0 ;;
      *) printf '%s' "$out" >&2; return 1 ;;
    esac
  fi
  printf '%s' "$out"
}
crontab_write() {
  local acct="$1" content="$2"
  if [ "$acct" = "$LOCAL_ACCOUNT" ]; then
    printf '%s\n' "$content" | "$CRONTAB_BIN" -
  else
    printf '%s\n' "$content" | sudo -n -u "$acct" "$CRONTAB_BIN" -
  fi
}

# --- repo files that are STILL repo files: _runner.conf, _tempo.conf, FREEZE.
# The roster left (see fetch_roster below). root has no `gh` auth, so a
# human-invoked read borrows $SUDO_USER's rather than plant a standing secret.
gh_as() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    sudo -n -u "$SUDO_USER" "$GH_BIN" "$@"
  else
    "$GH_BIN" "$@"
  fi
}

gh_as_identity_note() {  # not folded into gh_as: fetch_repo_file's `gh_as ... 2>&1` would capture it too (#570)
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    printf 'dose: reading gh as root, borrowing $SUDO_USER=%s'"'"'s session -- hostless only because %s is logged in here (#570)\n' "$SUDO_USER" "$SUDO_USER"
  else
    printf 'dose: reading gh as %s'"'"'s own session\n' "$(id -un)"
  fi
}

# fetch_repo_file <relpath> -- print a file from the repo, over gh, no clone.
#
# GENERALISED FROM fetch_roster, not copied beside it. schedule/FREEZE needs
# exactly the same treatment as schedule/ROSTER (hf7y/scheduler#124) and a
# second fetcher would be a second answer to "is this repo reachable" -- the
# one-fact-two-readers shape this estate keeps paying for. The BLIND/GAP
# distinction below is the whole value and must not be re-derived per caller.
fetch_repo_file() {
  local rel="${1:?fetch_repo_file needs a repo-relative path}"
  if ! command -v "$GH_BIN" >/dev/null 2>&1; then
    echo "BLIND: '$GH_BIN' not on PATH -- cannot read $rel" >&2
    return 6
  fi
  [ -n "${_GH_AS_IDENTITY_LOGGED:-}" ] || { gh_as_identity_note >&2; _GH_AS_IDENTITY_LOGGED=1; }
  local out rc
  out="$(gh_as api "repos/$REPO_SLUG/contents/$rel?ref=$ROSTER_REF" --jq '.content' 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    # "THE FILE IS NOT THERE" AND "I COULD NOT LOOK" ARE DIFFERENT ANSWERS, and
    # collapsing them is this estate's signature failure -- selfdev-release-tick
    # makes the same distinction in the other direction ("Deliberately NOT 3.
    # BLIND means we could not look at the channel; this means we looked at
    # ourselves and the bootstrap is not here").
    #
    # They ARE distinguishable, contrary to a first draft of this function: a
    # 404 from the contents endpoint, when `repos/<slug>` itself reads fine, is
    # a POSITIVE statement that the ref carries no such file. Only if the repo
    # probe fails too is dose actually blind. Without this, a mistyped path
    # would report "cannot see truth" forever instead of "that file is absent",
    # and the operator would go looking at credentials.
    if printf '%s' "$out" | grep -q 'HTTP 404' \
       && gh_as api "repos/$REPO_SLUG" --jq '.name' >/dev/null 2>&1; then
      echo "GAP: $REPO_SLUG is reachable and $ROSTER_REF carries no $rel." >&2
      echo "     It has not landed on that ref yet, or the path is wrong." >&2
      echo "     This is not a credential problem: repos/$REPO_SLUG read fine on the same token." >&2
      return 4
    fi
    echo "BLIND: gh could not read $rel from $REPO_SLUG@$ROSTER_REF -- unauthenticated or unreachable. Nothing was verified: $out" >&2
    return 6
  fi
  printf '%s' "$out" | tr -d '\n' | base64 -d 2>/dev/null
}

# THE ARMING AUTHORITY IS A SERVICE, NOT THIS REPO (#432). Over `gh` it needed
# a credential every host lacked -- gh_as borrows $SUDO_USER's session and a
# cron row has none, so host mode read BLIND and exited 2 every tick. A local
# port needs none: verified from root@monkey under `env -i`, which is what a
# cron row is.
#
# STATE AND NOTHING ELSE (#996). `host` is answered by THIS MACHINE -- a
# project has a row here iff its unix account exists here -- so `dose <p>` off
# that host now says so instead of hopping. Run dose where the account lives.
ROSTER_URL="${SCHEDULER_ROSTER_URL:-http://100.107.253.56:8646}"
ROSTER_RATE="${SCHEDULER_ROSTER_RATE:-20m}"

fetch_roster() {
  local raw
  for _b in curl jq; do
    command -v "$_b" >/dev/null 2>&1 || {
      echo "BLIND: '$_b' is not on PATH -- cannot read the roster service. Nothing was verified." >&2
      return 6; }
  done
  # NO FALLBACK. Unreachable is BLIND, and BLIND classifies nothing.
  raw="$(curl -fsS --max-time 10 "$ROSTER_URL/roster" 2>/dev/null)" || {
    echo "BLIND: the roster service at $ROSTER_URL is unreachable. Refusing to guess at what is armed." >&2
    return 6; }
  # 6-vs-4 as fetch_repo_file draws it: reachable-but-empty is a GAP, not BLIND.
  local _rows
  _rows="$(printf '%s' "$raw" | jq -r '.rows[]? | "\(.project)\t\(.state)"' 2>/dev/null)"
  if [ -z "$_rows" ]; then
    echo "GAP: $ROSTER_URL is reachable and carries no rows. Nothing is armed anywhere; this is not a credential problem." >&2
    return 4
  fi
  # TRANSPORT ONLY -- EVERY ROW, NO HOST FILTER. The roster is the ESTATE's
  # state; realisateur's readers all take `.rows[]` whole. Narrowing is the
  # caller's job and it asks the machine: roster_rows() does, dose does not.
  printf '%s\n' "$_rows" \
  | while IFS="$(printf '\t')" read -r _p _s; do
      [ -n "$_p" ] || continue
      printf '%s | %s@%s | %s | %s\n' "$_p" "$_p" "${PACED_HOST:-$HOST}" "$ROSTER_RATE" "$_s"
    done
}

# write_roster_state replaces six functions this branch used to need --
# create_repo_branch, write_repo_file, open_repo_pr, enable_pr_auto_merge,
# branch_head_sha and dose-project.sh's roster_with_state -- which built a
# branch and a PR out of $ROSTER_CONTENT. That content is SYNTHESISED from
# this service now, so committing it back would fabricate the host/account
# columns the file no longer carries (#686). One POST does the whole job.
ROSTER_WRITE_TOKEN_PATH="${DOSE_ROSTER_WRITE_TOKEN:-/etc/scheduler/roster-write.token}"

write_roster_state() {  # <project> <state> -- POST, then GET to confirm (#686)
  local project="${1:?write_roster_state needs a project}" state="${2:?needs a state}" token got
  [ -r "$ROSTER_WRITE_TOKEN_PATH" ] || {
    echo "BROKEN: no readable token at $ROSTER_WRITE_TOKEN_PATH -- cannot write the roster." >&2
    return 5; }
  token="$(cat "$ROSTER_WRITE_TOKEN_PATH")"
  [ -n "$token" ] || { echo "BROKEN: $ROSTER_WRITE_TOKEN_PATH is empty -- cannot write the roster." >&2; return 5; }
  command -v curl >/dev/null 2>&1 || { echo "BLIND: 'curl' is not on PATH -- cannot write the roster service." >&2; return 6; }
  curl -fsS --max-time 10 -X POST "$ROSTER_URL/roster/$project" \
    -H "X-Roster-Token: $token" -d "{\"state\":\"$state\",\"by\":\"$(id -un)@$HOST\"}" \
    >/dev/null 2>&1 || { echo "BLIND: POST to $ROSTER_URL/roster/$project did not reach the service -- nothing confirmed changed." >&2; return 6; }
  # A WRITE THAT REPORTS SUCCESS AND DID NOTHING is this estate's measured
  # failure mode (40% of the old PR-based writes never merged) -- re-reading,
  # not the POST's own exit code, is what answers "did it actually happen".
  command -v jq >/dev/null 2>&1 || { echo "BLIND: 'jq' is not on PATH -- wrote, but cannot confirm by re-reading." >&2; return 6; }
  got="$(curl -fsS --max-time 10 "$ROSTER_URL/roster/$project" 2>/dev/null | jq -r '.state // empty' 2>/dev/null)"
  [ "$got" = "$state" ] || {
    echo "BROKEN: posted state='$state' for '$project' but re-read gives '${got:-<none>}' -- verify failed." >&2
    return 5; }
  return 0
}

# runner_tag <schedule-dir> <host> -- dose-project.sh's do_live() RUNNER tag,
# shared so #305's audit can't compute a different one. Returns 5 if
# _runner.conf is missing or names no RUNNER_JOB.
runner_tag() {
  local sched_dir="${1:?runner_tag needs a schedule dir}" host="${2:?runner_tag needs a host}"
  local conf_path="$sched_dir/_runner.conf"
  [ -f "$conf_path" ] || return 5
  local conf job host_conf_path
  conf="$(cat "$conf_path")"
  job="$(grep -E '^RUNNER_JOB=' <<<"$conf" | tail -1 | sed -E 's/^RUNNER_JOB="?([^"]*)"?.*/\1/')"
  host_conf_path="$sched_dir/_runner.${host}.conf"
  if [ -f "$host_conf_path" ] && grep -qE '^RUNNER_JOB=' "$host_conf_path"; then
    job="$(grep -E '^RUNNER_JOB=' "$host_conf_path" | tail -1 | sed -E 's/^RUNNER_JOB="?([^"]*)"?.*/\1/')"
  fi
  [ -n "$job" ] || return 5
  printf '# scheduler:%s:RUNNER (usage-paced dispatch)' "$job"
}

# NOTHING BELOW THIS LINE MAY RUN AT SOURCE TIME. This file ended with
#   ROSTER_CONTENT="$(fetch_roster)" || exit $?
# from its extraction in hf7y/scheduler#120 until 2026-08-11, which made
# `. lib/dose-common.sh` do a NETWORK FETCH and, on failure, `exit` the
# CALLING process with dose's exit code. Caught when freeze-check.sh sourced it
# for fetch_repo_file and died with 6 (dose's BLIND) instead of its own
# contract's 2 (FROZEN) -- a library reaching past its caller's error handling.
# The fetch belongs to whoever wants the roster; see bin/dose-project.sh.
