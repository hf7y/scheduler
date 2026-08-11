#!/usr/bin/env bash
# roster-target.sh -- six probes asking one question about this repo: is a
# project's schedule DECLARED in one roster, or ASSEMBLED from files that
# must agree?
#
# GUARD: has the roster redesign (hf7y/scheduler#79/#80/#81/#78) landed?
# RUNNER: tests/roster-target-witness.sh
# GATE: strict
#   `--strict` is the SUNSET CHECK ALONE -- today's date against SUNSET, no
#   repo reads, no network, no fleet. That is what tests/run-all.sh runs, and
#   it is what makes the self-destruct real rather than a paragraph. The six
#   vision probes stay operator-run: they are expected to be RED until the
#   redesign lands, and a suite that is permanently red is a suite nobody
#   reads. From 2026-08-24 --strict goes red on every run and the ONLY thing
#   that clears it is deleting this file.
# VERIFIED: 2026-08-10 via bash bin/roster-target.sh (0/6 met, 6 to go, 0 blind)
#
# ############################################################################
# WHY THIS EXISTS WHEN realisateur/bin/served-not-cloned.sh ALREADY PROBES IT
# ############################################################################
#
# served-not-cloned.sh asks the ESTATE's question -- is the scheduler served
# as a verb or cloned into ten accounts -- and two of its nine probes
# (`oneroster`, `selfserve`) cover the roster. It is the right file for that
# and this one does not replace it.
#
# It cannot run here. It lives in realisateur, and it reads a scheduler
# checkout by path (`SERVED_SCHEDULER_REPO`), over ssh to monkey, and against
# GitHub. scheduler's own CI has none of those: it has this repository and
# nothing else. So the file that measures whether scheduler's redesign landed
# could not be run by scheduler, by its test suite, or by a pull request
# against it -- only by an operator on mandark who remembered to.
#
# That is the same defect this ecosystem keeps writing down under other
# names: `tests/run-all.sh` exists because three witnesses were built and
# NOTHING ran them, each "a test only a person who already knew its filename
# would ever execute". A vision target nobody's CI can evaluate is that, one
# level up.
#
# So: same commitment, same sunset date, measured from inside. Every probe
# below reads ONLY this repository, which is why it can be a witness here.
#
# ############################################################################
# THE TARGET, IN ONE SENTENCE
# ############################################################################
#
#   One roster Zach maintains decides what dispatches, and `dose <project>`
#   makes a host match it.
#
# Zach, 2026-08-11, quoted in hf7y/realisateur#134:
#
#   > I should be able to ssh zach@monkey and run `dose ecosim` and the newest
#   > ecosim self-installs, updates, starts clearing issues, setting up its
#   > rate should be part of the bootstrap process. it checks one source of
#   > truth. and that's maintained by me.
#
# ############################################################################
# WHAT IS ACTUALLY WRONG TODAY -- measured, not supposed
# ############################################################################
#
# A project is "live" only if THREE files agree: the row's `enabled` flag in
# `schedule/_paced.<host>.conf`, an uncommented `EXEMPT: <p>@<host>` in
# `schedule/FREEZE`, and `CRON_HOST`/`CRON_ACCOUNT` in `schedule/<p>.conf`.
# Each says so in its own header, in the imperative, because the trap has
# fired in BOTH directions:
#
#   - chezz's pause needed edits in two of them -- "either one alone leaves it
#     dark, which is the point of having two"
#   - `_paced.conf`'s TRAP 1 records the inverse: deleting a row ARMS a fixed
#     nightly cron rather than disarming it
#
# A two-key switch that has bitten in both directions is not a safety feature.
# `state` becomes ONE field in the roster, which is what removes it.
#
# ############################################################################
# WHAT MET MEANS, AND WHAT IT DELIBERATELY DOES NOT
# ############################################################################
#
# Every probe is a fact about the repository, never about a document. Writing
# `schedule/ROSTER` as a file full of comments does not move `oneroster`; the
# probe also requires that the files it replaces have stopped deciding
# liveness. A design agreed is not a design landed -- realisateur#134 says
# exactly this: "Do not mark this issue done because the design is agreed."
set -uo pipefail

