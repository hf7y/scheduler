#!/usr/bin/env bash
# enrole-selfdev.sh -- the two steps setup-selfdev-project.sh prints as prose
# and leaves to a human, done mechanically, idempotently and reversibly: flip
# the project's row in schedule/_paced.<host>.conf from |0| to |1|, and sync
# that host's crontab as the project's own account.
# TRAPS (the rest of this header is in
# vault:scheduler/provisioning-block-headers-20260826.md):
# TRAP: --retire flips the row to |0|; it does NOT delete it. Membership is
#   what SUPPRESSES the project's fixed nightly cron line, so deleting a row
#   to "clean up" installs a dispatch the rotation no longer controls
#   (2026-08-05, five stray cron lines). The reverse of "add a row" is "flip
#   a field".
# TRAP: IT COMMITS NOTHING. The repo half edits a scheduler clone and stops --
#   a provisioning script that pushes to a repo fourteen accounts pull from is
#   a blast radius nobody asked for.
set -uo pipefail

CLI_NAME='enrole-selfdev.sh'
CLI_SUMMARY='enrol a landed self-dev project into its host rotation -- mechanical, idempotent, reversible'
CLI_USAGE='  enrole-selfdev.sh <project>                    --check (default): probe, write NOTHING
  enrole-selfdev.sh <project> --apply            ensure conf fields + an ENABLED rotation row
  enrole-selfdev.sh <project> --retire           set the rotation row back to |0| (keeps the row)
  enrole-selfdev.sh <project> --apply --host h   target another host'"'"'s _paced.<h>.conf
  enrole-selfdev.sh <project> --apply --sync     ALSO run dose-project.sh <project> --apply
                                                 (host half; needs to be root or that user;
                                                 needs a schedule/ROSTER row for <project>)

  --repo <dir>   the scheduler clone to edit (default: $SCHEDULER_REPO, else
                 ~/Documents/Projects/scheduler)'
CLI_FLAGS='--check --apply --retire --sync --host --repo'
CLI_POSITIONAL=any
CLI_EXITS='  0  enrolled (or, under --check, would enrol with no findings)
  1  findings: a precondition is unmet -- read the BAD rows
  3  the project is not registered (no schedule/<project>.conf) -- register it first
  5  refused: the scheduler clone is missing, dirty in the files this touches,
     or the host has no _paced.<host>.conf'
. "$(dirname "${BASH_SOURCE[0]}")/../lib/cli-guard.sh"
cli_guard "$@"

MODE=--check; PROJECT=""; HOST=""; SYNC=0; REPO="${SCHEDULER_REPO:-$HOME/Documents/Projects/scheduler}"
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--apply|--retire) MODE="$1" ;;
    --sync)  SYNC=1 ;;
    --host)  shift; HOST="${1:-}" ;;
    --repo)  shift; REPO="${1:-}" ;;
    -*)      cli_die "unknown flag: $1" ;;
    *)       [ -z "$PROJECT" ] && PROJECT="$1" || cli_die "unexpected argument: $1" ;;
  esac
  shift
done
[ -n "$PROJECT" ] || cli_die "no project named"
[ -n "$HOST" ] || HOST="$(hostname -s 2>/dev/null || echo unknown)"

PW_OK_FMT='  OK      %s\n'
PW_GAP_FMT='  MISSING %s\n'
PW_BAD_FMT='  BAD     %s\n'
PW_ACT_FMT='  DO      %s\n'
. "$(dirname "${BASH_SOURCE[0]}")/../lib/provision-witness.sh"
die() { printf '\n%s: %s\n' "$CLI_NAME" "$*" >&2; exit "${2:-5}"; }

echo "== enrole-selfdev $PROJECT ($MODE) -- host $HOST, repo $REPO =="

CONF="$REPO/schedule/$PROJECT.conf"
PACED="$REPO/schedule/_paced.$HOST.conf"
[ -d "$REPO/.git" ]  || die "$REPO is not a git clone -- pass --repo <scheduler clone>"
[ -f "$CONF" ]       || die "$PROJECT is not registered: no $CONF. Registration is a separate, reviewed act -- copy examples/schedule-entry.conf.template." 3
# TRAP: a host with no rotation file falls back to the SHARED _paced.conf -- another machine's rotation. Writing a row into a file this host does not read looks done and is not.
[ -f "$PACED" ]      || die "no $PACED -- this host reads the shared _paced.conf, i.e. another machine's rotation. Give it its own file first."

