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
#   MODEL          default unset -- pass a specific model id to `claude
#                  -p --model` (e.g. "claude-sonnet-5" for a mechanical
#                  bug sweep, instead of whatever the CLI default is).
#                  Unset means no --model flag (CLI default), so this is
#                  backward-compatible. Pair it with PRECHECK_CMD (below):
#                  the precheck cuts HOW OFTEN claude runs, MODEL cuts what
#                  each run costs.
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
: "${MODEL:=}"
: "${ALLOWED_TOOLS:=Bash,Read,Write,Edit,Glob,Grep}"
: "${NODE_BIN_DIR:=/home/zach/.nvm/versions/node/v25.2.1/bin}"
# Empty = resolve from origin's own default HEAD after the clone (below),
# NOT the literal string "main". Hardcoding "main" silently half-broke
# every home-assistant run for weeks: baudin's only branch is master, so
# `git checkout main` and `git reset --hard origin/main` both failed --
# unchecked -- the reset-to-origin guarantee quietly did not apply, the
# push check misread the missing ref as an SSH/auth failure, and one run
# summarized itself as "committed, pushed, and in sync" with a commit
# still sitting unpushed. A wrapper may still set BRANCH explicitly
# (aedile's dated aedile-nightly/<date>, scheduler's nightly/<date>);
# this only changes what happens when it says nothing.
: "${BRANCH:=}"
: "${SECRETS_SRC_DIR:=}"
: "${SECRETS_DEST_SUBDIR:=.session-handoff}"
: "${PRECHECK_CMD:=}"
#   AUTONOMY_TIER  default unset. "high" turns on lib/autonomy-merge.sh's
#                  test-gated auto-merge at the end of this run (see that
#                  file). Anything else (including unset) leaves branches
#                  for manual review, today's existing behavior, unchanged.
#                  bin/scheduler-run exports this from the conf directly.
#                  A legacy *_SCRIPT wrapper never sources the conf, so it
#                  won't be set here -- this file falls back to reading
#                  schedule/<PROJECT_KEY>.conf itself, below, rather than
#                  requiring every wrapper to be edited to pass it through.
#   TEST_CMD       default unset (ungated merge). Optional shell command,
#                  eval'd on each candidate branch before autonomy-merge
#                  will touch it; non-zero exit leaves that branch alone.
: "${AUTONOMY_TIER:=}"
: "${TEST_CMD:=}"
LIB_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$LIB_DIR_EARLY/autonomy-merge.sh"
if [ -z "$AUTONOMY_TIER" ] && [ -n "${PROJECT_KEY:-}" ]; then
  LEGACY_CONF="$LIB_DIR_EARLY/../schedule/$PROJECT_KEY.conf"
  if [ -f "$LEGACY_CONF" ]; then
    AUTONOMY_TIER="$(grep -E '^AUTONOMY_TIER=' "$LEGACY_CONF" | tail -1 | sed -E 's/^AUTONOMY_TIER=//; s/^"(.*)"$/\1/')"
    : "${PREFIX:=}"
    if [ -z "$PREFIX" ]; then
      case "$TIER" in
        nightly-batch|batch) PREFIX="BATCH" ;;
        bug-sweep|sweep) PREFIX="SWEEP" ;;
      esac
    fi
    if [ -n "$PREFIX" ]; then
      TEST_CMD="$(grep -E "^${PREFIX}_TEST_CMD=" "$LEGACY_CONF" | tail -1 | sed -E "s/^${PREFIX}_TEST_CMD=//; s/^\"(.*)\"\$/\1/")"
    fi
  fi
fi

STATE_DIR="$HOME/.local/share/${JOB_NAME}"
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
REGISTRY_DIR="$HOME/.local/share/scheduler-registry"
REGISTRY_LOCK="$REGISTRY_DIR/${PROJECT_KEY}.lock"
REGISTRY_MARKER="$REGISTRY_DIR/${PROJECT_KEY}.active"

export PATH="${NODE_BIN_DIR}:$PATH"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

mkdir -p "$STATE_DIR" "$REGISTRY_DIR"