# ############################################################################
# THE SUNSET. Same date as realisateur/bin/served-not-cloned.sh, deliberately:
# it is the same commitment, and two dates for one promise is how one of them
# quietly becomes the real one. Overridable ONLY so the witness can exercise
# both sides of the date. Moving it in the file is not a maintenance action;
# it is a decision to re-commit, and it needs a commit message that says so.
# ############################################################################
SUNSET="${ROSTER_TARGET_SUNSET:-2026-08-24}"

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SCHED_ROOT="${SCHED_ROOT:-$ROOT}"

QUIET=0; STRICT=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help)
      cat <<EOF
roster-target.sh -- has the roster redesign landed? red until it does, then deletes itself

usage:
  roster-target.sh            probe this repository (the six vision probes)
  roster-target.sh --strict   the SUNSET check alone -- no repo reads; this is the CI gate
  roster-target.sh --quiet    results only

exit codes:
  0  the target is met -- this file has done its job, delete it
  1  UNMET -- expected until the redesign lands
  2  BLIND -- a probe could not be run. This is NEVER "all clear"
  4  SUNSET reached: delete this file, whatever the probes say

the work: hf7y/scheduler#79 (ROSTER) #80 (dose <project>) #81 (per-project rate) #78 (dead-man polarity)
the frame: hf7y/realisateur#134
EOF
      exit 0 ;;
    *) echo "roster-target.sh: unknown flag $a" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

# --- the sunset, first, because it outranks every probe --------------------
today="$(date -Is)"; today="${today%%T*}"
if [[ "$today" > "$SUNSET" || "$today" == "$SUNSET" ]]; then
  say "roster-target: SUNSET reached ($SUNSET). Delete bin/roster-target.sh and"
  say "  tests/roster-target-witness.sh, whatever the probes say. If the redesign"
  say "  landed, the probes are redundant. If it did not, the honest outcome is"
  say "  deletion plus a commit saying so -- not moving the date."
  exit 4
fi
[ "$STRICT" -eq 1 ] && { say "roster-target: sunset $SUNSET not yet reached (today $today)"; exit 0; }

met=0; unmet=0; blind=0
row() { # row <verdict> <name> <detail>
  case "$1" in
    MET)   met=$((met+1));     say "    MET    $2  $3" ;;
    UNMET) unmet=$((unmet+1)); say "    UNMET  $2  $3" ;;
    BLIND) blind=$((blind+1)); say "    BLIND  $2  $3" ;;
  esac
}

ROSTER="$SCHED_ROOT/schedule/ROSTER"

# ---------------------------------------------------------------------------
# 1. ONEROSTER -- schedule/ROSTER exists and carries real rows.
#    A file of comments is not a source of truth, so rows are counted, not
#    the file's presence. hf7y/scheduler#79.
# ---------------------------------------------------------------------------
probe_oneroster() {
  [ -d "$SCHED_ROOT/schedule" ] || { row BLIND oneroster "no schedule/ dir under $SCHED_ROOT"; return; }
  if [ ! -f "$ROSTER" ]; then
    row UNMET oneroster "no schedule/ROSTER"
    return
  fi
  local rows
  rows="$(grep -cvE '^[[:space:]]*(#|$)' "$ROSTER" 2>/dev/null || echo 0)"
  if [ "$rows" -gt 0 ]; then
    row MET oneroster "schedule/ROSTER carries $rows row(s)"
  else
    row UNMET oneroster "schedule/ROSTER exists but has no rows -- a file of comments is not a source of truth"
  fi
}

