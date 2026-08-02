#!/usr/bin/env bash
# deploy-drift-check.sh -- does what's INSTALLED still match what's in git?
#
# Offline-first, read-only, zero AI cost -- same discipline as
# docs/offline-first-checks.md and blockers-freshness-check.sh. It never
# edits anything under $DEPLOY_DIR (installed wrappers are outside this
# repo's write scope by standing rule); it only reports.
#
# Why this exists (found 2026-07-26, live, not hypothetical):
# ~/.local/bin/usage-paced-runner.sh -- the script cron actually executes
# every 5 minutes -- is a hand-made COPY of bin/usage-paced-runner.sh, not a
# symlink into the checkout. Two things follow, both silent:
#
#   1. Every improvement committed to bin/usage-paced-runner.sh since the
#      copy was made (2026-07-24 19:53) has never gone live. The repo file
#      and the running file had diverged and nothing said so.
#   2. A copied install also disables any logic in the script that resolves
#      its own repo from its own path. Concretely: that script's auto-pull
#      (built 2026-07-24 so a commit on one host reaches the other) derives
#      REPO_ROOT from `readlink -f "$0"/..`, which under a copy install is
#      ~/.local -- not a git repo -- so the whole pull block is skipped.
#      Witness: 0 `PULL` lines in 1633 lines of that job's own run.log.
#
# So "deployed" was an assumed external dependency that had quietly stopped
# being true -- exactly the failure class the stability milestone names. A
# symlink install cannot drift; a copy can, and did.
#
# THE DECLARED SET, added 2026-08-02 -- and the reason is this script itself.
# Everything below USED to iterate "per file in this repo's bin/ that ALSO
# EXISTS in $DEPLOY_DIR" -- the intersection. A file that SHOULD be installed
# and simply is not was never iterated over, so absence could not be reported;
# only a DANGLING symlink was caught, never an ABSENT one. With no overlap at
# all the summary printed "nothing in $DEPLOY_DIR shares a name with this
# repo's bin/ -- nothing to check" and exited 0. That is an exit-0 no-op inside
# the guard built to catch deploy problems, and it is the outage in the header
# above one level up: on a BARE host this check reported clean.
#
# DEXTER-MIGRATION-NOTES-20260729.md states the rule this now keeps:
#   check the DECLARED set, never the intersection, or absence reports clean.
#
# The declaration is DERIVED, not typed. This repo already says which of its
# scripts must exist at an installed path, because its own config names them:
#   schedule/_sweep.conf     SWEEP_TICK_CMD=".../.local/bin/scheduler sweep"
#   schedule/_runner.conf    RUNNER_CMD=".../.local/bin/usage-paced-runner.sh"
#   .scheduler/schedule.conf BATCH_SCRIPT=".../.local/bin/scheduler-dev-cycle.sh"
# A config assignment naming $DEPLOY_DIR/<name> IS the declaration that <name>
# must be installed -- that is exactly what made the July outage possible,
# since sync-crontab.sh will happily write a cron line pointing at a path
# nothing ever created. Comment lines are excluded: several configs discuss
# installed paths in prose, and dexter's deliberately use repo paths instead,
# so a commented example is not a declaration.
#
# Checks, per DECLARED install:
#   ABSENT  declared by config, not installed at all -- the case the
#           intersection could not see, and the one that takes dispatch down
#   NOSRC   declared, but this repo has no bin/<name> to install from
#
# Checks, per file in this repo's bin/ that also exists in $DEPLOY_DIR:
#   OK      symlink into a checkout -- tracks whatever it points at
#   DRIFT   copy whose content differs from $DEPLOY_REF (names the commit
#           the copy DOES match, so "how stale" is a fact, not a guess)
#   COPY    copy that matches $DEPLOY_REF today -- not broken now, but
#           nothing keeps it in sync, and see (2) above for the sharper
#           edge: a copy can disable repo-relative logic even when its
#           bytes are current
#   BROKEN  symlink whose target no longer exists
#
# Findings are SIGNALS, not verdicts -- the fix (usually `ln -sfn`) is a
# human step outside this repo. Exit 1 if anything is flagged, 0 if clean,
# 2 on a setup problem.
#
# Env: DEPLOY_DIR (~/.local/bin), DEPLOY_REF (origin/main, then main, then
#      HEAD -- whichever resolves first)
set -uo pipefail

SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"
[ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF_REAL")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)" || exit 2
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/.local/bin}"

[ -d "$REPO_ROOT/bin" ] || { echo "FATAL: no bin/ under $REPO_ROOT" >&2; exit 2; }

