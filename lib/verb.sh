#!/usr/bin/env bash
# verb.sh -- the shared runtime every bashified utility sources.
#
# One copy of the argument grammar, the cost boundary, and the failure
# vocabulary, so nineteen utilities cannot drift into nineteen dialects.
# Config is read here and nowhere else.
#
# WHAT --summon ACTUALLY IS (read this before the cost boundary below;
# stating it only as a cost boundary is what made it misread -- Zach,
# interactive, 2026-07-31):
#
#   A summon is how a verb WRITES ITSELF FROM THE INSIDE.
#
#   In this ecosystem the man page is written BEFORE the utility works, and
#   the utility is judged against the page. So a page routinely contracts an
#   action with no mechanism behind it yet. That is the normal case, not a
#   defect. When a caller invokes such an action:
#
#     without --summon  the verb exits 3 and PRINTS THE SUMMON it would have
#                       made. Nothing is spent. The gap is named, not hidden.
#     with --summon     an agent is summoned to perform the action AND to
#                       leave behind a durable mechanism that performs it
#                       WITHOUT an agent next time (basheur Law 2: every
#                       summon leaves residue; residue becomes an impl).
#
#   So the flag does not merely buy one answer. It buys the answer plus the
#   machine that makes the next answer free. A verb carrying --summon is a
#   verb still under construction by its own callers, and the correct
#   direction of travel is that the flag stops costing anything, one
#   subcommand at a time, because the mechanism now exists.
#
#   Escalate through basheur -- `basheur run --summon <contract>` -- never by
#   contacting a model directly. basheur is the contract store that decides
#   MECHANIZED (exec the impl, spend nothing, say so) versus AGENT (summon).
#   A verb that calls a model itself has re-animated its own project, which
#   is what Law 3 forbids.
#
# THE COST BOUNDARY (the second thing this file exists for):
#   Nothing in a bashified utility may spend money implicitly. A utility
#   that CAN spend declares VERB_CAN_SUMMON=1 and gains --summon; one that
#   cannot does not carry the flag at all.
#
#   --summon means "spend IF AND ONLY IF the contract cannot be fulfilled
#   mechanically" -- a grant of permission, never an instruction to spend.
#   On an already-mechanized action it costs zero and says so on stderr.
#   The other reading ("spend because I said so") looks identical at the
#   prompt and diverges completely in the bill: under it, de-animation stops
#   showing up in the only place it was ever going to show up.
#
#   Because nearly every verb can now escalate, the presence of --summon no
#   longer sorts tools into spending and non-spending. The informative
#   question moved from WHETHER a tool spends to WHICH OF ITS SUBCOMMANDS do,
#   which is why a man page must name them and the page test checks it.
#
#   Short form is deliberately ABSENT. `-s` collides with existing tools
#   and `-S` differs from it by one shift key, which is an unacceptable
#   property for the only flag that spends real money. Typing the whole
#   word IS the deliberateness.

set -uo pipefail

VERB_NAME="${VERB_NAME:?verb.sh: VERB_NAME must be set before sourcing}"
VERB_SUMMARY="${VERB_SUMMARY:-}"
VERB_CAN_SUMMON="${VERB_CAN_SUMMON:-0}"
VERB_SUMMON_COST="${VERB_SUMMON_COST:-unmeasured}"

VERB_SUMMON=0        # did the caller authorise spending?
VERB_JSON=0
VERB_QUIET=0

# ---------------------------------------------------------------- failing
# Exit codes are part of the contract. An exit-0 no-op is the failure this
# ecosystem records more than any other, so every one of these is loud.
#   0  the promise was kept
#   2  usage error (the caller is wrong)
#   3  this needs a summon and did not get one -- A FINDING, NOT AN ERROR
#   4  GAP: the tooling to keep this promise does not exist yet
#   5  the promise was broken (ran, produced a wrong or partial answer)
#   6  BLIND: cannot read the domain, so cannot report on it
verb_die()   { printf '%s: %s\n' "$VERB_NAME" "$*" >&2; exit 2; }
verb_gap()   { printf '%s: GAP: %s\n' "$VERB_NAME" "$*" >&2
               printf '%s: no tooling exists for this yet; see GAPS.md\n' "$VERB_NAME" >&2
               exit 4; }