# ---------------------------------------------------------------------------
# 2. ONEKEY -- liveness is decided in ONE place. Counts the file KINDS that
#    still gate it. This is the both-or-it-stays-dark trap, and it is the
#    probe that stops `oneroster` from being satisfied by adding a fourth
#    file alongside the three. hf7y/scheduler#79.
# ---------------------------------------------------------------------------
probe_onekey() {
  [ -d "$SCHED_ROOT/schedule" ] || { row BLIND onekey "no schedule/ dir under $SCHED_ROOT"; return; }
  local kinds=() n
  # (a) an `enabled` column in any _paced*.conf
  n="$(cat "$SCHED_ROOT"/schedule/_paced*.conf 2>/dev/null | grep -cE '^[a-zA-Z0-9_-]+\|[01]\|' || true)"
  [ "${n:-0}" -gt 0 ] && kinds+=("_paced*.conf enabled column ($n row(s))")
  # (b) EXEMPT lines in FREEZE
  n="$(grep -cE '^[[:space:]]*EXEMPT:' "$SCHED_ROOT/schedule/FREEZE" 2>/dev/null || true)"
  [ "${n:-0}" -gt 0 ] && kinds+=("FREEZE EXEMPT ($n line(s))")
  # (c) CRON_HOST/CRON_ACCOUNT in per-project confs
  n="$(grep -lE '^CRON_(HOST|ACCOUNT)=' "$SCHED_ROOT"/schedule/*.conf 2>/dev/null | grep -cv '/_' || true)"
  [ "${n:-0}" -gt 0 ] && kinds+=("CRON_HOST/CRON_ACCOUNT ($n conf(s))")

  if [ "${#kinds[@]}" -le 1 ]; then
    row MET onekey "liveness decided in ${#kinds[@]} place(s)"
  else
    local joined; printf -v joined '%s; ' "${kinds[@]}"
    row UNMET onekey "${#kinds[@]} file kinds still decide liveness: ${joined%; }"
  fi
}

# ---------------------------------------------------------------------------
# 3. PERPROJECT -- the dispatch rate is per project, not one global with a
#    manual per-account fan-out. RUNNER_CRON in _runner.<host>.conf is that
#    global. hf7y/scheduler#81.
# ---------------------------------------------------------------------------
probe_perproject() {
  [ -d "$SCHED_ROOT/schedule" ] || { row BLIND perproject "no schedule/ dir under $SCHED_ROOT"; return; }
  local globals
  globals="$(grep -lE '^RUNNER_CRON=.+' "$SCHED_ROOT"/schedule/_runner*.conf 2>/dev/null | wc -l)"
  if [ "$globals" -gt 0 ]; then
    row UNMET perproject "RUNNER_CRON is still a global in $globals _runner*.conf file(s)"
  elif [ -f "$ROSTER" ] && grep -qE '^[^#].*\|.*[0-9]+[mh].*\|' "$ROSTER" 2>/dev/null; then
    row MET perproject "rate is a roster column"
  else
    row UNMET perproject "no global RUNNER_CRON, but no per-project rate in the roster either"
  fi
}

# ---------------------------------------------------------------------------
# 4. DOSEPROJECT -- `dose <project>` is a real form. Today dose's subcommand
#    table is DISCOVERED from bin/*.sh, so `dose ecosim` is a usage error, not
#    a convergence. hf7y/scheduler#80.
#
#    Probed against this repo rather than the installed verb, deliberately:
#    the installed build on any given host may be days behind main (mandark's
#    was pinned 5 days back on 2026-08-10), so asking PATH answers "what is
#    deployed here", not "has the work landed".
# ---------------------------------------------------------------------------
probe_doseproject() {
  local src body
  # `dose` is a VERB, so it lives on the `bashified` branch, not on main --
  # realisateur/bin/cut-verb-build.sh builds the verb surface from there.
  # Read it out of git rather than off PATH so this measures the branch, not
  # whatever build this host last installed.
  if body="$(git -C "$SCHED_ROOT" show bashified:bin/dose 2>/dev/null)" && [ -n "$body" ]; then
    src="bashified:bin/dose"
  elif body="$(git -C "$SCHED_ROOT" show origin/bashified:bin/dose 2>/dev/null)" && [ -n "$body" ]; then
    src="origin/bashified:bin/dose"
  elif [ -f "$SCHED_ROOT/bin/dose" ]; then
    body="$(cat "$SCHED_ROOT/bin/dose")"; src="bin/dose"
  else
    row BLIND doseproject "no bin/dose on bashified, origin/bashified, or in the worktree -- cannot say whether the project form landed"
    return
  fi
  if grep -qE 'ROSTER' <<<"$body"; then
    row MET doseproject "$src reads the roster"
  else
    row UNMET doseproject "$src names no ROSTER -- its subcommands are still discovered from bin/*.sh, so \`dose <project>\` is a usage error"
  fi
}