# Runtime witness -- record that this check actually RAN, so a
# built-but-unwired check fails loud in `scheduler sweep` instead of looking
# clean (lib/check-witness.sh + bin/check-witness-lint.sh, 2026-07-28).
# Guarded, and never fatal -- bookkeeping must not be able to break a check.
if [ -r "$REPO_ROOT/lib/check-witness.sh" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/check-witness.sh"
  check_witness "$(basename "$SELF_REAL")"
fi

git_ok=0
git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && git_ok=1

REF=""
if [ "$git_ok" = "1" ]; then
  if [ -n "${DEPLOY_REF:-}" ]; then
    REF="$DEPLOY_REF"
    git -C "$REPO_ROOT" rev-parse --verify --quiet "$REF^{commit}" >/dev/null \
      || { echo "FATAL: DEPLOY_REF=$REF does not resolve in $REPO_ROOT" >&2; exit 2; }
  else
    for cand in origin/main main HEAD; do
      if git -C "$REPO_ROOT" rev-parse --verify --quiet "$cand^{commit}" >/dev/null; then
        REF="$cand"; break
      fi
    done
  fi
fi

# Which checkout should an install actually point AT? Not necessarily the one
# this script is running from: an unattended paced cycle runs out of a
# throwaway worktree (~/.local/share/scheduler-paced-dev/worktree), and
# telling a human to `ln -sfn` into a directory that gets deleted would be
# worse than the drift being reported. Resolve the main checkout via the
# shared git dir and suggest THAT; fall back to REPO_ROOT if it isn't a
# linked worktree (or the fallback path has no bin/).
LINK_ROOT="$REPO_ROOT"
WORKTREE_NOTE=""
if [ "$git_ok" = "1" ]; then
  _gitdir="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
  _common="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_common" ] && [ "$_gitdir" != "$_common" ]; then
    _main_root="$(dirname "$_common")"
    if [ -d "$_main_root/bin" ]; then
      LINK_ROOT="$_main_root"
      WORKTREE_NOTE="$_main_root"
    fi
  fi
fi

echo "deploy-drift-check -- $(date '+%Y-%m-%d %H:%M')"
echo "  repo:      $REPO_ROOT"
[ -n "$WORKTREE_NOTE" ] && echo "             (a linked worktree -- 'fix:' lines below point at the main checkout, $WORKTREE_NOTE)"
echo "  installed: $DEPLOY_DIR"
if [ -n "$REF" ]; then
  echo "  ref:       $REF ($(git -C "$REPO_ROOT" rev-parse --short "$REF"))"
else
  echo "  ref:       (none -- not a git checkout; comparing against the working tree)"
fi
echo "(offline-first: no claude calls, nothing under $DEPLOY_DIR is modified.)"

# Which commit does this installed copy actually match? Walks the file's own
# history comparing blob hashes, so staleness is reported as a real commit +
# date rather than "differs".
matching_commit() {
  local name="$1" live_hash="$2" c blob
  [ -n "$REF" ] || return 1
  while read -r c; do
    [ -n "$c" ] || continue
    blob="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "$c:bin/$name" 2>/dev/null)" || continue
    if [ "$blob" = "$live_hash" ]; then echo "$c"; return 0; fi
  done < <(git -C "$REPO_ROOT" rev-list --max-count=200 "$REF" -- "bin/$name" 2>/dev/null)
  return 1
}

flagged=0
checked=0

# ---------------------------------------------------------- the declared set --
# Every non-comment config assignment naming $DEPLOY_DIR/<name>. Derived from
# the repo on every run, so it cannot go stale the way a typed list does, and
# so a config that starts naming a new installed path is covered the moment it
# is committed rather than the next time somebody remembers this file.
DEPLOY_DIR_RE="$(printf '%s' "$DEPLOY_DIR" | sed 's/[][\.*^$(){}?+|\\]/\\&/g')"

declared_names() {
  local f hit
  for f in "$REPO_ROOT"/schedule/*.conf "$REPO_ROOT"/.scheduler/*.conf; do
    [ -f "$f" ] || continue
    # Strip comments FIRST, then match. A commented example is not a
    # declaration -- schedule/_paced.dexter.conf discusses installed wrappers
    # at length precisely to say it does NOT use them.
    sed 's/#.*//' "$f" 2>/dev/null \
      | grep -oE "$DEPLOY_DIR_RE/[A-Za-z0-9._-]+"
  done | while read -r hit; do
    [ -n "$hit" ] || continue
    printf '%s\n' "${hit#"$DEPLOY_DIR"/}"
  done | sort -u
}

mapfile -t DECLARED < <(declared_names)

echo
echo "-- declared installs (config names them at $DEPLOY_DIR; absence is a finding) --"
if [ "${#DECLARED[@]}" -eq 0 ]; then
  # Not "clean". Zero declarations means the derivation found nothing, which is
  # a discovery failure wearing the same face as a healthy host -- the very
  # confusion this section was added to end.
  echo "  NONE -- no config assignment names a path under $DEPLOY_DIR."
  echo "  That is a DERIVATION failure, not a clean host: sync-crontab.sh writes"
  echo "  cron lines from these configs, so at least one installed path is expected."
  flagged=$((flagged + 1))