verb_broke() { printf '%s: BROKEN: %s\n' "$VERB_NAME" "$*" >&2; exit 5; }
verb_blind() { printf '%s: BLIND: %s\n' "$VERB_NAME" "$*" >&2
               printf '%s: this is "I cannot see", NOT "nothing to report".\n' "$VERB_NAME" >&2
               exit 6; }

# ------------------------------------------------------------ the summon
# Refuse rather than spend. Callers that want the money spent must say so.
verb_need_summon() {
  local what="$1"
  [ "$VERB_CAN_SUMMON" = 1 ] || verb_die "internal: verb_need_summon in a utility that declares no summon"
  if [ "$VERB_SUMMON" = 1 ]; then
    return 0
  fi
  printf '%s: this needs a summon: %s\n' "$VERB_NAME" "$what" >&2
  printf '%s: no mechanism for it exists yet, so nothing was done and nothing was spent.\n' "$VERB_NAME" >&2
  printf '%s: cost if summoned: %s\n' "$VERB_NAME" "$VERB_SUMMON_COST" >&2
  printf '%s: re-run with --summon to have an agent perform it AND leave behind\n' "$VERB_NAME" >&2
  printf '%s: the mechanism that performs it without an agent next time.\n' "$VERB_NAME" >&2
  exit 3
}

# ------------------------------------------------------------ arg parsing
# Hand-rolled rather than getopts: getopts cannot express "--summon has no
# short form on purpose", and silently accepting a bundled cost flag is
# exactly the misparse that would spend money the caller never authorised.
verb_parse() {
  VERB_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --summon)
        [ "$VERB_CAN_SUMMON" = 1 ] || verb_die "--summon: this utility never spends; the flag does not exist here"
        VERB_SUMMON=1 ;;
      --summon=*) verb_die "--summon takes no value" ;;
      -s|-S|-\$|--sum|--summ|--summo)
        # Named explicitly so a near-miss FAILS rather than being ignored.
        verb_die "no short or abbreviated form of --summon exists. Spell it out; that is the point." ;;
      --json)    VERB_JSON=1 ;;
      --quiet|-q) VERB_QUIET=1 ;;
      -h|--help) verb_usage; exit 0 ;;
      --version) printf '%s (bashified)\n' "$VERB_NAME"; exit 0 ;;
      --) shift; VERB_ARGS+=("$@"); break ;;
      -*) verb_die "unknown flag: $1  (try --help)" ;;
      *)  VERB_ARGS+=("$1") ;;
    esac
    shift
  done
}

verb_usage() {
  printf '%s -- %s\n\n' "$VERB_NAME" "$VERB_SUMMARY"
  printf 'usage: %s\n\n' "${VERB_USAGE:-$VERB_NAME [flags]}"
  printf 'flags:\n'
  printf '  --json        machine-readable output\n'
  printf '  --quiet, -q   suppress commentary; results only\n'
  printf '  -h, --help    this text\n'
  printf '  --version     print version\n'
  if [ "$VERB_CAN_SUMMON" = 1 ]; then
    printf '  --summon      permit an agent to be summoned for an action this\n'
    printf '                utility does not yet implement -- it performs the\n'
    printf '                action and leaves behind the mechanism that will\n'
    printf '                perform it next time without an agent.\n'
    printf '                Spends real money ONLY if no mechanism exists yet\n'
    printf '                (cost: %s). Already-mechanized work costs nothing\n' "$VERB_SUMMON_COST"
    printf '                and says so. Without this flag such an action\n'
    printf '                exits 3 and prints the summon it would have made.\n'
    printf '                No short form exists, deliberately.\n'
  else
    printf '\nThis utility cannot spend money. It has no --summon flag.\n'
  fi
  printf '\nexit: 0 kept  2 usage  3 needs-summon  4 gap  5 broken  6 blind\n'
  printf 'see: man %s\n' "$VERB_NAME"
}