# ---------------------------------------------------------------------------
# 5. ROSTERFROMGH -- the convergence command reads the roster from GitHub,
#    not from a local clone. Both reasons were measured 2026-08-11: zach@monkey's
#    scheduler checkout was on a feature branch five days behind main, so a
#    clone-reading dose would read stale truth on the very host the command is
#    typed on; and reading from GitHub makes the command a bomb -- copy it
#    anywhere, run it, it fetches what it needs. hf7y/scheduler#80.
# ---------------------------------------------------------------------------
probe_rosterfromgh() {
  local hits
  hits="$(grep -rlE 'gh (api|repo view).*(ROSTER|contents)' "$SCHED_ROOT/bin" 2>/dev/null | head -1)"
  if [ -n "$hits" ]; then
    row MET rosterfromgh "$(basename "$hits") reads the roster over gh"
  else
    row UNMET rosterfromgh "nothing in bin/ fetches the roster from GitHub -- a clone-reading convergence reads whatever that host last pulled"
  fi
}

# ---------------------------------------------------------------------------
# 6. DEADMAN -- the switch alarms on SILENCE, not on the CALENDAR.
#    lib/deadman-switch.sh:67 writes expires_at only `if [ ! -f ... ]`, so a
#    HEALTHY run never extends it: every armed account counts down from its
#    first run regardless of how well it is working. That is how all three
#    armed accounts came to be scheduled to self-destruct within 19 hours of
#    each other while working correctly. healthchecks.io has the polarity
#    right; ours is inverted. hf7y/scheduler#78.
# ---------------------------------------------------------------------------
probe_deadman() {
  local f="$SCHED_ROOT/lib/deadman-switch.sh"
  [ -f "$f" ] || { row BLIND deadman "no lib/deadman-switch.sh"; return; }
  # MET requires a stamp write that is NOT guarded by the file being absent --
  # i.e. a successful run refreshes the deadline.
  if grep -qE 'renew_on_success|refresh_expiry|stamp_on_run' "$f" 2>/dev/null; then
    row MET deadman "a successful run refreshes the deadline"
  else
    local guard
    guard="$(grep -n 'if \[ ! -f "\$expires_at_file" \]' "$f" | head -1 | cut -d: -f1)"
    row UNMET deadman "expires_at written only when absent (${f#"$SCHED_ROOT"/}:${guard:-?}) -- counts down from first run, not from last silence"
  fi
}

say "roster-target -- $(date +%Y-%m-%d)  (sunset $SUNSET)"
say "  repo: $SCHED_ROOT"
say ""
probe_oneroster
probe_onekey
probe_perproject
probe_doseproject
probe_rosterfromgh
probe_deadman
say ""

total=$((met + unmet + blind))
say "roster-target: $met/$total met, $unmet to go, $blind blind -- sunset $SUNSET"
if [ "$blind" -gt 0 ]; then
  say "  BLIND is not met. A probe that could not run is never an all-clear."
  exit 2
fi
if [ "$unmet" -eq 0 ]; then
  say "  The target is met. Delete this file and tests/roster-target-witness.sh."
  exit 0
fi
exit 1
