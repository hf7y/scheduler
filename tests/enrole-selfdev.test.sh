#!/usr/bin/env bash
# enrole-selfdev.test.sh -- witness for bin/enrole-selfdev.sh.
#
# HERMETICITY: fully offline. Every case builds a throwaway git repo shaped
# like a scheduler clone under a temp dir. Nothing reads the live ecosystem,
# nothing writes a crontab (--sync is never passed), nothing reaches GitHub.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/../bin" && pwd)/enrole-selfdev.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS: %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$*"; fail=$((fail+1)); }
rc()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing: $3)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpectedly present: $3)" ;; *) ok "$1" ;; esac; }

# A minimal clone: one registered project with a deliberately BLANK batch tier
# and no CRON_* fields -- the exact 2026-08-12 starting state of sequestria.
mkclone() {
  local d="$T/$1"; rm -rf "$d"; mkdir -p "$d/schedule"
  cat > "$d/schedule/widget.conf" <<'EOF'
PROJECT="widget"
PROJECT_KEY="widget"
PROJECT_REPO_PATH="$HOME/Documents/Projects/widget"
REPO_URL="https://github.com/hf7y/widget.git"
SWEEP_JOB_NAME=""
BATCH_JOB_NAME=""
BATCH_PROMPT="/nightly-batch"
BATCH_CRON=""
AUTONOMY_TIER="medium"
EOF
  printf '# rotation\nother|1|1|%s/other/x\n' "$HOMES" > "$d/schedule/_paced.testhost.conf"
  git -C "$d" init -q; git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init
  echo "$d"
}
# SELFDEV_HOME_ROOT keeps the fixture rows out of a real /home, which is also
# what stops bin/hardcoded-home-lint.sh flagging this file's expected strings.
HOMES="$T/homes"
run() { SELFDEV_HOME_ROOT="$HOMES" "$SCRIPT" widget --host testhost --repo "$1" "${@:2}"; }

echo "enrole-selfdev.test.sh"

echo "-- A. --check writes nothing and names every missing field"
C="$(mkclone a)"
OUT="$(run "$C" --check 2>&1)"; RC=$?
rc  "A1 exits 0 with only would-changes" 0 "$RC"
has "A2 names BATCH_JOB_NAME"   "$OUT" 'set BATCH_JOB_NAME="widget-nightly-batch"'
has "A3 names CRON_ACCOUNT"     "$OUT" 'set CRON_ACCOUNT="widget"'
has "A4 names the row it would add" "$OUT" 'add row: widget|1|1|'
[ -z "$(git -C "$C" status --porcelain)" ] && ok "A5 tree is untouched" || bad "A5 --check wrote to the clone"

echo "-- B. --apply sets every field and adds ONE enabled row"
OUT="$(run "$C" --apply 2>&1)"; RC=$?
rc  "B1 exits 0" 0 "$RC"
has "B2 conf carries the job name" "$(cat "$C/schedule/widget.conf")" 'BATCH_JOB_NAME="widget-nightly-batch"'
has "B3 conf carries CRON_HOST"    "$(cat "$C/schedule/widget.conf")" 'CRON_HOST="testhost"'
ROWS="$(grep -c '^widget|' "$C/schedule/_paced.testhost.conf")"
[ "$ROWS" = 1 ] && ok "B4 exactly one row" || bad "B4 expected 1 row, got $ROWS"
has "B5 the row is enabled" "$(grep '^widget|' "$C/schedule/_paced.testhost.conf")" "widget|1|1|$HOMES/widget/Documents/Projects/scheduler/bin/scheduler-run widget batch"
has "B6 prints the undo command" "$OUT" 'undo: git -C'

echo "-- D. IDEMPOTENT: a second --apply changes nothing"
BEFORE="$(git -C "$C" diff)"
OUT="$(run "$C" --apply 2>&1)"; RC=$?
rc  "D1 exits 0" 0 "$RC"
has "D2 says it was already enrolled" "$OUT" "already enrolled (idempotent)"
[ "$BEFORE" = "$(git -C "$C" diff)" ] && ok "D3 the diff is byte-identical after a second run" || bad "D3 the second run changed the tree"
ROWS="$(grep -c '^widget|' "$C/schedule/_paced.testhost.conf")"
[ "$ROWS" = 1 ] && ok "D4 still exactly one row (no append-on-rerun)" || bad "D4 rows multiplied: $ROWS"

echo "-- E. REVERSIBLE: --retire disables the row and KEEPS it"
OUT="$(run "$C" --retire 2>&1)"; RC=$?
rc  "E1 exits 0" 0 "$RC"
has "E2 the row is now disabled" "$(grep '^widget|' "$C/schedule/_paced.testhost.conf")" 'widget|0|1|'
ROWS="$(grep -c '^widget|' "$C/schedule/_paced.testhost.conf")"
[ "$ROWS" = 1 ] && ok "E3 the row was kept, not deleted (deleting un-suppresses the fixed nightly line)" || bad "E3 the row was removed"
has "E4 the conf fields survive retirement" "$(cat "$C/schedule/widget.conf")" 'BATCH_JOB_NAME="widget-nightly-batch"'
OUT="$(run "$C" --apply 2>&1)"
has "E5 --apply re-arms the same row" "$(grep '^widget|' "$C/schedule/_paced.testhost.conf")" 'widget|1|1|'

