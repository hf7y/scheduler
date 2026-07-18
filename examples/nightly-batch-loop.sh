#!/usr/bin/env bash
# Example: Tier 2 (overnight batch) wrapper on the same shared library as
# Tier 1's bug-sweep wrappers -- generalizes
# ~/Documents/vkv/inv/schedule-drilldown-wakeup.sh's one-off `at` pattern
# into a real recurring script. Same engine, different knobs: a much
# higher MAX_TURNS (this tier is meant to run long), and a PROMPT that
# reads the project's own FOCUS.md first instead of a fixed /bug-sweep
# invocation.
#
# NOT wired up anywhere yet. To actually use: copy this per project,
# fill in the config block, add a REAL .claude/commands/nightly-batch.md
# (see ../examples/nightly-batch.md.template) and a REAL .claude/FOCUS.md
# (see ../examples/FOCUS.md.template) to that project's repo, then add a
# crontab entry (see README.md's "Open decisions" for timing).

JOB_NAME="vkv-inventory-nightly-batch"
PROJECT_KEY="vkv-inventory"  # SAME key as the bug-sweep wrapper's vkv-inventory copy --
                              # if this run is still active past the sweeper's window
                              # opening, the sweeper detects it and skips instead of
                              # racing a second `reset --hard`/push against this clone.
TIER="nightly-batch"
REPO_URL="git@github.com:media-arts-collective/inventory-app.git"
REPO_SUBDIR="."
EXPIRY_DAYS=7
MAX_TURNS=200

PROMPT="/nightly-batch

This is a fully unattended overnight run with no human review step.
Read .claude/FOCUS.md FIRST -- everything you do tonight is scoped by
that file. An accumulated feature idea or report that is not in service
of the current focus should be written up as deferred in tonight's
report, not implemented, no matter how easy it looks.

Write your report to ~/reports/vkv-inventory/$(date +%Y-%m-%d).md and
update ~/reports/vkv-inventory/LATEST.md to match it, so it is a 30-second
read the next time this machine boots up, covering: what shipped, what
broke and got fixed, what was deliberately deferred and why, and any open
questions that need a human decision. Confirm everything is committed and
pushed to the branch before finishing -- an overnight run that isn't
saved anywhere didn't happen."

source "$(dirname "$0")/../lib/sweep-loop-common.sh"
