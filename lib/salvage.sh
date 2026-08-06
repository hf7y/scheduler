#!/usr/bin/env bash
# salvage.sh -- put a scheduled job's workspace on origin's state WITHOUT
# destroying anything a previous run left behind.
#
# Replaces `git stash push -u` + `git branch rescue/...` + `git reset --hard`
# (lib/sweep-loop-common.sh, until 2026-08-06). Those preserved work LOCALLY,
# and local was the bug: in a disposable clone the stash and the rescue ref
# died with the directory, and in any checkout they are invisible to
# everything that counts work -- no branch list, no PR, no issue, no report.
# ecosim's auto-stash held PARADIGM 4 (verdict designs), a supervisor
# history-loss fix and 87 lines of tests, and sat unread for days because
# nothing in the system had a reason to look in a stash.
#
# The rule here is: preserve where it can be SEEN (a branch on origin), and
# treat a failure to preserve as a reason to STOP, not to proceed. No
# discarding step runs until `git push` has said yes.
#
# Extracted into its own lib so it has a witness (tests/salvage-witness.sh).
# The old inline version could only be exercised by running a whole nightly
# batch, which is why "reset --hard eats work" was a story told in comments
# rather than a case that fails a test.
#
# SECRETS. A salvage branch is PUSHED, so anything it sweeps up becomes
# public-to-the-remote. The engine copies SECRETS_SRC_DIR into
# $REPO/$SECRETS_DEST_SUBDIR inside the workspace, and with the disposable
# clone retired that directory now SURVIVES between runs, sitting in the tree
# looking exactly like uncommitted work. `git add -A` would commit it and
# `git push` would publish it. So the caller passes those paths in
# SALVAGE_EXCLUDE and they are excluded from BOTH the detection and the
# commit -- excluding only the commit would leave every run seeing a dirty
# tree and salvaging an empty branch forever.
#
# Usage:  salvage_then_restore <branch> <label> [log_fn]
#   cwd must already be the workspace.
#   SALVAGE_EXCLUDE  optional space-separated list of repo-relative paths
#                    that must never be salvaged (no spaces in the paths).
#   Returns:
#     0  workspace is at origin/<branch>; SALVAGE_REF is set if work was saved
#     1  nothing was discarded, and the caller must abort (see SALVAGE_ERROR)
# The caller owns notification -- this lib does not know what `notify` means.

# shellcheck disable=SC2034
SALVAGE_REF=""
SALVAGE_ERROR=""
: "${SALVAGE_EXCLUDE:=}"

salvage_then_restore() {
  local branch="$1" label="$2" log_fn="${3:-echo}"
  SALVAGE_REF=""
  SALVAGE_ERROR=""

  if ! git rev-parse --verify --quiet "origin/$branch" >/dev/null; then
    SALVAGE_ERROR="origin/$branch does not exist -- refusing to guess a base"
    return 1
  fi

  # Build the pathspec once and use it for BOTH detection and staging.
  local -a scope=(--)
  local p
  scope+=(".")
  for p in ${SALVAGE_EXCLUDE:-}; do
    scope+=(":(exclude)$p")
  done

  local working_state ahead changed ref
  working_state="$(git status --porcelain "${scope[@]}" 2>/dev/null)"
  ahead="$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)"

  if [ -n "$working_state" ] || [ "$ahead" -gt 0 ]; then
    changed="$(printf '%s\n' "$working_state" | grep -c .)"
    ref="salvage/${label}-$(date +%Y%m%d%H%M%S)"
    "$log_fn" "WARNING: previous run left work behind ($ahead unpushed commit(s), $changed changed path(s)) -- salvaging to '$ref' before restoring to origin/$branch"

    if ! git checkout -b "$ref" >/dev/null 2>&1; then
      SALVAGE_ERROR="cannot create salvage branch '$ref' -- workspace left UNTOUCHED, nothing discarded"
      return 1
    fi
    if [ -n "$working_state" ]; then
      # -A is correct HERE specifically: this workspace has no other writer
      # (a human editing it defers the whole run via registry_should_defer),
      # and .gitignore still applies, so build debris does not ride along.
      git add -A "${scope[@]}"
      git commit -q -m "salvage: uncommitted work found by $label at $(date -Is)"
    fi
    if ! git push -u origin "$ref" >/dev/null 2>&1; then
      SALVAGE_ERROR="could not push salvage branch '$ref' -- the workspace is left ON that branch with the work intact; NOTHING was discarded. Push it by hand, or delete the branch once it is judged worthless."
      return 1
    fi
    SALVAGE_REF="$ref"
    "$log_fn" "salvaged: origin/$ref -- review it; this run continues from origin/$branch"
  fi

  # Only now, with anything worth keeping visible on origin, move the
  # workspace onto origin's state.
  if ! git checkout -B "$branch" "origin/$branch" >/dev/null 2>&1; then
    SALVAGE_ERROR="cannot put '$branch' at origin/$branch -- aborting before any claude work"
    return 1
  fi
  return 0
}
