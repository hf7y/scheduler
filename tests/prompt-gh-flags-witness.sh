#!/usr/bin/env bash
# Witness: every `gh` flag written into a dispatched prompt is a flag `gh`
# actually has.
#
# THE DEFECT THIS RETIRES, shipped and merged on 2026-08-11 within the hour.
# hf7y/scheduler#101 widened bibliothecaire's selector -- a correct fix for a
# real measured problem, the account had been an armed no-op -- and wrote the
# fallback as:
#
#     gh issue list --repo hf7y/bibliothecaire --state open \
#        --exclude-labels in-progress,deferred
#
# There is no `--exclude-labels`. `gh` exits 2 with "unknown flag" and lists
# nothing. The fix for an armed no-op would have been an armed ERROR: the same
# silence, one layer further in, and harder to see because now there is a
# plausible-looking command in the log.
#
# WHY NOTHING CAUGHT IT. `suites` was green on that PR and would have been
# green on any wording, because no test in this repo has ever run a command a
# BATCH_PROMPT contains. A prompt is executable instruction that ships to an
# unattended agent, and it was the only executable thing here with no linter
# pointed at it. The conf's own text is checked for shell-injection
# (tests/conf-sources-clean-witness.sh) and for duplication across confs
# (tests/conf-prompt-duplication-witness.sh); nothing checked whether the
# commands are real.
#
# WHAT THIS CHECKS, and deliberately not more: for every `gh <group> <cmd>`
# line in every conf's prompt fields, every `--flag` on that line appears in
# that subcommand's own `--help`. It does not run the commands (they hit the
# network and mutate issues), does not check flag VALUES, and does not check
# non-gh commands. Flag existence is the failure that shipped, it is checkable
# offline against the installed binary, and it is checkable cheaply.
#
# BLIND, NEVER GREEN, when `gh` is absent. A run that cannot ask the binary
# what flags it has has not verified anything, and "no gh here" must not look
# like "all flags valid" -- that is the exit-0 no-op this estate refuses.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEDULE="${PROMPT_FLAGS_SCHEDULE:-$ROOT/schedule}"

if ! command -v gh >/dev/null 2>&1; then
  echo "prompt-gh-flags-witness: BLIND -- gh is not on PATH, so no flag could be"
  echo "  verified against it. This is 'I cannot see', not 'everything is fine'."
  exit 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# Cache one --help per subcommand; `gh` is slow enough that re-asking per flag
# is noticeable across a dozen confs.
declare -A HELP_CACHE
help_for() {  # $1=group $2=cmd
  local key="$1 $2"
  [ -n "${HELP_CACHE[$key]:-}" ] || HELP_CACHE[$key]="$(gh "$1" "$2" --help 2>&1)"
  printf '%s' "${HELP_CACHE[$key]}"
}

CHECKED=0
shopt -s nullglob
for conf in "$SCHEDULE"/*.conf; do
  name="$(basename "$conf")"
  case "$name" in _*) continue ;; esac   # _paced/_runner/_usage carry no prompts

  # Read the raw file, not a sourced value: sourcing a conf executes it, which
  # is the hazard conf-sources-clean-witness.sh exists for. Grep the text.
  while IFS= read -r line; do
    # Normalise: strip leading whitespace and any trailing backslash-continuation.
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in "gh "*) ;; *) continue ;; esac

    group="$(printf '%s' "$line" | awk '{print $2}')"
    cmd="$(printf '%s' "$line" | awk '{print $3}')"
    case "$group" in ''|-*) continue ;; esac
    case "$cmd"   in ''|-*) continue ;; esac

    helptext="$(help_for "$group" "$cmd")"
    case "$helptext" in
      *"unknown command"*|*"Unknown command"*)
        bad "$name: 'gh $group $cmd' is not a gh subcommand"
        CHECKED=$((CHECKED+1))
        continue
        ;;
    esac

    for word in $line; do
      case "$word" in
        --*) ;;
        *) continue ;;
      esac
      flag="${word%%=*}"
      CHECKED=$((CHECKED+1))
      if printf '%s' "$helptext" | grep -qe "$flag\b"; then
        ok "$name: gh $group $cmd $flag"
      else
        bad "$name: 'gh $group $cmd' has no $flag -- gh exits 2 'unknown flag' and lists NOTHING"
      fi
    done
  done < "$conf"
done

echo
if [ "$CHECKED" -eq 0 ]; then
  echo "prompt-gh-flags-witness: BLIND -- no gh invocation found in any prompt."
  echo "  Every conf carrying a prompt uses gh; finding none means this witness"
  echo "  stopped matching the file shape, not that the prompts got simpler."
  exit 1
fi
echo "prompt-gh-flags-witness: $PASS passed, $FAIL failed ($CHECKED flag(s) checked)"
[ "$FAIL" -eq 0 ]
