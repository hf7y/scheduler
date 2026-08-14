#!/usr/bin/env bash
# debroussaille.sh -- clear the brush before the mowing (hf7y/scheduler#37).
#
# Mechanically clears git debris that needs no judgement call: local
# branches fully merged into origin's default branch, and worktrees that
# are both clean and already fully present on origin. Never deletes a
# repository -- that is fauche's contract, not this script's. Writes the
# residue (what it did NOT clear, plus fauche's own repo-level verdict) as
# a dated report via publish-report.sh, so the next session opens on facts
# probed that run instead of prose written days ago (#37's own words).
#
# Companion to fauche: fauche answers "is this whole repo recoverable
# elsewhere," debroussaille answers "what inside a KEPT repo needs no
# human at all." Neither one deletes a repo.
#
# SCOPE, discovered 2026-08-14 while building this. #37 asked for "a
# paced-rotation job on monkey that runs fauche check across every
# clone" -- but self-dev accounts on monkey are siloed home directories
# (confirmed: the `scheduler` account gets Permission denied reading
# /home/zach). One account cannot reach another's clones, so this cannot
# be a single monkey-wide job; each self-dev account's own paced rotation
# is where it gets invoked, against that account's own clones. This
# script is scoped to what ONE account can see; #37 stays open for the
# per-account rotation wiring.
#
# RUNNER: tests/debroussaille-witness.sh
set -uo pipefail

CLI_NAME="debroussaille.sh"
FAUCHE_BIN="${DEBROUSSAILLE_FAUCHE_BIN:-fauche}"
REPORTS_ROOT="${DEBROUSSAILLE_REPORTS_ROOT:-$HOME/reports}"

usage() {
  cat <<EOF
usage: $CLI_NAME [--apply] [repo...]

Clear provably-recoverable git debris from each <repo> (default: every git
repo directly under ~/Documents/Projects). Never deletes a repository.

  (default)  report what would be cleared; writes nothing to any repo
  --apply    delete merged branches and stale-but-recoverable worktrees

Writes a dated residue report to \$REPORTS_ROOT/debroussaille/ regardless
of mode (REPORTS_ROOT default: ~/reports).

exit: 0 ok  2 usage  5 broken
EOF
}

MODE="check"
REPOS=()
for a in "$@"; do
  case "$a" in
    --apply) MODE="apply" ;;
    --check) MODE="check" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CLI_NAME: unknown flag $a" >&2; exit 2 ;;
    *) REPOS+=("$a") ;;
  esac
done