echo "-- F. it refuses rather than half-writing"
OUT="$(run "$C" --apply --repo "$T/nope" 2>&1)"; RC=$?
rc  "F1 a missing clone exits 5" 5 "$RC"
C2="$(mkclone f)"
OUT="$("$SCRIPT" ghost --host testhost --repo "$C2" --check 2>&1)"; RC=$?
rc  "F2 an unregistered project exits 3" 3 "$RC"
has "F3 says registration is the missing act" "$OUT" "is not registered"
OUT="$(run "$C2" --check --host nosuchhost 2>&1)"; RC=$?
rc  "F4 a host with no _paced.<host>.conf exits 5" 5 "$RC"
has "F5 says why that matters" "$OUT" "another machine's rotation"
echo 'BATCH_MAX_TURNS="9"' >> "$C2/schedule/widget.conf"
OUT="$(run "$C2" --apply 2>&1)"; RC=$?
rc  "F6 an uncommitted edit to the conf it would rewrite exits 5" 5 "$RC"
has "F7 names the in-flight file" "$OUT" "schedule/widget.conf"

printf 'another-project|1|1|%s/another-project/x\n' "$HOMES" >> "$C2/schedule/_paced.testhost.conf"
git -C "$C2" checkout -q -- schedule/widget.conf
OUT="$(run "$C2" --apply 2>&1)"; RC=$?
rc  "F8 a foreign row added to the rotation exits 5" 5 "$RC"
has "F9 quotes the foreign line, not ours" "$OUT" "another-project|1|1|"

echo "-- G. the brief-location finding (the defect that hid behind a 404)"
C3="$(mkclone g)"
mkdir -p "$T/home/Documents/Projects/widget/.claude"
: > "$T/home/Documents/Projects/widget/.claude/FOCUS.md"
OUT="$(HOME="$T/home" run "$C3" --check 2>&1)"; RC=$?
has "G1 flags a brief under .claude/" "$OUT" "an unattended run can read it and CANNOT write it"
rc  "G2 a BAD row makes --check exit 1" 1 "$RC"
mkdir -p "$T/home/Documents/Projects/widget/.scheduler"
mv "$T/home/Documents/Projects/widget/.claude/FOCUS.md" "$T/home/Documents/Projects/widget/.scheduler/FOCUS.md"
OUT="$(HOME="$T/home" run "$C3" --check 2>&1)"; RC=$?
has "G3 accepts a brief under .scheduler/" "$OUT" "brief at .scheduler/FOCUS.md"
rc  "G4 and exits 0 again" 0 "$RC"
rm "$T/home/Documents/Projects/widget/.scheduler/FOCUS.md"
: > "$T/home/Documents/Projects/widget/CLAUDE.md"
OUT="$(HOME="$T/home" run "$C3" --check 2>&1)"; RC=$?
has "G5 accepts a brief at repo-root CLAUDE.md, the live convention" "$OUT" "brief at CLAUDE.md"
rc  "G6 and exits 0" 0 "$RC"

echo "-- I. a rotation file with NO trailing newline"
# THE 2026-09-02 DEFECT: schedule/_paced.monkey.conf ended without a newline,
# so >> fused the new row onto the last one -- "dcp-gate-site|1|1|...batch" +
# "american-cycle|1|1|..." became ONE line that still parses as a row named
# after neither project. Every fixture above ends in a newline, which is why
# every earlier case passed while the live file was being corrupted.
C4="$(mkclone i)"
printf '# rotation\nother|1|1|%s/other/x' "$HOMES" > "$C4/schedule/_paced.testhost.conf"
git -C "$C4" -c user.email=t@t -c user.name=t commit -qam "no trailing newline"
run "$C4" --apply >/dev/null 2>&1
LAST_OTHER="$(grep -c '^other|1|1|[^|]*/other/x$' "$C4/schedule/_paced.testhost.conf")"
[ "$LAST_OTHER" = 1 ] && ok "I1 the previous last row is left intact" \
                      || bad "I1 the previous last row was fused with the new one"
ROWS="$(grep -c '^widget|' "$C4/schedule/_paced.testhost.conf")"
[ "$ROWS" = 1 ] && ok "I2 widget gets a row of its own" \
                || bad "I2 expected 1 widget row, got $ROWS"

echo "-- H. the argument contract (cli-guard)"
"$SCRIPT" widget --not-a-real-flag >/dev/null 2>&1; rc "H1 unknown flag exits 2" 2 "$?"
"$SCRIPT" --help >/dev/null 2>&1;                   rc "H2 --help exits 0" 0 "$?"
"$SCRIPT" >/dev/null 2>&1;                          rc "H3 no project named exits 2" 2 "$?"

echo
printf 'enrole-selfdev: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
