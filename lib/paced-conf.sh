#!/usr/bin/env bash
# lib/paced-conf.sh -- WHICH ROTATION FILE DOES THIS HOST ACTUALLY RUN?
#
# Two hosts (mandark, dexter) execute bin/usage-paced-runner.sh out of one
# git-tracked repo, and each MAY own its own participants file:
#
#   schedule/_paced.<short-hostname>.conf   this host's rotation, if present
#   schedule/_paced.conf                    shared/default, used otherwise
#
# The rule itself is documented at length in bin/usage-paced-runner.sh under
# "which participants file". This file exists because the rule had ONE
# implementation and TWO callers who needed it.
#
# THE BUG THIS RETIRES: bin/scheduler (the human front door) once hardcoded
# schedule/_paced.conf with no host resolution, while the runner beside it
# did -- so on dexter it answered "not a participant" about the one project
# dexter's rotation had enabled, and its edit-and-commit path (`scheduler
# weight <p> <n>`) wrote into MANDARK's rotation while the operator believed
# they were retuning dexter's, the exact cross-host write the per-host split
# exists to make impossible. Full account in tests/paced-conf-witness.sh's
# own header.
#
# So: one resolver, sourced by the front door, and tests/paced-conf-witness.sh
# asserts the runner's inline copy still agrees with it. Drift fails loud
# instead of quietly answering about the wrong machine.
#
# WHY THE RUNNER STILL HAS AN INLINE COPY rather than sourcing this: it is the
# live */5 dispatcher for every project in the ecosystem, and a `source` is a
# new way for it to die outright (bad path, partial checkout, mid-pull tree).
# It resolves its conf before it has established anything it could safely
# source from. Keeping its copy inline and MECHANIZING the agreement is the
# cheaper trade -- the witness is what makes that an engineering decision
# instead of a second source of truth nobody rechecks.
#
# Usage:
#   source lib/paced-conf.sh
#   resolve_paced_conf "$REPO_ROOT" || <refuse loudly>
#   # sets: PACED_CONF (path), PACED_CONF_SRC (why that path), PACED_HOST
#
# Honors an explicit PACED_CONF in the environment, same as the runner, so a
# test or a one-off can point every consumer at one file at once.

# resolve_paced_conf <repo-root>
#   Sets PACED_CONF / PACED_CONF_SRC / PACED_HOST. Returns 0 when a real file
#   was resolved, 1 when none exists -- and on that path PACED_CONF is left
#   EMPTY on purpose, so a caller that ignores the return code fails on a
#   missing file rather than silently reading a plausible-looking default.
resolve_paced_conf() {
  local repo_root="${1:-}"
  if [ -z "$repo_root" ]; then
    PACED_CONF=""
    PACED_CONF_SRC="NONE -- resolve_paced_conf called with no repo root"
    return 1
  fi
  PACED_HOST="${PACED_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}"
  if [ -n "${PACED_CONF:-}" ]; then
    PACED_CONF_SRC="explicit PACED_CONF"
  elif [ -f "$repo_root/schedule/_paced.$PACED_HOST.conf" ]; then
    PACED_CONF="$repo_root/schedule/_paced.$PACED_HOST.conf"
    PACED_CONF_SRC="host-scoped for $PACED_HOST"
  elif [ -f "$repo_root/schedule/_paced.conf" ]; then
    PACED_CONF="$repo_root/schedule/_paced.conf"
    PACED_CONF_SRC="shared (no _paced.$PACED_HOST.conf)"
  else
    PACED_CONF=""
    PACED_CONF_SRC="NONE -- neither _paced.$PACED_HOST.conf nor _paced.conf under $repo_root/schedule"
    return 1
  fi
  return 0
}

# paced_membership_set <repo-root>
#   Sets PACED_MEMBERS -- the space-delimited union of participant names
#   across EVERY host's rotation file (schedule/_paced.conf and every
#   schedule/_paced.<host>.conf), and PACED_MEMBERS_SRC naming the files it
#   read. Returns 1 when no rotation file exists at all, and on that path
#   PACED_MEMBERS is left as the empty marker " " on purpose -- same reason
#   resolve_paced_conf blanks PACED_CONF.
#
# WHY A UNION RATHER THAN THIS HOST'S FILE, and it is the whole point of the
# function. There are two DIFFERENT questions a caller can be asking:
#
#   "does the paced system own this project's Tier 2?"   -> membership, UNION
#   "does it dispatch HERE, as this account, right now?" -> resolve_paced_conf
#
# The first decides whether to install a FIXED nightly cron line, and
# answering it per-host is wrong in both directions: a project enabled on one
# host but not the other would either get a second, redundant dispatcher
# installed on the host that doesn't own it, or have its fixed line silently
# re-armed on the host that no longer does -- restoring a second writer of
# that project's git history, the exact hazard the per-host split exists to
# prevent.
#
# One host means one thing (resolve_paced_conf). "Somebody's runner owns
# this" is an ecosystem-wide fact, so it reads ecosystem-wide.
#
# The union direction is also the SAFE one for a crontab writer: it is a
# superset of what the old hardcoded read produced, so switching to it can
# only ever suppress a line that used to be emitted -- it can never arm a
# cron line that was not there before.
paced_membership_set() {
  local repo_root="${1:-}"
  PACED_MEMBERS=" "
  if [ -z "$repo_root" ]; then
    PACED_MEMBERS_SRC="NONE -- paced_membership_set called with no repo root"
    return 1
  fi
  local -a files=()
  local f
  # Explicit PACED_CONF wins outright, same override resolve_paced_conf
  # honors, so a test can point every consumer at one file at once.
  if [ -n "${PACED_CONF:-}" ]; then
    files=("$PACED_CONF")
  else
    shopt -s nullglob
    for f in "$repo_root"/schedule/_paced.conf "$repo_root"/schedule/_paced.*.conf; do
      [ -f "$f" ] && files+=("$f")
    done
    shopt -u nullglob
  fi
  if [ "${#files[@]}" -eq 0 ]; then
    PACED_MEMBERS_SRC="NONE -- no schedule/_paced*.conf under $repo_root/schedule"
    return 1
  fi
  local pname
  for f in "${files[@]}"; do
    while IFS='|' read -r pname _ || [ -n "$pname" ]; do
      # A COMMENTED-OUT line is not a participant -- `#scheduler|1|3|...`
      # means the rotation no longer owns it, which is exactly the
      # documented rollback path back to a fixed nightly cron line.
      case "$pname" in ''|\#*) continue ;; esac
      pname="${pname// /}"
      [ -n "$pname" ] || continue
      case "$PACED_MEMBERS" in *" $pname "*) continue ;; esac
      PACED_MEMBERS+="$pname "
    done < "$f"
  done
  PACED_MEMBERS_SRC="union of ${files[*]}"
  return 0
}