# Every notification in this engine goes through here (q-756f82, closed
# 2026-07-28). `notify-send ... 2>/dev/null || true` guards a notify-send
# that FAILS; it does nothing about one that NEVER RETURNS, and those are
# different. Found live 2026-07-28 in lib/deadman-switch.sh:82 under
# svc-vaporwave: the dbus socket at $XDG_RUNTIME_DIR/bus exists but nothing
# is listening, so notify-send blocked forever and hung the run that
# sourced it. This engine exports DBUS_SESSION_BUS_ADDRESS unconditionally
# (line 177) for EVERY job, cron or not, so it points at that same socket
# on any account without a live desktop session -- the cron path is not
# immune, it just hasn't drawn the short straw yet. A wedged notify-send
# here is worse than there: this one holds $LOCK and the registry marker,
# so it blocks the project's other tier too.
#
# The notification is best-effort garnish and must never wedge the job it
# decorates -- but a dropped one is not allowed to be silent either, so
# the timeout case (rc 124) says so in the log.
notify() {
  local rc=0
  timeout 5 notify-send "$@" 2>/dev/null || rc=$?
  if [ "$rc" = "124" ]; then
    echo "$(date -Is) WARNING: notify-send timed out after 5s (dbus socket present but unanswered, or a hung notification daemon) -- notification DROPPED: $*" >> "$LOG"
  fi
  return 0
}

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
# ---- job vs. HUMAN --------------------------------------------------------
# The two flocks above are job-vs-job. This is the other half: is a person
# editing this project right now? $REGISTRY_DIR/<PROJECT_KEY>.interactive is
# written by realisateur/bin/session-marker.sh (a Claude session started under
# this project's repo) and by bin/scheduler's front door (you opened one of
# this project's .md files through `scheduler -q/-f/-r`). Same directory as
# .active on purpose -- one place answers "is anything writing to this project
# right now."
#
# LIVENESS IS A PID PROBE, never the file's existence. Neither writer can
# guarantee a clean release (SessionEnd is not guaranteed on crash; an editor
# can be SIGKILLed), so trusting the file alone would wedge this project's
# batch permanently and SILENTLY -- introducing a silent-failure path in order
# to fix a race, which is the trade this repo exists to refuse.
#
# STARVATION CAP, non-negotiable: "defer whenever a human is present" means a
# long session starves this project's batch forever. After
# INTERACTIVE_DEFER_MAX consecutive deferrals, proceed anyway and say so
# LOUDLY. Warn-then-continue is a real failure pattern; silent indefinite
# deferral is a worse one. The cap is the lesser evil and is visible either
# way. Set INTERACTIVE_DEFER_MAX per job via RUNNER_ENV or the project's own
# schedule/<key>.conf; 3 consecutive misses is roughly "you have been editing
# across three of this project's turns."
INTERACTIVE_MARKER="$REGISTRY_DIR/${PROJECT_KEY}.interactive"
# Records WHEN the current deferral streak began, not how many times we asked.
# (Retires interactive_deferrals, a counter of dispatch attempts -- see
# registry_should_defer's header for why attempts measured nothing.)
DEFER_STREAK_FILE="$STATE_DIR/interactive_defer_since"
[ -f "$STATE_DIR/interactive_deferrals" ] && rm -f "$STATE_DIR/interactive_deferrals"

# The probe/cap policy itself now lives in lib/registry-lock.sh so the
# scheduler's own dev cycle obeys the same rule (2026-07-27) -- it had no
# registry participation at all and used a dirty-tree heuristic instead.
# Behaviour here is unchanged; only the decision moved. This file keeps the
# LOG WORDING, because the exit-code vocabulary (4 = deferred) and the
# ===-delimited run record are this job engine's contract, not the policy's.
# shellcheck source=lib/registry-lock.sh
. "$(dirname "${BASH_SOURCE[0]}")/registry-lock.sh"

