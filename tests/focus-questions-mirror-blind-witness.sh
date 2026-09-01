#!/usr/bin/env bash
# Witness for the 2026-08-20 fix: sync-crontab.sh's local focus/*.md and
# questions/*.md symlink farm was retired whole by #244 (the coordinator-
# file sunset, #234), but bin/scheduler's cmd_glance and cmd_status kept
# reading those exact paths -- so every project's NEXT UP/ETA column and a
# file-channel project's "open questions" section in `scheduler status`
# silently rendered as "nothing here" (`-`, "no QUESTIONS.md symlink
# found")
# instead of the true answer: this account cannot read the file at all
# (every project's home is 0700 -- verified 2026-08-20 -- so there is no
# path back to the data now that the mirror is gone).
#
# That is exactly the "BLIND reported as OK" failure this file's own
# QUESTIONS column comment already warns against for a DIFFERENT column.
# This witness asserts the fix: with no focus/ or questions/ directory
# present, these three surfaces say so (BLIND) instead of implying an
# empty backlog / no open questions.
#
# Section 3 (added 2026-08-25, #234) covers a further site the original fix
# missed: the bare `scheduler focus <project>` verb itself still called
# open_file() unconditionally and failed with open_file's generic "no file
# yet at ..." -- which reads as "$proj has no FOCUS.md", not "this command
# can no longer see one". Same BLIND framing now applied there too.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

mkdir -p "$TMP/root/schedule" "$TMP/proj" "$TMP/home"
ln -s "$ROOT/bin" "$TMP/root/bin"
ln -s "$ROOT/lib" "$TMP/root/lib"
printf 'witnessproj|1|3\n' > "$TMP/root/schedule/_paced.conf"
{
  echo "PROJECT_REPO_PATH=\"$TMP/proj\""
  echo 'SCHEDULER_SUBDIR=".scheduler"'
  echo 'ANSWER_CHANNEL="file"'
} > "$TMP/root/schedule/witnessproj.conf"
# No $TMP/root/focus and no $TMP/root/questions -- the retired-mirror state
# this witness exists to cover, not a fixture bug.

run() { SCHED_ROOT="$TMP/root" HOME="$TMP/home" "$ROOT/bin/scheduler" "$@"; }

echo "== 1. cmd_glance: NEXT UP / ETA render '?' (BLIND), never '-' (empty)"
out="$(run 2>&1)"
row="$(printf '%s\n' "$out" | grep -E '^\s*witnessproj\s')"
if [ -z "$row" ]; then
  bad "glance printed no row for witnessproj -- output: $out"
else
  # Columns: PROJECT QUESTIONS LAST RUN ETA NEXT UP -- ETA and NEXT UP are
  # the last two fields.
  eta="$(printf '%s' "$row" | awk '{print $(NF-1)}')"
  next="$(printf '%s' "$row" | awk '{print $NF}')"
  if [ "$eta" = "?" ]; then ok "ETA column is '?' (BLIND)"; else bad "ETA column is '$eta', not '?' -- row: $row"; fi
  if [ "$next" = "?" ]; then ok "NEXT UP column is '?' (BLIND)"; else bad "NEXT UP column is '$next', not '?' -- row: $row"; fi
fi

echo "== 2. cmd_status: file-channel 'open questions' says BLIND, not silent-empty"
out="$(run status witnessproj 2>&1)"
if printf '%s' "$out" | grep -qi 'blind'; then
  ok "status's open-questions section says BLIND when the questions/ mirror is absent"
else
  bad "status did not say BLIND for a file-channel project -- output: $out"
fi
if printf '%s' "$out" | grep -q 'no QUESTIONS.md symlink found'; then
  bad "status still uses the old 'no QUESTIONS.md symlink found' phrasing (reads as 'nothing open')"
else
  ok "status does not claim nothing is open when it never looked"
fi

echo "== 3. bare 'scheduler focus <project>' verb: BLIND, not open_file's generic 'no file yet'"
out="$(run focus witnessproj 2>&1)"
rc=0; run focus witnessproj >/dev/null 2>&1 || rc=$?
if printf '%s' "$out" | grep -qi 'blind'; then
  ok "focus verb says BLIND when the focus/ mirror is absent"
else
  bad "focus verb did not say BLIND -- output: $out"
fi
if printf '%s' "$out" | grep -q 'no file yet at'; then
  bad "focus verb still uses open_file's generic 'no file yet at ...' (implies empty, not unreadable)"
else
  ok "focus verb does not fall through to open_file's generic missing-file message"
fi
[ "$rc" -ne 0 ] && ok "focus verb exits non-zero on BLIND" || bad "focus verb exited 0 on BLIND"

echo "== 4. 'scheduler -q' (questions overview): file-channel project reported BLIND, not 'nothing open'"
out="$(run -q 2>&1)"
if printf '%s' "$out" | grep -qi 'blind'; then
  ok "-q overview says BLIND for the file-channel project it never read"
else
  bad "-q overview did not say BLIND -- output: $out"
fi
if printf '%s' "$out" | grep -qE '^\s*nothing open:.*witnessproj'; then
  bad "-q overview still lists the unreadable project under 'nothing open' -- output: $out"
else
  ok "-q overview does not claim witnessproj has nothing open"
fi

echo "== 5. bare 'scheduler questions <project>' verb: BLIND, not open_file's generic 'no file yet'"
out="$(run questions witnessproj 2>&1)"
rc=0; run questions witnessproj >/dev/null 2>&1 || rc=$?
if printf '%s' "$out" | grep -qi 'blind'; then
  ok "questions verb says BLIND when the questions/ mirror is absent"
else
  bad "questions verb did not say BLIND -- output: $out"
fi
if printf '%s' "$out" | grep -q 'no file yet at'; then
  bad "questions verb still uses open_file's generic 'no file yet at ...' (implies empty, not unreadable)"
else
  ok "questions verb does not fall through to open_file's generic missing-file message"
fi
[ "$rc" -ne 0 ] && ok "questions verb exits non-zero on BLIND" || bad "questions verb exited 0 on BLIND"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