else
  for name in "${DECLARED[@]}"; do
    live="$DEPLOY_DIR/$name"
    src="$REPO_ROOT/bin/$name"
    if [ -e "$live" ] || [ -L "$live" ]; then
      echo "  declared  $name (installed; content checked below)"
      continue
    fi
    if [ ! -e "$src" ]; then
      echo
      echo "NOSRC $name"
      echo "  - config names $live, but this repo has no bin/$name to install from"
      echo "  - nothing can fix this by symlink; the config or the repo is wrong"
      flagged=$((flagged + 1))
      continue
    fi
    # THE CASE THE INTERSECTION COULD NOT SEE.
    echo
    echo "ABSENT $name"
    echo "  - config names $live, and NOTHING IS INSTALLED THERE"
    echo "  - a cron line generated from that config would fail every tick"
    echo "  - fix: ln -sfn '$LINK_ROOT/bin/$name' '$live'"
    flagged=$((flagged + 1))
  done
fi

echo
echo "-- installed files that share a name with this repo's bin/ ------------"

for src in "$REPO_ROOT"/bin/*; do
  [ -f "$src" ] || continue
  name="$(basename "$src")"
  live="$DEPLOY_DIR/$name"
  # -e is false for a dangling symlink, so test -L too
  [ -e "$live" ] || [ -L "$live" ] || continue
  checked=$((checked + 1))

  if [ -L "$live" ]; then
    tgt="$(readlink -f "$live" 2>/dev/null || true)"
    if [ -z "$tgt" ] || [ ! -e "$tgt" ]; then
      echo
      echo "BROKEN $name"
      echo "  - symlink at $live points at '$(readlink "$live")', which does not exist"
      flagged=$((flagged + 1))
    fi
    continue
  fi

  # Regular file: a copy install.
  ref_content=""
  have_ref_content=0
  if [ -n "$REF" ]; then
    if ref_content="$(git -C "$REPO_ROOT" show "$REF:bin/$name" 2>/dev/null)"; then
      have_ref_content=1
    fi
  fi

  if [ "$have_ref_content" = "1" ]; then
    if printf '%s\n' "$ref_content" | diff -q - "$live" >/dev/null 2>&1; then
      echo
      echo "COPY $name"
      echo "  - installed as a COPY, not a symlink -- matches $REF today, but nothing keeps it in sync"
      echo "  - a copy can also disable repo-relative logic inside the script itself (see this script's header)"
      echo "  - fix: ln -sfn '$LINK_ROOT/bin/$name' '$live'"
      flagged=$((flagged + 1))
    else
      changed="$(printf '%s\n' "$ref_content" | diff - "$live" 2>/dev/null | grep -c '^[<>]' || true)"
      live_hash="$(git -C "$REPO_ROOT" hash-object "$live" 2>/dev/null || true)"
      echo
      echo "DRIFT $name"
      echo "  - installed copy at $live differs from $REF ($changed changed line(s))"
      if match="$(matching_commit "$name" "${live_hash:-none}")"; then
        behind="$(git -C "$REPO_ROOT" rev-list --count "$match..$REF" -- "bin/$name" 2>/dev/null || echo '?')"
        echo "  - the installed copy matches $(git -C "$REPO_ROOT" log -1 --format='%h (%ad) %s' --date=short "$match") -- $behind later commit(s) to bin/$name have never gone live"
      else
        echo "  - the installed copy matches no committed version of bin/$name (hand-edited, or older than the last 200 commits touching it)"
      fi
      echo "  - fix: ln -sfn '$LINK_ROOT/bin/$name' '$live'  (review the copy first if it was hand-edited)"
      flagged=$((flagged + 1))
    fi
  else
    if diff -q "$src" "$live" >/dev/null 2>&1; then
      echo
      echo "COPY $name"
      if [ -n "$REF" ]; then
        echo "  - installed as a COPY; bin/$name is not in $REF (new/uncommitted here), matches the working tree"
      else
        echo "  - installed as a COPY, not a symlink -- matches the working tree today, but nothing keeps it in sync"
      fi
      echo "  - fix: ln -sfn '$LINK_ROOT/bin/$name' '$live'"
    else
      echo
      echo "DRIFT $name"
      echo "  - installed copy at $live differs from the working-tree bin/$name"
      echo "  - fix: ln -sfn '$LINK_ROOT/bin/$name' '$live'  (review the copy first if it was hand-edited)"
    fi
    flagged=$((flagged + 1))
  fi
done

echo
echo "== summary: ${#DECLARED[@]} declared install(s), $checked installed file(s) compared, $flagged flagged =="
if [ "$checked" = "0" ] && [ "${#DECLARED[@]}" -gt 0 ]; then
  # Deliberately no longer the whole story, and no longer exit 0. This line used
  # to read "nothing to check" and return clean, which is what let a bare host
  # -- every declared path missing -- pass the deploy checker.
  echo "(nothing in $DEPLOY_DIR shares a name with this repo's bin/, so no CONTENT"
  echo " was compared; the declared-install section above is the check that matters)"
fi
[ "$flagged" -gt 0 ] && exit 1
exit 0