if [ "${#REPOS[@]}" -eq 0 ]; then
  PROJ_DIR="$HOME/Documents/Projects"
  [ -d "$PROJ_DIR" ] || { echo "$CLI_NAME: BROKEN: no repo named and $PROJ_DIR does not exist" >&2; exit 5; }
  while IFS= read -r -d '' d; do
    [ -d "$d/.git" ] && REPOS+=("$d")
  done < <(find "$PROJ_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "$CLI_NAME: BROKEN: no git repos found to scan" >&2
  exit 5
fi

REPORT_LINES=()
add() { REPORT_LINES+=("$1"); }

PROCESSED=0
for repo in "${REPOS[@]}"; do
  repo="$(cd "$repo" 2>/dev/null && pwd -P)" || { echo "$CLI_NAME: skipping $repo: not a directory" >&2; continue; }
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "$CLI_NAME: skipping $repo: not a git repo" >&2
    continue
  fi
  PROCESSED=$((PROCESSED + 1))

  add "## $repo"
  add ""

  default_branch="$(git -C "$repo" remote show origin 2>/dev/null | sed -n 's/^[[:space:]]*HEAD branch: //p')"
  current_branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

  cleared_branches=()
  kept_branches=()
  if [ -n "$default_branch" ]; then
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      [ "$b" = "$default_branch" ] && continue
      if [ "$b" = "$current_branch" ]; then
        kept_branches+=("$b (checked out)")
        continue
      fi
      if [ "$MODE" = "apply" ]; then
        if git -C "$repo" branch -d "$b" >/dev/null 2>&1; then
          cleared_branches+=("$b")
        else
          kept_branches+=("$b (delete refused -- not actually merged, or checked out in a worktree)")
        fi
      else
        cleared_branches+=("$b")
      fi
    done < <(git -C "$repo" branch --format='%(refname:short)' --merged "origin/$default_branch" 2>/dev/null)
  else
    add "- default branch unknown (no origin, or origin HEAD unset) -- branch cleanup skipped"
  fi

  if [ "${#cleared_branches[@]}" -gt 0 ]; then
    verb="cleared"; [ "$MODE" = "check" ] && verb="would clear"
    add "- $verb ${#cleared_branches[@]} merged branch(es): ${cleared_branches[*]}"
  fi
  if [ "${#kept_branches[@]}" -gt 0 ]; then
    add "- kept ${#kept_branches[@]} branch(es): ${kept_branches[*]}"
  fi

  cleared_wt=()
  kept_wt=()
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    [ "$wt" = "$repo" ] && continue
    if [ ! -d "$wt" ]; then
      kept_wt+=("$wt (missing on disk)")
      continue
    fi
    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
      kept_wt+=("$wt (dirty)")
      continue
    fi
    wt_head="$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo '')"
    if [ -z "$wt_head" ] || ! git -C "$repo" branch -r --contains "$wt_head" 2>/dev/null | grep -q .; then
      kept_wt+=("$wt (HEAD not on any origin branch)")
      continue
    fi
    if [ "$MODE" = "apply" ]; then
      if git -C "$repo" worktree remove "$wt" >/dev/null 2>&1; then
        cleared_wt+=("$wt")
      else
        kept_wt+=("$wt (remove refused)")
      fi
    else
      cleared_wt+=("$wt")
    fi
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

  if [ "${#cleared_wt[@]}" -gt 0 ]; then
    verb="cleared"; [ "$MODE" = "check" ] && verb="would clear"
    add "- $verb ${#cleared_wt[@]} worktree(s): ${cleared_wt[*]}"
  fi
  if [ "${#kept_wt[@]}" -gt 0 ]; then
    add "- kept ${#kept_wt[@]} worktree(s): ${kept_wt[*]}"
  fi

  if command -v "$FAUCHE_BIN" >/dev/null 2>&1; then
    add "- fauche verdict:"
    while IFS= read -r line; do add "    $line"; done < <("$FAUCHE_BIN" check "$repo" 2>&1)
  fi
  add ""
done

if [ "$PROCESSED" -eq 0 ]; then
  echo "$CLI_NAME: BROKEN: none of the named path(s) were usable git repos" >&2
  exit 5
fi

STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
BODY="$(printf '# debroussaille residue -- %s (%s)\n\n' "$STAMP" "$MODE"; printf '%s\n' "${REPORT_LINES[@]}")"

echo "$BODY"

REPORT_DIR="$REPORTS_ROOT/debroussaille"
mkdir -p "$REPORT_DIR" || { echo "$CLI_NAME: BROKEN: could not create $REPORT_DIR" >&2; exit 5; }
DATED="$STAMP-debroussaille.md"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PUBLISH_BIN="${DEBROUSSAILLE_PUBLISH_BIN:-$SCRIPT_DIR/publish-report.sh}"
if [ -x "$PUBLISH_BIN" ]; then
  SCHEDULER_REPORTS_ROOT="$REPORTS_ROOT" "$PUBLISH_BIN" debroussaille "$DATED" --from - <<<"$BODY" \
    || echo "$CLI_NAME: NOTE: report body printed above but publish-report.sh failed to persist it" >&2
else
  echo "$CLI_NAME: NOTE: publish-report.sh not found at $PUBLISH_BIN -- report only printed, not persisted" >&2
fi

exit 0
