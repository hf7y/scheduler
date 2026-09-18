#!/usr/bin/env bash
# served-build-consumer-check.sh -- before you delete it, does the SERVED
# build still read it?
#
# hf7y/realisateur#1143. schedule/ROSTER was ripped out in #716 because
# `main`'s lib/dose-common.sh had moved to the roster SERVICE and the file
# looked dead. It was dead on `main` and load-bearing on every host, because
# the build the fleet actually dispatches from (build 2026-09-07T031807Z)
# still carried the old `fetch_roster() { fetch_repo_file schedule/ROSTER; }`.
# That build was a month behind `main` -- the ordinary gap the 30-day release
# cadence plus two Zach-gated approvals leaves standing -- and nothing before
# #716 asked the one question that would have caught it: "does the build
# people are actually running still reference this?" #718 reverted it.
#
# THE BUILD THIS CHECKS is never this checkout. `main` and the served build
# are allowed to disagree -- that disagreement is the whole reason a release
# channel exists -- so this never compares against git. It greps the one tree
# dose-project.sh and land-selfdev.sh (hf7y/realisateur) already agree is the
# fleet's actual answer to "what are we running":
#   ${VERB_HOST_BUILD_ROOT:-/usr/local/share/verb-builds}/current/scheduler
# (DOSE_BUILD_ROOT in bin/dose-project.sh, SCHEDULER_BUILD_ROOT in
# realisateur's bin/land-selfdev.sh -- one convention, not reinvented here.)
#
# THIS IS NOT bin/deploy-drift-check.sh. That script asks "does a locally
# INSTALLED WRAPPER under $DEPLOY_DIR still match what git says it should
# be" (symlink vs. stale copy, one host's PATH). This script asks "does the
# PINNED BUILD the whole fleet dispatches from still contain code that reads
# a thing I am about to delete from the repo" -- a repo-level deletion
# checked against a build that can be weeks behind, not a host's link
# hygiene. Different question, different tree, deliberately not merged.
#
# Read-only. Never modifies the served build, this checkout, or anything
# else. Offline-first: no network, no `claude` call -- same discipline as
# docs/offline-first-checks.md and bin/deploy-drift-check.sh.
#
# usage: served-build-consumer-check.sh <needle> [<needle> ...]
#   <needle>  a literal string to search for under the served build's tree --
#             typically the path you are about to delete (schedule/ROSTER),
#             and/or the name of a function/symbol that might read it
#             indirectly (fetch_roster). Plain substring match, not a regex;
#             a path with regex metacharacters is searched literally.
#
# exit: 0 CLEAR   -- served build has no reference to any needle
#       1 FOUND   -- served build still references at least one needle;
#                    REFUSE the deletion until a cut build drops it
#       2 USAGE   -- no needle given
#       6 BLIND   -- could not read the served build at all (wrong host, no
#                    build installed yet, permission denied, or the tree is
#                    empty). BLIND is never treated as CLEAR: "could not
#                    look" is not "nothing is wrong" (the #511 lesson).
set -uo pipefail

CLI_NAME="served-build-consumer-check.sh"
SCHED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVED_ROOT="${VERB_HOST_BUILD_ROOT:-/usr/local/share/verb-builds}/current/scheduler"

usage() {
  cat <<EOF
usage: $CLI_NAME <needle> [<needle> ...]

Checks whether the SERVED build (the one the fleet actually dispatches from,
not this checkout) still contains a reference to <needle> -- a path you are
about to delete, or a symbol name that might read it indirectly.

  \$VERB_HOST_BUILD_ROOT   override the verb-builds root (default
                          /usr/local/share/verb-builds); this script reads
                          \$VERB_HOST_BUILD_ROOT/current/scheduler, exactly
                          what bin/dose-project.sh calls DOSE_BUILD_ROOT.

exit: 0 clear  1 found (refuse)  2 usage  6 blind (could not check)
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ "$#" -ge 1 ] || { usage >&2; exit 2; }