if registry_should_defer "$PROJECT_KEY" "$DEFER_STREAK_FILE" "${PROJECT_REPO_PATH:-}"; then
  HUMAN_PID="$REGISTRY_DEFER_PID"
  HUMAN_SINCE="$REGISTRY_DEFER_SINCE"
  NOW_IS="$(date -Is)"
  # A real ===-delimited run record, same reasoning as the expiry block
  # below: a bare prose line is invisible to `scheduler status`, which
  # would then re-report the PREVIOUS run as this project's current state
  # and hide the fact that it has been standing down.
  {
    echo "=== $NOW_IS ==="
    echo "deferred -- '$PROJECT_KEY' is being worked in right now (pid $HUMAN_PID, since ${HUMAN_SINCE:-unknown}); no work attempted (no clone, no claude)."
    echo "reason: $REGISTRY_DEFER_REASON (watching ${REGISTRY_DEFER_DIR:-?}). Standing down for as long as that stays true; backstop at ${REGISTRY_DEFER_MAX_HOURS}h continuous, currently ${REGISTRY_DEFER_STREAK_MIN}m. Marker: $INTERACTIVE_MARKER"
    echo "=== skipped (repo active, ${REGISTRY_DEFER_STREAK_MIN}m into a deferral streak) $NOW_IS (0s) ==="
  } >> "$LOG"
  # Exit 4: distinct from success (0), fatal (1) and expired (3), so
  # usage-paced-runner.sh's `rc=` line tells deferred from worked without
  # parsing this log. The rotation simply comes back next tick.
  exit 4
fi

# Proceeding. registry_should_defer() returns 1 both when nobody is there and
# when the starvation cap fired -- REGISTRY_DEFER_CAPPED distinguishes them,
# and the capped case must never be quiet.
if [ "${REGISTRY_DEFER_CAPPED:-0}" = "1" ]; then
  # Only the BACKSTOP is loud. Proceeding because the repo went quiet is the
  # ordinary path and says nothing -- notifying on it is what trains a person
  # to ignore the notification that matters.
  echo "$(date -Is) WARNING: proceeding despite an ACTIVE repo on '$PROJECT_KEY' (pid $REGISTRY_DEFER_PID, since ${REGISTRY_DEFER_SINCE:-unknown}) -- $REGISTRY_DEFER_REASON. This run may write files you have open; your editor's next save reconciles via the vimrc 3-way merge." >> "$LOG"
  notify -u critical "$JOB_NAME: running while you work" "$PROJECT_KEY has deferred continuously for ${REGISTRY_DEFER_STREAK_MIN}m (backstop ${REGISTRY_DEFER_MAX_HOURS}h) and is now running anyway. Close the editor or expect a merge on save."
fi

echo "{\"job\":\"$JOB_NAME\",\"tier\":\"$TIER\",\"started_at\":\"$(date -Is)\",\"pid\":$$}" > "$REGISTRY_MARKER"
trap 'rm -f "$REGISTRY_MARKER"' EXIT

if [ -f "$LOG" ]; then
  tail -n 4000 "$LOG" > "$LOG.tmp"
  mv "$LOG.tmp" "$LOG"
fi

# Expiry (dead-man switch) is checked BEFORE the clone/secrets work, not
# after (moved 2026-07-26): an expired job used to clone the repo and copy
# secrets in first, then no-op -- burning network/disk for a run that was
# never going to do anything. The check needs nothing but the stamp file.
if [ ! -f "$EXPIRES_AT_FILE" ]; then
  date -d "+${EXPIRY_DAYS} days" -Is > "$EXPIRES_AT_FILE"
fi
EXPIRES_AT=$(cat "$EXPIRES_AT_FILE")
NOW_IS=$(date -Is)

