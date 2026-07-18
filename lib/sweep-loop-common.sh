#!/usr/bin/env bash
# Shared engine for per-project bug-sweep / nightly-batch loop scripts.
#
# A per-project wrapper sets the variables below, THEN sources this file
# (does not execute it directly) -- sourcing runs the actual
# lock/expiry/heartbeat/clone/invoke-claude logic using those variables.
# See ../examples/ for full per-project wrappers.
#
# This is extracted from two real, independently-written scripts
# (chezz-bug-sweep-loop.sh and vkv-inventory-bug-sweep-loop.sh) that
# turned out to be ~90% identical boilerplate -- the only genuine
# per-project differences were the repo URL, which subdirectory to cd
# into, the prompt text, and a couple of tunables. Everything else
# (lock file so overlapping cron fires no-op instead of racing, 7-day
# auto-expiry that removes its own crontab entry, a 24h heartbeat
# notification, log rotation, a dedicated clone that's safe to
# `reset --hard` because it's never the user's real working copy) is
# exactly the same logic either project needs, so it only needs to exist
# once.
#
# Required variables the wrapper must set before sourcing:
#   JOB_NAME       short, unique, matches this wrapper's own filename.
#                  Also names this job's state dir (~/.local/share/$JOB_NAME)
#                  and must match the SWEEP_JOB_NAME/BATCH_JOB_NAME field
#                  for this job in this project's ../schedule/<project>.conf
#                  entry -- that's how bin/sync-crontab.sh finds this job's
#                  expiry state (see EXPIRY_DAYS below) to prune its
#                  crontab line once expired. This script no longer edits
#                  crontab itself -- sync-crontab.sh is the only writer, so
#                  there's one place a job's schedule actually comes from.
#   PROJECT_KEY    short, unique PER PROJECT (not per job) -- e.g.
#                  "vkv-inventory". A project's Tier 1 bug-sweep and Tier 2
#                  nightly-batch wrappers have DIFFERENT JOB_NAMEs but the
#                  SAME PROJECT_KEY -- that shared key is what lets them
#                  detect and avoid each other (see the registry section
#                  below). Two different projects must never share one.
#   REPO_URL       git clone URL (SSH) for the dedicated clone
#   REPO_SUBDIR    subdirectory within the clone to cd into before
#                  invoking claude ("." if the project IS the repo root,
#                  e.g. vkv-inventory; something like "inv" if the
#                  command file lives one level down from the repo root)
#   PROMPT         the full prompt text to pass to `claude -p`
#
# Optional (sensible defaults given):
#   TIER           default "unspecified" -- free-form label ("bug-sweep",
#                  "nightly-batch", ...) recorded in the registry marker
#                  purely for the other tier's own log message and for
#                  bin/morning-report.sh; not used for any logic decision.
#   EXPIRY_DAYS    default 7
#   MAX_TURNS      default 40 (bug-sweep scale -- bump way up, e.g. 200,
#                  for a Tier 2 nightly-batch wrapper; see
#                  nightly-batch-loop.sh)
#   ALLOWED_TOOLS  default "Bash,Read,Write,Edit,Glob,Grep"
#   NODE_BIN_DIR   default /home/zach/.nvm/versions/node/v25.2.1/bin --
#                  wherever `claude` actually resolves from on this
#                  machine; cron's own PATH is minimal and won't find it
#                  otherwise
#   BRANCH         default "main" -- branch this job resets to and pushes
#                  against
#   SECRETS_SRC_DIR
#                  default unset (disabled). A local directory of
#                  non-git secrets (credentials, tokens, keypairs) that
#                  won't be present in a fresh `git clone` because
#                  they're gitignored by design, not by accident. If set,
#                  copied into the dedicated clone's $SECRETS_DEST_SUBDIR
#                  every run (not just on first clone), so a rotated
#                  credential is picked up without editing this wrapper.
#                  `git reset --hard` never touches untracked files, so
#                  this is safe to copy in before it runs. Pattern
#                  originated in home-assistant's real wrapper (it
#                  hand-rolled this ahead of sourcing this file before
#                  this option existed -- worth migrating once confirmed).
#   SECRETS_DEST_SUBDIR
#                  default ".session-handoff" -- subdirectory of the
#                  clone SECRETS_SRC_DIR's contents get copied into.
#   PRECHECK_CMD   default unset (always runs). A cheap shell command
#                  (evaluated after the clone/checkout/reset below, so it
#                  can inspect fresh repo state) that should exit 0 if
#                  there's real work to consider and non-zero if this run
#                  can be skipped without invoking `claude -p` at all --
#                  e.g. "nothing changed in the tracker or FOCUS.md since
#                  last time." Exists because a full nightly-batch turn
#                  budget isn't free even on a night with nothing to do;
#                  see README's "Cost of an idle run" section. Opt-in --
#                  no existing wrapper sets this yet.

