#!/usr/bin/env bash
# Example: what the REAL script at
# ~/.local/bin/vkv-inventory-bug-sweep-loop.sh (currently ~97 lines,
# hand-duplicating the same engine as chezz's own loop script) would look
# like rewritten on top of ../lib/sweep-loop-common.sh. Everything below
# is project-specific config -- the actual lock/expiry/heartbeat/clone/
# invoke logic lives in the shared library, once.
#
# This file is NOT wired up anywhere -- it's a side-by-side comparison
# against the real, currently-duplicated version. To actually adopt this
# shape: replace the real script's contents with something like this,
# pointed at the real path to sweep-loop-common.sh.

JOB_NAME="vkv-inventory-bug-sweep"
PROJECT_KEY="vkv-inventory"  # SAME key as nightly-batch-loop.sh's vkv-inventory copy --
                              # that's what lets them detect and skip around each other.
TIER="bug-sweep"
REPO_URL="git@github.com:media-arts-collective/inventory-app.git"
REPO_SUBDIR="."
MAX_TURNS=40

PROMPT="/bug-sweep

This is a fully unattended run with no human review step. Once you've
committed your fixes and pushed to origin/main, deploy them per
DEV_DEPLOYMENT_ID at the top of .claude/commands/bug-sweep.md (this repo
is itself a fork, not the real production app -- that ID is confirmed
fine to deploy to directly, not something to avoid). Never resolve or
reclassify a report you are not confident about; leave it open with a
note instead, per the command file's own guidance."

source "$(dirname "$0")/../lib/sweep-loop-common.sh"