refuse_if_dirty() {  # <path> <regex of lines this script owns>
  local path="$1" mine="$2" foreign
  git -C "$REPO" diff --quiet -- "$path" 2>/dev/null && return 0
  git -C "$REPO" ls-files --error-unmatch "$path" >/dev/null 2>&1 || return 0   # untracked: nothing to lose
  foreign="$(git -C "$REPO" diff -U0 -- "$path" | grep -E '^[+-][^+-]' | grep -vE "^[+-]($mine)" || true)"
  [ -z "$foreign" ] && return 0
  die "uncommitted changes in $path that this script does not own:
$foreign
Commit, stash or revert them first -- adopting another writer's in-flight edit
is not this script's call."
}
# Field, wanted value, why it is not optional. All derived from project and host; nothing here is a judgement.
conf_get() { grep -m1 -oP "(?<=^$1=\")[^\"]*" "$CONF" 2>/dev/null || true; }

declare -a FIELD=(CRON_HOST      CRON_ACCOUNT BATCH_JOB_NAME)
declare -a WANT=("$HOST"         "$PROJECT"   "$PROJECT-nightly-batch")
declare -a WHY=(
  "without it mandark also emits this project's cron lines"
  "state ownership: whose ~/.local/share holds the run log (scheduler#33 -- four jobs read 7-12d idle while running daily)"
  "scheduler-run <p> batch exits 2 without it -- a blank one is not 'unarmed', it is 'armed and broken'"
)

CONF_MINE="($(IFS='|'; echo "${FIELD[*]}"))=\""
ROW_MINE="$PROJECT\\|"

ensure_field() {  # <field> <value> -- print nothing if already right
  local f="$1" v="$2" cur; cur="$(conf_get "$f")"
  [ "$cur" = "$v" ] && return 1
  if grep -qE "^$f=" "$CONF"; then
    sed -i "s|^$f=.*|$f=\"$v\"|" "$CONF"
  else
    # TRAP: appended, never inserted at a guessed line -- these confs are SOURCED so order is meaningless, and a guessed insertion point lands inside a heredoc-shaped BATCH_PROMPT sooner or later.
    printf '%s="%s"\n' "$f" "$v" >> "$CONF"
  fi
  return 0
}

echo "-- conf fields ($CONF)"
changed=0
for i in "${!FIELD[@]}"; do
  f="${FIELD[$i]}"; v="${WANT[$i]}"; cur="$(conf_get "$f")"
  if [ "$cur" = "$v" ]; then ok "$f=\"$v\""
  elif [ "$MODE" = --check ]; then act "set $f=\"$v\" (currently \"${cur:-unset}\") -- ${WHY[$i]}"; GAPS=$((GAPS+1))
  elif [ "$MODE" = --retire ]; then ok "$f left as \"${cur:-unset}\" (retire touches the rotation row only)"
  else refuse_if_dirty "schedule/$PROJECT.conf" "$CONF_MINE"; ensure_field "$f" "$v" && { act "set $f=\"$v\" (was \"${cur:-unset}\")"; changed=1; }
  fi
done

# The brief location is a FACT ABOUT THE PROJECT REPO, not fixable by editing the scheduler conf. Reported, never auto-moved: a git mv in someone else's repository is a PR, not a side effect of provisioning.
PRP="$(conf_get PROJECT_REPO_PATH)"; PRP="${PRP/\$HOME/$HOME}"
if [ -d "$PRP" ]; then
  if [ -f "$PRP/CLAUDE.md" ]; then ok "brief at CLAUDE.md (repo root, writable unattended -- the live convention; schedule/_run-procedure.md reads this)"
  elif [ -f "$PRP/.scheduler/FOCUS.md" ]; then ok "brief at .scheduler/FOCUS.md (writable unattended)"
  elif [ -f "$PRP/.claude/FOCUS.md" ]; then
    bad "brief is at .claude/FOCUS.md -- an unattended run can read it and CANNOT write it (sensitive-file gate). Move it: git mv .claude/FOCUS.md .scheduler/FOCUS.md (same for QUESTIONS.md), in that repo, as its own PR."
  else gap "no CLAUDE.md or FOCUS.md in any location under $PRP -- the run will have only its BATCH_PROMPT and the issue queue"; fi
else
  gap "PROJECT_REPO_PATH=$PRP is not present here -- cannot check where the brief lives (normal when enrolling from a different account than the one that will run it)"
fi

