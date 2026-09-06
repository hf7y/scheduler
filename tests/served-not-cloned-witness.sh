#!/usr/bin/env bash
# served-not-cloned-witness.sh -- a v2 dispatch entry point takes its repo as
# an ARGUMENT, never a fact derived from its own filesystem or its caller's
# identity (hf7y/scheduler#306).
#
# HISTORY. bin/served-not-cloned.sh enforced "a host is SERVED, not cloned"
# until it was deleted 2026-08-22 (#511), two days before its own declared
# sunset -- against a rule fourteen accounts were violating at that moment.
# This restores the one assertion of the three in #306 that is checkable
# without the v2 scratch worker #304 stands up: "the dispatch entry point
# refuses when given no repo argument, rather than falling back to $USER,
# $HOME, or basename $PWD." That fallback is exactly how a rename could pass
# this test by accident, which is why #306 says test (3) -- the same worker
# dispatched at two different repos -- is worth more than this one. Add it
# here once #304 lands a scratch repo to point a second dispatch at.
#
# NOT A V1 ALARM (#306's own instruction): this checks the entry points
# scripts/humans call directly, not whether any of the 15 live accounts
# still clone -- that would fire daily against every account for a rule the
# project already knows it is mid-migration on.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/witness-common.sh"
echo "served-not-cloned-witness"

# A hostile identity: a $USER/$HOME/$PWD that, if any of the three fallbacks
# #306 names were live, would derive a DIFFERENT (and wrong) project name
# than the caller meant -- rather than refusing.
FAKE_HOME="$(mktemp -d)"; trap 'rm -rf "$FAKE_HOME"' EXIT
FAKE_USER="totally-not-a-project-$$"

check_refuses_with_no_repo_arg() {  # <label> <script> [extra args...]
  local label="$1" script="$2"; shift 2
  local out rc out2 rc2

  out="$(cd "$REPO_ROOT" && "$script" "$@" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "$label: exits nonzero ($rc) with no repo argument" \
    || bad "$label: exited 0 with no repo argument -- it dispatched SOMETHING"

  # Same call, under an identity that would name a real-looking project if
  # $USER, $HOME or `basename $PWD` were consulted as a fallback.
  out2="$(cd /tmp && HOME="$FAKE_HOME" USER="$FAKE_USER" LOGNAME="$FAKE_USER" "$script" "$@" 2>&1)"; rc2=$?
  [ "$rc2" -ne 0 ] && ok "$label: still refuses under a hostile \$USER/\$HOME/\$PWD" \
    || bad "$label: exited 0 under a hostile identity -- it derived a project instead of refusing"

  grep -qF "$FAKE_USER" <<<"$out2" && bad "$label: leaked the hostile \$USER into its output -- it read \$USER for the repo" \
    || ok "$label: never reads \$USER as a repo name"
}

check_refuses_with_no_repo_arg "bin/scheduler-run" "$REPO_ROOT/bin/scheduler-run"
check_refuses_with_no_repo_arg "bin/dose-project.sh" "$REPO_ROOT/bin/dose-project.sh"

# Structural guard: no fallback assignment of the form PROJECT=${1:-$USER} /
# ${1:-$(basename "$PWD")} / PROJECT="$USER" anywhere in either entry point.
# Belt-and-suspenders for the behavioural checks above -- this is what would
# have caught #511 as a diff, not just as a live failure three weeks later.
for f in bin/scheduler-run bin/dose-project.sh; do
  if grep -nE '\$\{?1?:?-\$(USER|LOGNAME)\}?|PROJECT="?\$(USER|LOGNAME)"?|basename "?\$(PWD|HOME)"?' "$REPO_ROOT/$f" | grep -q .; then
    bad "$f: contains a literal \$USER/\$LOGNAME/\$PWD/\$HOME fallback pattern"
  else
    ok "$f: no \$USER/\$LOGNAME/\$PWD/\$HOME fallback pattern in source"
  fi
done

printf '\nserved-not-cloned-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
