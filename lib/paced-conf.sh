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
# THE BUG THIS RETIRES (found 2026-07-29 on dexter, live):
# bin/scheduler -- the human front door -- hardcoded
# "$SCHED_ROOT/schedule/_paced.conf" and had no host resolution at all, while
# the runner beside it did. Its own comment claimed `next`/`run`/`weight`
# "stay in lockstep with what the real runner will actually do -- no second
# source of truth for this parsing". The PARSING was in lockstep. The FILE
# SELECTION was not, and nothing said so. On dexter that produced:
#
#   $ scheduler weight scheduler
#   scheduler: 'scheduler' is not a participant in .../schedule/_paced.conf
#
# ...about the one project that IS enabled in dexter's rotation, and the only
# project whose self-dev dexter now owns outright (58d6495). `scheduler weight
# crt` answered "weight=3 enabled=0" from mandark's file where dexter's says
# `crt|0|0`. Worst of the three: `scheduler weight <p> <n>` EDITS AND COMMITS
# $PACED_CONF, so on dexter it rewrote MANDARK's rotation while the operator
# believed they were retuning dexter's -- a cross-host write, which is the
# exact two-writer hazard the per-host split was introduced to make
# structurally impossible.
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