if [[ "$NOW_IS" > "$EXPIRES_AT" ]]; then
  MSG="Auto-disabled: dead-man switch tripped ($EXPIRES_AT). Renew: rm $EXPIRES_AT_FILE -- next run re-stamps now+${EXPIRY_DAYS}d. Bumping EXPIRY_DAYS alone does NOT renew (the stamp is only written when the file is missing)."
  notify "$JOB_NAME" "$MSG"
  # A real ===-delimited run record, not one bare prose line (changed
  # 2026-07-26, FOCUS.md EXPIRY_DAYS finding 2: expiry used to be a clean
  # exit 0 with a log line nothing surfaced -- invisible everywhere but
  # this file). The start/completion pair is what `scheduler status`
  # slices a "last run" from, and "skipped" is a completion status it
  # already recognizes -- so an expired job now SHOWS expiry as its last
  # run instead of the view re-reporting the previous real run as current.
  {
    echo "=== $NOW_IS ==="
    echo "expired -- dead-man switch tripped; no work attempted (no clone, no claude). $MSG"
    echo "note: bin/sync-crontab.sh prunes this job's crontab line on its next --apply run; this script never touches crontab itself"
    echo "=== skipped (expired $EXPIRES_AT) $NOW_IS (0s) ==="
  } >> "$LOG"
  # Exit 3, not 0: distinct from success and from a fatal error (1), so a
  # dispatcher (usage-paced-runner.sh logs rc= per dispatch) can tell
  # "expired" from "worked" without parsing this log. Nothing keys on the
  # old exit 0 -- cron ignores exit codes and the paced runner only logs rc.
  exit 3
fi

# Dedicated clone, never the user's real working copy -- reset --hard
# below would destroy uncommitted work if pointed at a real checkout.
#
# The clone result is CHECKED (2026-07-24, dexter bring-up). It used to be
# unchecked, and with `set -uo pipefail` (no -e) a failed clone did not stop
# the run: $REPO never got created, the `cd "$REPO/$REPO_SUBDIR"` below
# silently failed too, and everything after it -- git checkout/fetch/reset
# --hard AND the `claude -p` call with Write/Edit/Bash -- ran in whatever
# directory cron happened to start in ($HOME). Found while pinning crt to
# dexter, where crt's REPO_URL (a bare repo local to mandark) genuinely is
# unreachable, making this the first host that would actually hit it.
if [ ! -d "$REPO/.git" ]; then
  if ! git clone "$REPO_URL" "$REPO" >> "$LOG" 2>&1; then
    echo "$(date -Is) FATAL clone failed: '$REPO_URL' -> '$REPO' (git output above) -- aborting before any git or claude work" >> "$LOG"
    notify -u critical "$JOB_NAME" "clone failed for $REPO_URL -- job aborted, see $LOG"
    exit 1
  fi
fi