set -uo pipefail

: "${JOB_NAME:?sweep-loop-common.sh: JOB_NAME must be set before sourcing}"
: "${PROJECT_KEY:?sweep-loop-common.sh: PROJECT_KEY must be set before sourcing}"
: "${REPO_URL:?sweep-loop-common.sh: REPO_URL must be set before sourcing}"
: "${REPO_SUBDIR:=.}"
: "${PROMPT:?sweep-loop-common.sh: PROMPT must be set before sourcing}"
: "${TIER:=unspecified}"
: "${EXPIRY_DAYS:=7}"
: "${MAX_TURNS:=40}"
: "${ALLOWED_TOOLS:=Bash,Read,Write,Edit,Glob,Grep}"
: "${NODE_BIN_DIR:=/home/zach/.nvm/versions/node/v25.2.1/bin}"
: "${BRANCH:=main}"
: "${SECRETS_SRC_DIR:=}"
: "${SECRETS_DEST_SUBDIR:=.session-handoff}"
: "${PRECHECK_CMD:=}"

STATE_DIR="/home/zach/.local/share/${JOB_NAME}"
REPO="$STATE_DIR/repo"
LOG="$STATE_DIR/sweep.log"
LOCK="$STATE_DIR/sweep.lock"
EXPIRES_AT_FILE="$STATE_DIR/expires_at"
HEARTBEAT_FILE="$STATE_DIR/last_heartbeat"

# Cross-job, cross-tier registry -- one directory shared by EVERY project's
# EVERY job, not per-job like STATE_DIR above. $LOCK (above) only stops
# THIS SAME SCRIPT from double-running if one invocation runs long; it
# does nothing to stop a project's bug-sweep and nightly-batch (different
# scripts, different JOB_NAMEs) from firing at the same time and both
# doing `git reset --hard` + commit + push against the SAME repo --
# whichever pushes second silently clobbers or conflicts with the other.
# Keying this second lock by PROJECT_KEY instead of JOB_NAME is what makes
# every tier/job for one project contend for the same slot.
REGISTRY_DIR="/home/zach/.local/share/scheduler-registry"
REGISTRY_LOCK="$REGISTRY_DIR/${PROJECT_KEY}.lock"
REGISTRY_MARKER="$REGISTRY_DIR/${PROJECT_KEY}.active"

export PATH="${NODE_BIN_DIR}:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

mkdir -p "$STATE_DIR" "$REGISTRY_DIR"

exec 200>"$LOCK"
if ! flock -n 200; then
  echo "$(date -Is) already running, skipping" >> "$LOG"
  exit 0
fi

exec 201>"$REGISTRY_LOCK"
if ! flock -n 201; then
  OTHER="$(cat "$REGISTRY_MARKER" 2>/dev/null || echo 'unknown job')"
  echo "$(date -Is) project '$PROJECT_KEY' already has an active job ($OTHER) -- skipping this run to avoid a concurrent-push conflict" >> "$LOG"
  exit 0
fi
echo "{\"job\":\"$JOB_NAME\",\"tier\":\"$TIER\",\"started_at\":\"$(date -Is)\",\"pid\":$$}" > "$REGISTRY_MARKER"
trap 'rm -f "$REGISTRY_MARKER"' EXIT

if [ -f "$LOG" ]; then
  tail -n 4000 "$LOG" > "$LOG.tmp"
  mv "$LOG.tmp" "$LOG"
fi

