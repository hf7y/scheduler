#!/usr/bin/env bash
# Witness: a project conf must not EXECUTE anything when sourced.
#
# bin/scheduler-run does `source "$CONF"`, so a conf is code, not data. The
# risky part is that most of a conf is prose -- a BATCH_PROMPT is a paragraph
# of English sitting inside a double-quoted shell string, where four
# characters stay live: \ " ` and $.
#
# Both failure modes happened while writing the 2026-08-06 issue-driven
# briefs, neither was caught by `bash -n` (both are valid syntax), and each
# would have run as the dispatching account on every tick:
#
#   * a backtick pair around a word -- "issues labelled `observation`" --
#     is a command substitution. It ran `observation`. An ODD number of
#     backticks is worse: it swallows following lines until the next one,
#     so a comment can reach forward and execute a live config line.
#   * an unescaped inner quote -- "first in ideas may be obviated" --
#     closes the string, and the rest of the sentence becomes argv.
#
# The check is deliberately behavioural rather than a grep for backticks:
# comments legitimately contain them all over this directory, and a lint
# that flags those would be turned off within a week.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Only confs that are actually SOURCED. The _paced/_sweep/_runner files are
# parsed line-wise (`while IFS='|' read`), never sourced, so a stray backtick
# in their prose is inert -- asserting on them would be asserting a rule that
# does not apply.
cd "$ROOT" || exit 1
shopt -s nullglob
CONFS=()
for f in schedule/*.conf; do
  case "$(basename "$f")" in _*) continue ;; esac
  CONFS+=("$f")
done
[ "${#CONFS[@]}" -gt 0 ] || { echo "no project confs found -- that is a failure, not a pass"; exit 1; }

echo "== every sourced project conf must be side-effect free (${#CONFS[@]} confs)"
for f in "${CONFS[@]}"; do
  out="$(bash -c "set -u; . '$ROOT/$f'" 2>&1 >/dev/null)"
  if [ -z "$out" ]; then
    ok "$(basename "$f") sources cleanly"
  else
    bad "$(basename "$f") EXECUTES something on source: $(printf '%s' "$out" | head -1)"
  fi
done

echo "== the check actually bites"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf 'BATCH_PROMPT="work the `whoami` queue"\n' > "$TMP/backtick.conf"
out="$(bash -c "set -u; . '$TMP/backtick.conf'" 2>&1 >/dev/null; true)"
# A backtick substitution of `whoami` succeeds silently, so stderr is empty --
# prove it by observing the EXPANSION, which is what a prompt would leak.
# shellcheck disable=SC1090
( set -u; . "$TMP/backtick.conf" ) >/dev/null 2>&1
val="$( ( . "$TMP/backtick.conf" >/dev/null 2>&1; printf '%s' "${BATCH_PROMPT:-}" ) )"
if [ "$val" = 'work the `whoami` queue' ]; then
  bad "backticks were NOT expanded -- this witness cannot detect the real bug"
else
  ok "a backticked conf really does execute (got: $val)"
fi
# The inner-quote fixture must be MULTI-LINE, which is the shape the real bug
# had. On one line bash just concatenates ("a "b" c" -> abc) and nothing runs;
# it is the following line, now outside the string, that becomes a command.
{ printf 'BATCH_PROMPT="Zach said "first in ideas may be obviated\n'
  printf '   before they can be realized." Do NOT take the oldest."\n'; } > "$TMP/quote.conf"
out="$(bash -c "set -u; . '$TMP/quote.conf'" 2>&1 >/dev/null)"
[ -n "$out" ] && ok "an unescaped inner quote is detected ($(printf '%s' "$out" | head -1))" \
              || bad "an unescaped inner quote went undetected"

echo
echo "conf-sources-clean-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