if [ -n "$SECRETS_SRC_DIR" ]; then
  mkdir -p "$REPO/$SECRETS_DEST_SUBDIR"
  cp -f "$SECRETS_SRC_DIR"/* "$REPO/$SECRETS_DEST_SUBDIR/" 2>/dev/null || true
fi

NOW_EPOCH=$(date +%s)
LAST_HEARTBEAT_EPOCH=0
if [ -f "$HEARTBEAT_FILE" ]; then
  LAST_HEARTBEAT_EPOCH=$(cat "$HEARTBEAT_FILE")
fi
SECONDS_SINCE=$((NOW_EPOCH - LAST_HEARTBEAT_EPOCH))

if [ "$SECONDS_SINCE" -ge 86400 ]; then
  notify "$JOB_NAME" "Still running. Expires $EXPIRES_AT."
  echo "$NOW_EPOCH" > "$HEARTBEAT_FILE"
fi

{
  START_TS=$(date +%s)
  echo "=== $(date -Is) ==="
  # Belt-and-braces with the clone check above: never let a failed cd leave
  # the reset --hard / claude call running against the cron working directory.
  if ! cd "$REPO/$REPO_SUBDIR"; then
    echo "FATAL cannot cd '$REPO/$REPO_SUBDIR' -- aborting before any git or claude work"
    notify -u critical "$JOB_NAME" "cannot enter $REPO/$REPO_SUBDIR -- job aborted, see $LOG"
    exit 1
  fi
  # Hard safety check, not just a convention: this clone is meant to be
  # disposable between scheduled cycles, but a human can (and did, in
  # practice) open an interactive session directly in it -- e.g. to poke
  # at a project as svc-vaporwave. `git reset --hard` below would
  # silently discard any uncommitted work left behind. Stash it instead
  # of losing it; a stash survives reset --hard and is recoverable
  # (`git stash list` / `git stash pop`) even if nobody notices right
  # away, unlike a straight reset.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "uncommitted changes found before reset --hard -- stashing instead of discarding (git stash list to recover)"
    git stash push -u -m "sweep-loop-common.sh auto-stash before reset $(date -Is)"
  fi
  # Resolve BRANCH from the remote's own default HEAD when the wrapper
  # didn't name one. Local read (the clone already recorded it), no
  # network; ls-remote is the fallback, and only then the old "main"
  # guess -- now announced in the log rather than assumed.
  if [ -z "$BRANCH" ]; then
    BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
    if [ -z "$BRANCH" ]; then
      BRANCH="$(git ls-remote --symref origin HEAD 2>/dev/null | awk '$1=="ref:"{sub("refs/heads/","",$2); print $2; exit}')"
    fi
    if [ -z "$BRANCH" ]; then
      BRANCH="main"
      echo "WARNING: could not resolve origin's default branch -- falling back to '$BRANCH'"
    else
      echo "BRANCH unset by the wrapper -- resolved from origin's default HEAD: $BRANCH"
    fi
  fi
  # CHECKED, all three (2026-07-25). These were unchecked and `set -uo
  # pipefail` has no -e, so a bad branch name or an unreachable origin
  # let the run continue against whatever the clone happened to have
  # checked out -- i.e. the disposable-clone-reset-to-origin guarantee
  # every other part of this design assumes was silently void. Aborting
  # is correct: the next scheduled cycle retries, whereas a run on an
  # unknown base can commit and push real work onto the wrong thing.
  if ! git checkout "$BRANCH"; then
    echo "FATAL cannot checkout '$BRANCH' in $REPO -- aborting before any claude work (does that branch exist on origin?)"
    notify -u critical "$JOB_NAME" "checkout $BRANCH failed -- job aborted, see $LOG"
    exit 1
  fi
  if ! git fetch origin --quiet; then
    echo "FATAL git fetch origin failed -- aborting rather than running against a stale base"
    notify -u critical "$JOB_NAME" "fetch failed -- job aborted, see $LOG"
    exit 1
  fi
  # Bit chezz 2026-07-25: a prior run can die (e.g. hit the monthly spend
  # limit) after committing but before pushing, leaving real commits ahead
  # of origin. The stash guard above protects uncommitted work; committed
  # work had no equivalent -- this reset would destroy it outright, with
  # only luck (the reflog GC window) standing between it and being gone.
  # Rescue it into a dedicated ref before the reset can touch it.
  AHEAD_COUNT=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)
  if [ "$AHEAD_COUNT" -gt 0 ]; then
    RESCUE_REF="rescue/${JOB_NAME}-$(date +%Y%m%d%H%M%S)"
    git branch "$RESCUE_REF" HEAD
    echo "WARNING: $AHEAD_COUNT commit(s) ahead of origin/$BRANCH before reset --hard -- a prior run committed but never pushed. Rescued onto local ref '$RESCUE_REF' (git log $RESCUE_REF) before resetting; push it manually to recover."
    notify -u critical "$JOB_NAME" "$AHEAD_COUNT unpushed commit(s) found -- rescued to $RESCUE_REF before reset, see $LOG"
  fi
  if ! git reset --hard "origin/$BRANCH"; then
    echo "FATAL git reset --hard origin/$BRANCH failed -- aborting; the clone is NOT at origin's state"
    notify -u critical "$JOB_NAME" "reset to origin/$BRANCH failed -- job aborted, see $LOG"
    exit 1
  fi
  BEFORE_SHA=$(git rev-parse HEAD)
  echo "start commit: $BEFORE_SHA"

  # Pick up any %%TAG inline comments the human left in the previous
  # report (see docs/feedback-tags.md) and put them first in this run's
  # prompt. LATEST.md gets overwritten by this same run below, so a tag
  # naturally clears itself once acted on -- no separate "mark as read".
  LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  FEEDBACK_FILE="$HOME/reports/$PROJECT_KEY/LATEST.md"
  if [ -f "$FEEDBACK_FILE" ]; then
    FEEDBACK_BLOCK="$("$LIB_DIR/../bin/collect-feedback.sh" "$FEEDBACK_FILE" 2>/dev/null || true)"
    if [ -n "$FEEDBACK_BLOCK" ]; then
      echo "found inline feedback tags in $FEEDBACK_FILE -- prepending to prompt"
      PROMPT="Human feedback on the previous report, left inline in $FEEDBACK_FILE -- act on this FIRST, before anything else:

$FEEDBACK_BLOCK

---

$PROMPT"
    fi
  fi

  # Same idea, but for the cross-project BLOCKERS.md (human-owned action
  # items, e.g. "go flip this setting in a browser"). --section restricts
  # to this project's own "## $PROJECT_KEY" heading; --consume removes
  # the matched %%TAG lines from BLOCKERS.md once collected (that file is
  # hand-maintained and persistent, unlike LATEST.md, so it needs its own
  # "mark as read" instead of relying on the next report overwriting it).
  BLOCKERS_FILE="$LIB_DIR/../BLOCKERS.md"
  if [ -f "$BLOCKERS_FILE" ]; then
    # --consume only if this account can actually write the file back --
    # a cross-account run (e.g. svc-vaporwave reading zach-owned
    # BLOCKERS.md) that tried --consume anyway hung indefinitely on the
    # resulting mv instead of failing fast (real incident 2026-07-20,
    # root cause of the mv not fully diagnosed -- this guard sidesteps it
    # rather than relying on understanding exactly why it hung).
    CONSUME_FLAG=""
    [ -w "$BLOCKERS_FILE" ] && CONSUME_FLAG="--consume"
    BLOCKERS_BLOCK="$("$LIB_DIR/../bin/collect-feedback.sh" "$BLOCKERS_FILE" --section "$PROJECT_KEY" $CONSUME_FLAG 2>/dev/null || true)"
    if [ -n "$BLOCKERS_BLOCK" ]; then
      echo "found inline feedback tags in $BLOCKERS_FILE under ## $PROJECT_KEY -- prepending to prompt"
      FEEDBACK_BLOCK="${FEEDBACK_BLOCK:-}${FEEDBACK_BLOCK:+$'\n\n'}$BLOCKERS_BLOCK"
      PROMPT="Human feedback left inline in $BLOCKERS_FILE (cross-project blockers file) -- act on this FIRST, before anything else:

$BLOCKERS_BLOCK

---

$PROMPT"
    fi
  fi

  # claude's own output is tee'd to a per-run capture file (as well as
  # flowing into $LOG via the enclosing block redirect) so that a FAILED
  # run can be diagnosed against exactly THIS run's output -- $LOG
  # accumulates across runs, so grepping it would match stale text from
  # an earlier failure. pipefail is set above, so the pipeline's status
  # is still claude's own exit code.
  CLAUDE_OUT="$STATE_DIR/claude-last-run.out"
  STATUS_DETAIL=""
  if [ -n "$PRECHECK_CMD" ] && [ -z "${FEEDBACK_BLOCK:-}" ] && ! eval "$PRECHECK_CMD"; then
    echo "precheck said nothing to do -- skipping claude invocation this run"
    STATUS="skipped (precheck)"
  elif claude -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS" --max-turns "$MAX_TURNS" ${MODEL:+--model "$MODEL"} 2>&1 | tee "$CLAUDE_OUT"; then
    STATUS="done"
  else
    STATUS="FAILED"
    # Say WHY claude itself failed when the cause is recognizable, instead
    # of every non-zero exit reading as the same generic FAILED. The one
    # cause worth naming today is a lapsed/absent CLI login ("Not logged
    # in") -- a recurring unattended failure mode (see
    # .scheduler/QUESTIONS.md answer 2026-07-25: make it LOUD, same
    # principle as stale .active markers and push-reason surfacing). It
    # is NOT a quota/turn cutoff and has a specific human fix: run any
    # interactive claude session as this OS user to refresh credentials.
    # STATUS itself stays the exact string "FAILED" -- the push-reason and
    # exit-code blocks below compare it with = -- the detail rides in
    # STATUS_DETAIL and is appended to the final === line.
    if grep -qiE 'not logged in|please run /login|invalid api key|oauth token.*(expired|revoked)|authentication[_ ]?error' "$CLAUDE_OUT" 2>/dev/null; then
      STATUS_DETAIL=" (auth: not logged in)"
      echo "CRITICAL: claude authentication failure -- this account's CLI credentials have lapsed (\"Not logged in\"), NOT a quota/turn cutoff. Fix: run any interactive claude session as OS user $(id -un) to refresh the login, then this job recovers on its own next scheduled run."
      notify -u critical "$JOB_NAME: claude NOT LOGGED IN" "CLI credentials lapsed for OS user $(id -un) -- run any interactive claude session to refresh. See $LOG"
    fi
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
    # Nonzero, not just a log line (2026-07-25). This branch is the exact
    # state home-assistant sat in for weeks while `usage-paced-runner.sh`
    # recorded `rc=0` and the run's own summary claimed it had pushed. The
    # runner logs whatever rc it gets and neither retries nor escalates, so
    # returning 1 here costs nothing and is the difference between a
    # failure that is visible in run.log and one that isn't.
    RUN_RC=1
    echo "WARNING: local commit made but NOT pushed to origin (local=$AFTER_SHA remote=$REMOTE_SHA)"
    # WHY, not just THAT -- distinguish the recurring causes instead of
    # leaving every unpushed commit looking like the same generic no-op
    # (this is the "stale/incomplete-push visibility" stability-milestone
    # item). All read-only: --dry-run never mutates the remote, so it's
    # safe to run here even though the same `claude -p` invocation above
    # may have already attempted and failed its own push.
    if [ "$STATUS" = "FAILED" ] && [ -n "${STATUS_DETAIL:-}" ]; then
      echo "push reason: claude -p failed with a recognized cause -- ${STATUS_DETAIL# } (see the CRITICAL line above), not a push failure per se"
    elif [ "$STATUS" = "FAILED" ]; then
      echo "push reason: claude -p itself exited non-zero (see above) -- most likely cut off (turn/spend limit) before it reached a push step, not a push failure per se"
    elif [ -z "$REMOTE_SHA" ]; then
      echo "push reason: could not read origin/$BRANCH at all (git ls-remote returned nothing) -- looks like an SSH/auth/network failure reaching origin, not a push rejection"
    elif git merge-base --is-ancestor "$REMOTE_SHA" "$AFTER_SHA" 2>/dev/null; then
      DRY_RUN_OUT="$(git push --dry-run origin "HEAD:$BRANCH" 2>&1)"
      if [ $? -eq 0 ]; then
        echo "push reason: a plain push would succeed right now (dry-run OK) -- claude's own run likely never attempted git push at all this cycle, not a credential/conflict failure"
      else
        echo "push reason: dry-run push failed -- $(echo "$DRY_RUN_OUT" | grep -m1 -v '^$')"
      fi
    else
      echo "push reason: origin/$BRANCH has commit(s) local doesn't (diverged) -- would need a merge/rebase before push, not a credential issue"
    fi
  fi

  # AUTONOMY_TIER="high" gate (lib/autonomy-merge.sh) -- runs regardless of
  # whether THIS run's own subagent created a branch, so it also catches
  # anything left over from an earlier run/turn-limit cutoff. No-op for
  # any other tier value; see that file for the merge/push/fallback logic.
  autonomy_sweep_repo "$REPO" "$BRANCH" "$AUTONOMY_TIER" "$TEST_CMD" "$JOB_NAME"

  echo "=== $STATUS${STATUS_DETAIL:-} $(date -Is) (${ELAPSED}s) ==="

  if [ "$STATUS" = "FAILED" ]; then
    RUN_RC=1
    notify -u critical "$JOB_NAME FAILED" "See log: $LOG"
  fi
} >> "$LOG" 2>&1

# The job's exit status is the runner's ONLY machine-readable verdict --
# it is what lands in usage-paced-runner.sh's `DONE <name> rc=N` line.
# Before 2026-07-25 that was whatever the last command in the block
# happened to return (usually notify-send, i.e. 0), so a FAILED claude
# run and an unpushed commit both reported success. The brace group above
# is a group, not a subshell, so RUN_RC set inside it is visible here.
exit "${RUN_RC:-0}"
