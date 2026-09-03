#!/usr/bin/env bash
# Witness for @@MILESTONE-QUEUE@@ substitution in bin/scheduler-run.
#
# THE DEFECT THIS RETIRES. `gh issue list` returns number, state, title,
# labels and updated -- no milestone column -- sorted newest first. So an
# issue filed this morning and the generation every other project is waiting
# on are indistinguishable at the moment an agent picks its work. Measured
# 2026-09-03: scheduler took 65 sessions in seven days, second-highest in the
# fleet, and left four of Zach's answered decisions rotting while working
# issues filed that same morning. It was never short of turns.
#
# WHY DATA AND NOT A RULE. A prose rule saying "prefer the milestone" is a
# rule an agent must remember to apply against a listing that still hides the
# milestone. This injects the listing itself, so the ordering is visible
# rather than instructed -- hf7y/scheduler#522's complaint, answered rather
# than added to.
#
# HERMETICITY: full. `gh` is stubbed on PATH per case; nothing reaches the
# network, and case 2 proves the dispatcher survives a gh that does not work.
#
# Asserts:
#   1. the marker resolves to the milestone listing the stub reports, in
#      place, with prose before and after surviving in order.
#   2. FAILS OPEN: a gh that exits non-zero leaves a legible fallback, the
#      raw marker never survives, and dispatch still exits 0.
#   3. the repo slug is derived from REPO_URL for ssh and https forms, with
#      and without a .git suffix.
#   4. no marker in the prompt means gh is never invoked -- 19 accounts pay
#      this cost on every batch, so it must be opt-in by presence.
#   5. real wiring: schedule/_standing-rules.md carries the marker, so every
#      conf with USES_STANDING_RULES=1 resolves it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule" "$TMP/stub"
cp "$RUN" "$FX/bin/scheduler-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
printf 'printf "%%s" "$PROMPT"\nexit 0\n' > "$FX/lib/sweep-loop-common.sh"

mkconf() {  # $1=name $2=repo_url, rest=lines
  local name="$1" url="$2"; shift 2
  { echo "REPO_URL=\"$url\""; printf '%s\n' "$@"; } > "$FX/schedule/$name.conf"
}

stub_gh() {  # $1=mode: ok | fail
  cat > "$TMP/stub/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh-calls"
[ "$1" = fail ] && exit 1
case "\$*" in
  *milestones*) printf 'v2\t10\nregulation\t3\n' ;;
  *"--milestone v2"*)          printf '#304 #350\n' ;;
  *"--milestone regulation"*)  printf '#348 #360\n' ;;
  *) printf '\n' ;;
esac
exit 0
STUB
  chmod +x "$TMP/stub/gh"
  : > "$TMP/gh-calls"
}

run() { ( cd "$FX" && PATH="$TMP/stub:$PATH" bash bin/scheduler-run "$1" "$2" 2>"$TMP/err" ); }

echo "== case 1: the marker resolves to the listing, in place"
stub_gh ok
mkconf one "https://github.com/hf7y/scheduler.git" 'BATCH_JOB_NAME="one-batch"' \
  'BATCH_PROMPT="BEFORE.
@@MILESTONE-QUEUE@@
AFTER."'
out="$(run one batch)"
case "$out" in
  "BEFORE."*"v2 (10 open): #304 #350"*"regulation (3 open): #348 #360"*"AFTER.") \
    ok "listing resolved in place, prose either side intact, order preserved" ;;
  *) bad "marker did not resolve as expected: [$out]" ;;
esac
case "$out" in *'@@MILESTONE-QUEUE@@'*) bad "raw marker leaked into the prompt" ;;
              *) ok "no raw marker token left in the prompt" ;; esac
case "$out" in *"ship together and outrank"*) ok "the listing says what membership means" ;;
              *) bad "listing carried no statement of what a milestone means" ;; esac

echo "== case 2: a broken gh fails OPEN -- dispatch still happens"
stub_gh fail
out="$(run one batch)"; rc=$?
[ "$rc" = 0 ] && ok "dispatch exited 0 despite gh failing" || bad "dispatch exited $rc when gh failed"
case "$out" in *'@@MILESTONE-QUEUE@@'*) bad "raw marker survived the gh failure" ;;
              *) ok "marker still replaced when gh fails" ;; esac
case "$out" in *"could not be read at dispatch"*) ok "fallback names the failure and how to check by hand" ;;
              *) bad "fallback text missing: [$out]" ;; esac
case "$out" in "BEFORE."*"AFTER.") ok "surrounding prompt survived the failure" ;;
              *) bad "prompt damaged by the failure path" ;; esac

echo "== case 3: the slug is derived from REPO_URL, ssh and https alike"
for url in "git@github.com:hf7y/ecosim.git" "https://github.com/hf7y/apms-2173.git" \
           "https://github.com/hf7y/dcp-gate-site"; do
  want="${url##*[:/]}"; want="${want%.git}"
  stub_gh ok
  mkconf slug "$url" 'BATCH_JOB_NAME="slug-batch"' 'BATCH_PROMPT="@@MILESTONE-QUEUE@@"'
  run slug batch >/dev/null
  if grep -q "hf7y/$want" "$TMP/gh-calls" 2>/dev/null; then
    ok "REPO_URL $url resolved to hf7y/$want"
  else
    bad "REPO_URL $url did not resolve to hf7y/$want -- calls: $(tr '\n' ';' < "$TMP/gh-calls")"
  fi
done

echo "== case 4: no marker means gh is never called"
stub_gh ok
mkconf nomark "https://github.com/hf7y/scheduler.git" 'BATCH_JOB_NAME="nomark-batch"' \
  'BATCH_PROMPT="NOTHING TO SUBSTITUTE."'
run nomark batch >/dev/null
if [ -s "$TMP/gh-calls" ]; then
  bad "gh was invoked with no marker present -- 19 accounts would pay this every batch"
else
  ok "gh not invoked when the prompt carries no marker"
fi

echo "== case 5: real wiring -- the standing rules carry the marker"
if grep -q '@@MILESTONE-QUEUE@@' "$ROOT/schedule/_standing-rules.md"; then
  ok "schedule/_standing-rules.md carries the marker, so USES_STANDING_RULES confs resolve it"
else
  bad "schedule/_standing-rules.md does not carry @@MILESTONE-QUEUE@@ -- the rule reaches nobody"
fi

echo
echo "milestone-queue-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