# Runtime witness, first act, before any early exit -- a run that comes back
# BLIND still ran, and bin/check-witness-lint.sh needs to see that
# (docs/offline-first-checks.md, lib/check-witness.sh). Never fatal.
if [ -r "$SCHED_ROOT/lib/check-witness.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCHED_ROOT/lib/check-witness.sh"
  check_witness "$(basename "${BASH_SOURCE[0]}")"
fi

echo "$CLI_NAME -- $(date '+%Y-%m-%d %H:%M')"
echo "  served build: $SERVED_ROOT"

# "current" is a symlink dose-project.sh deliberately leaves UNRESOLVED in
# its own path variable (#350) so a crontab line never freezes today's dated
# build dir. Resolve it here only to NAME which build was actually checked,
# so a refusal states a fact ("build 2026-09-07T031807Z still reads this")
# rather than "the served build", which is a moving target.
CURRENT_LINK="$(dirname "$SERVED_ROOT")"
BUILD_ID=""
if [ -L "$CURRENT_LINK" ]; then
  BUILD_ID="$(basename "$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)" 2>/dev/null || true)"
fi
if [ -n "$BUILD_ID" ]; then
  echo "  build id:     $BUILD_ID (current -> $BUILD_ID)"
else
  echo "  build id:     (unresolved -- $CURRENT_LINK is not a symlink, or does not exist)"
fi

# THE CASE THIS EXISTS FOR: not present, not readable, or empty. Every one of
# these is "I could not look", and every one of them gets the SAME verdict --
# BLIND, never CLEAR -- because a wrong host or a bare box greps identically
# to a served build with nothing left to consume the needle, and only one of
# those means the deletion is actually safe.
if [ ! -d "$SERVED_ROOT" ]; then
  echo
  echo "BLIND: no served build at $SERVED_ROOT"
  echo "  this host has nothing installed there yet, or VERB_HOST_BUILD_ROOT points"
  echo "  elsewhere -- this is not evidence the deletion is safe, only that this"
  echo "  script could not check. Run it on a host that runs dispatch (dose-project.sh"
  echo "  reads the same path as DOSE_BUILD_ROOT), or point VERB_HOST_BUILD_ROOT at one."
  exit 6
fi
if [ ! -r "$SERVED_ROOT" ]; then
  echo
  echo "BLIND: $SERVED_ROOT exists but is not readable by $(id -un)"
  exit 6
fi

file_count="$(find "$SERVED_ROOT" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "${file_count:-0}" -eq 0 ]; then
  echo
  echo "BLIND: $SERVED_ROOT exists but contains no files"
  echo "  a served build with nothing in it is a discovery failure, not a clean"
  echo "  result -- dose-project.sh would refuse to dispatch against this too"
  exit 6
fi

echo "  files seen:   $file_count"
echo

found=0
for needle in "$@"; do
  # -F: literal substring, not a regex -- a path like "schedule/ROSTER" or a
  # bare symbol name should never be reinterpreted as a pattern.
  # -I: skip binaries; a served build carries none we care about, but a
  # stray one must never abort the whole scan.
  # -r: the served build is a plain copy, not necessarily a git checkout, so
  # this walks the filesystem tree, not git's index.
  hits="$(grep -rIFn -- "$needle" "$SERVED_ROOT" 2>/dev/null)" || true
  if [ -n "$hits" ]; then
    found=1
    echo "FOUND: '$needle' is still referenced in the served build${BUILD_ID:+ ($BUILD_ID)}:"
    printf '%s\n' "$hits" | sed 's/^/    /'
    echo
  else
    echo "clear: '$needle' -- no reference under $SERVED_ROOT"
  fi
done

echo
if [ "$found" -eq 1 ]; then
  echo "REFUSE: the served build still reads at least one needle above. Deleting it"
  echo "  from main now would repeat hf7y/realisateur#1143 (schedule/ROSTER, #716/#718):"
  echo "  dead on main, load-bearing on the fleet, discovered by an outage. Land the"
  echo "  consumer's fix in a CUT BUILD first, confirm this script reports clear"
  echo "  against the build that carries it, and only then remove the source."
  exit 1
fi
echo "CLEAR: no needle above is referenced in served build${BUILD_ID:+ $BUILD_ID}."
echo "  (this checks the served build ONLY -- it says nothing about whether"
echo "  another consumer on main still needs the file for a different reason)"
exit 0