# One name, three surfaces (unix user, PROJECT, first column) -- MONKEY.md 2. The command is BUILT, not copied, so a renamed account leaves no stale path.
# TRAP: the rotation column MUST stay an absolute literal -- _paced*.conf is read by `while IFS=| read`, not sourced, so $HOME does not expand there (MONKEY.md 4b). HOME_ROOT is a variable because a host may put accounts outside /home; it is resolved here and written out expanded.
HOME_ROOT="${SELFDEV_HOME_ROOT:-/home}"
ROW_CMD="$HOME_ROOT/$PROJECT/Documents/Projects/scheduler/bin/scheduler-run $PROJECT batch"
echo "-- rotation row ($PACED)"
cur_row="$(grep -m1 -E "^$PROJECT\|" "$PACED" || true)"
want_enabled=1; [ "$MODE" = --retire ] && want_enabled=0

if [ -z "$cur_row" ]; then
  if [ "$MODE" = --retire ]; then ok "no row for $PROJECT -- nothing to retire"
  elif [ "$MODE" = --check ]; then act "add row: $PROJECT|1|1|$ROW_CMD"; GAPS=$((GAPS+1))
  else
    refuse_if_dirty "schedule/_paced.$HOST.conf" "$ROW_MINE"
    # >> onto a newline-less file FUSES the new row onto the last one.
    [ -s "$PACED" ] && [ -n "$(tail -c1 "$PACED")" ] && printf '\n' >> "$PACED"
    printf '%s|1|1|%s\n' "$PROJECT" "$ROW_CMD" >> "$PACED"
    act "added row: $PROJECT|1|1|$ROW_CMD"; changed=1
  fi
else
  # Field 2 is enabled; the row may or may not carry a weight in field 3.
  IFS='|' read -r _n en rest <<<"$cur_row"
  if [ "${en// /}" = "$want_enabled" ]; then ok "row present, enabled=$want_enabled"
  elif [ "$MODE" = --check ]; then act "flip row enabled: $en -> $want_enabled"; GAPS=$((GAPS+1))
  else
    refuse_if_dirty "schedule/_paced.$HOST.conf" "$ROW_MINE"
    # TRAP: anchored to the row own text -- a project name that prefixes another ("crt" vs "crt-cast") must not be rewritten by accident.
    new_row="$PROJECT|$want_enabled|$rest"
    python3 - "$PACED" "$cur_row" "$new_row" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(old + "\n") == 1, "expected exactly one occurrence of the row"
open(p, "w").write(s.replace(old + "\n", new + "\n"))
PY
    act "row enabled $en -> $want_enabled"; changed=1
  fi
fi

# Separate flag: the repo half edits a clone anywhere, the host half installs a crontab ON the host AS the account.
if [ "$SYNC" -eq 1 ] && [ "$MODE" != --check ]; then
  echo "-- host half (dose-project.sh as $PROJECT)"
  if [ "$(id -un)" = "$PROJECT" ]; then RUN=(bash -lc)
  elif [ "$(id -u)" -eq 0 ]; then RUN=(sudo -u "$PROJECT" -H bash -lc)
  else RUN=(); bad "--sync needs to run as root or as $PROJECT (this is $(id -un))"; fi
  if [ "${#RUN[@]}" -gt 0 ]; then
    out="$("${RUN[@]}" "cd ~/Documents/Projects/scheduler && git pull -q --ff-only && ./bin/dose-project.sh '$PROJECT' --apply" 2>&1)"; rc=$?
    printf '%s\n' "$out" | sed 's/^/    /'
    if [ "$rc" -ne 0 ]; then bad "dose-project.sh exited $rc as $PROJECT -- if this is exit 4 (no roster row), $PROJECT needs a schedule/ROSTER row first"
    else ok "crontab converged for $PROJECT"; fi
  fi
elif [ "$SYNC" -eq 1 ]; then
  act "--sync ignored under --check"
fi

echo
if [ "$MODE" = --check ]; then
  printf 'check only, nothing written: %d ok, %d would-change, %d bad\n' "$PASS" "$GAPS" "$BAD"
  [ "$BAD" -eq 0 ] || { echo "resolve the BAD rows first."; exit 1; }
  echo "Next: $CLI_NAME $PROJECT --apply [--sync]"
  exit 0
fi
if [ "$changed" -eq 1 ]; then
  echo "-- diff (NOT committed; land it as a PR)"
  git -C "$REPO" --no-pager diff -- "schedule/$PROJECT.conf" "schedule/_paced.$HOST.conf" | sed 's/^/    /'
  echo "    undo: git -C $REPO checkout -- schedule/$PROJECT.conf schedule/_paced.$HOST.conf"
else
  echo "no change -- $PROJECT was already $([ "$MODE" = --retire ] && echo retired || echo enrolled) (idempotent)"
fi
printf '%d ok, %d bad\n' "$PASS" "$BAD"
[ "$BAD" -eq 0 ]
