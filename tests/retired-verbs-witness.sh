#!/usr/bin/env bash
# Witness: the four `bin/scheduler` verbs retired by hf7y/scheduler#377 stay
# retired -- refused at the dispatch, absent from `--help`, absent from
# tab-completion. Each died because its SUBJECT died, not because nobody
# liked it, so a re-add would be a re-add of the dead subject:
#   explain     narrated the focus/questions symlink farm (#244), the `> `
#               reply round-trip (#66) and bin/scheduler-dev-cycle.sh (absent)
#   overview    read $SCHED_ROOT/focus/, retired whole by #244
#   -i --receipt  zero callers, zero `receipts` issues estate-wide since #41
#   questions <p> <n>  jumped into $SCHED_ROOT/questions/, retired by #244
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

mkdir -p "$TMP/root/schedule" "$TMP/bin"
ln -s "$ROOT/bin" "$TMP/root/bin"
ln -s "$ROOT/lib" "$TMP/root/lib"
printf 'witnessproj|1|1\n' > "$TMP/root/schedule/_paced.conf"
{
  echo 'REPO_URL="https://github.com/hf7y/witnessproj.git"'
  echo 'ANSWER_CHANNEL="file"'
} > "$TMP/root/schedule/witnessproj.conf"

# A gh that says yes to everything: if a retired path still ran, it would
# succeed here rather than fail for a missing credential.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "issue" ] && [ "$2" = "create" ] && echo "https://github.com/hf7y/witnessproj/issues/1"
exit 0
STUB
chmod +x "$TMP/bin/gh"

run_sched() {
  ( cd "$TMP" && PATH="$TMP/bin:$PATH" SCHED_ROOT="$TMP/root" HOME="$TMP" \
      EDITOR=true "$ROOT/bin/scheduler" "$@" )
}

echo "== 1. the dispatch refuses each retired name"
for verb in explain -e overview -o; do
  out="$(run_sched "$verb" witnessproj 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "unknown command"; then
    ok "\`scheduler $verb\` is an unknown command (rc=2)"
  else
    bad "\`scheduler $verb\` exited $rc: $(printf '%s' "$out" | head -1)"
  fi
done

echo "== 2. \`-i --receipt\` records NOTHING -- it is not silently an idea named '--receipt'"
out="$(run_sched -i --receipt witnessproj "a receipt" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then ok "exits non-zero"; else bad "exited 0: $out"; fi
if printf '%s' "$out" | grep -q "filed as a GitHub issue"; then
  bad "filed an issue anyway: $out"
else
  ok "filed nothing"
fi

echo "== 3. \`questions <p> <n>\` no longer jumps -- the mirror it jumped into is gone"
out="$(run_sched questions witnessproj 3 2>&1)"; rc=$?
# #396: fallthrough now says BLIND, not open_file's generic "no file yet at ...".
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "blind"; then
  ok "the trailing number is inert; the absent questions/ mirror is what fails, BLIND not silent"
else
  bad "unexpected rc=$rc: $(printf '%s' "$out" | head -1)"
fi

echo "== 4. nothing still advertises them"
help="$(run_sched --help 2>&1)"
for adv in 'explain, -e' 'overview <project>' -- '--receipt' 'questions [project] [n]'; do
  [ "$adv" = "--" ] && continue
  if printf '%s' "$help" | grep -qF -- "$adv"; then
    bad "\`--help\` still advertises: $adv"
  else
    ok "\`--help\` does not advertise: $adv"
  fi
done
completion_verbs="$(source "$ROOT/bin/scheduler-completion.bash"; SCHEDULER_COMPLETION_BIN="$ROOT/bin/scheduler" _scheduler_subcommands)"
for name in explain blockers; do
  if grep -qxF "$name" <<<"$completion_verbs"; then
    bad "tab-completion still offers \`$name\`"
  else
    ok "tab-completion does not offer \`$name\`"
  fi
done

echo "== 5. no orphaned implementation survives the verbs"
for fn in cmd_explain cmd_overview cmd_idea_receipt cmd_questions_jump; do
  if grep -q "$fn" "$ROOT/bin/scheduler"; then
    bad "$fn is still defined or referenced in bin/scheduler"
  else
    ok "$fn is gone from bin/scheduler"
  fi
done

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