# Dedicated clone, never the user's real working copy -- reset --hard
# below would destroy uncommitted work if pointed at a real checkout.
if [ ! -d "$REPO/.git" ]; then
  git clone "$REPO_URL" "$REPO" >> "$LOG" 2>&1
fi

if [ -n "$SECRETS_SRC_DIR" ]; then
  mkdir -p "$REPO/$SECRETS_DEST_SUBDIR"
  cp -f "$SECRETS_SRC_DIR"/* "$REPO/$SECRETS_DEST_SUBDIR/" 2>/dev/null || true
fi

if [ ! -f "$EXPIRES_AT_FILE" ]; then
  date -d "+${EXPIRY_DAYS} days" -Is > "$EXPIRES_AT_FILE"
fi
EXPIRES_AT=$(cat "$EXPIRES_AT_FILE")
NOW_IS=$(date -Is)

if [[ "$NOW_IS" > "$EXPIRES_AT" ]]; then
  MSG="Auto-disabled after ${EXPIRY_DAYS} days. Bump EXPIRY_DAYS (or re-run setup) and re-run bin/sync-crontab.sh to renew."
  notify-send "$JOB_NAME" "$MSG"
  echo "$NOW_IS expired -- no-op this run; ../bin/sync-crontab.sh prunes this job's crontab line on its next run, this script does not touch crontab itself" >> "$LOG"
  exit 0
fi

NOW_EPOCH=$(date +%s)
LAST_HEARTBEAT_EPOCH=0
if [ -f "$HEARTBEAT_FILE" ]; then
  LAST_HEARTBEAT_EPOCH=$(cat "$HEARTBEAT_FILE")
fi
SECONDS_SINCE=$((NOW_EPOCH - LAST_HEARTBEAT_EPOCH))

if [ "$SECONDS_SINCE" -ge 86400 ]; then
  notify-send "$JOB_NAME" "Still running. Expires $EXPIRES_AT."
  echo "$NOW_EPOCH" > "$HEARTBEAT_FILE"
fi

{
  START_TS=$(date +%s)
  echo "=== $(date -Is) ==="
  cd "$REPO/$REPO_SUBDIR"
  git checkout "$BRANCH"
  git fetch origin --quiet
  git reset --hard "origin/$BRANCH"
  BEFORE_SHA=$(git rev-parse HEAD)
  echo "start commit: $BEFORE_SHA"

  if [ -n "$PRECHECK_CMD" ] && ! eval "$PRECHECK_CMD"; then
    echo "precheck said nothing to do -- skipping claude invocation this run"
    STATUS="skipped (precheck)"
  elif claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --max-turns "$MAX_TURNS"; then
    STATUS="done"
  else
    STATUS="FAILED"
  fi

  # Objective, tool-verified facts about what actually happened -- not
  # relying solely on the agent's own summary prose being accurate or
  # consistently formatted (this check originated in chezz's own script,
  # independently, before this library existed). Compares local HEAD
  # against the *remote's* HEAD (not just "did local HEAD move"), so a
  # commit made locally but never actually pushed (e.g. an SSH/auth
  # failure mid-run) shows up as a distinct WARNING instead of silently
  # reading as "pushed".
  AFTER_SHA=$(git rev-parse HEAD)
  REMOTE_SHA=$(git ls-remote origin -h "refs/heads/$BRANCH" | cut -f1)
  ELAPSED=$(( $(date +%s) - START_TS ))

  if [ "$AFTER_SHA" = "$BEFORE_SHA" ]; then
    echo "pushed: no -- no new commits this run"
  elif [ "$AFTER_SHA" = "$REMOTE_SHA" ]; then
    echo "pushed: yes -- $BEFORE_SHA -> $AFTER_SHA"
    git log --oneline "$BEFORE_SHA..$AFTER_SHA"
  else
    echo "WARNING: local commit made but NOT pushed to origin (local=$AFTER_SHA remote=$REMOTE_SHA)"
  fi

  echo "=== $STATUS $(date -Is) (${ELAPSED}s) ==="

  if [ "$STATUS" = "FAILED" ]; then
    notify-send -u critical "$JOB_NAME FAILED" "See log: $LOG"
  fi
} >> "$LOG" 2>&1
