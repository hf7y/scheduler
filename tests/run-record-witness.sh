#!/usr/bin/env bash
# Witness for lib/run-record.sh -- the COMPUTED verdict.
#
# What this exists to prevent, in order of how badly it would hurt:
#
#  1. PROSE REACHING A COMPUTED FIELD. Case 3 hands the closeout a verdict file
#     stuffed with a fabricated sha and a claim of merged PRs, and asserts the
#     record still shows git's shas and gh's counts. A version of this library
#     that trusted the agent for any one field would pass every other case here
#     and be worthless: the whole point is that describing must stop paying.
#  2. UNMEASURED READING AS ZERO. Case 5b: gh missing must never read as a real
#     zero. Zero opened and "we never looked" are different facts.
#  3. THE LEDGER LANDING IN THE REPO. Case 7. lib/sweep-loop-common.sh:601
#     already consumes BLOCKERS.md in its own tree and froze vim-arcade's
#     deploys for 18 hours on 2026-08-07. A second engine writer inside the
#     checkout is the same bug again.
#
# THE DEBT RULE that used to live here (a run may not open more issues than it
# closed) ran as a two-week trial, 2026-08-07..2026-08-21, and is RETIRED, not
# just expired -- hf7y/scheduler#314. Two weeks of this account's own ledger
# never once showed it tripping (issues_opened was 0 in every trial-window
# run), and it had no measurable effect on the estate's issue-creation rate at
# either boundary. Its scoping was also weaker than documented: opened counts
# were as fresh as `since` allowed, correct for a real run window, but "author:
# @me" resolves through one shared GitHub identity across all fifteen self-dev
# accounts (`gh auth status` here shows account hf7y, no per-account token on
# the write path) -- see hf7y/scheduler#310. The behavioral intent survives as
# schedule/_standing-rules.md rule 0 (mechanism first) and rule 1 (close what
# you resolved), which do not depend on that measurement. The NET-closed
# WORKED credit below (closing more than you opened) is a different,
# unretired feature and keeps its cases.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/run-record.sh"
TMP="$(mktemp -d)"; trap 'cd /; rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# shellcheck source=../lib/run-record.sh
. "$LIB"
for f in run_record_probe_git run_record_probe_gh \
         run_record_compute_verdict run_record_append run_record_line \
         run_record_closeout; do
  type "$f" >/dev/null 2>&1 || { echo "lib did not define $f"; exit 1; }
done

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- a gh stub, so every branch is drivable without a network --------------
# Answers the four searches run_record_probe_gh makes, off env vars. It also
# proves the indirection exists: a probe that could only call the real gh could
# not be witnessed at all.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# $1=issue|pr  ... --state S --search Q
kind="$1"; state=""; search=""
while [ $# -gt 0 ]; do
  case "$1" in --state) state="$2"; shift 2;; --search) search="$2"; shift 2;; *) shift;; esac
done
[ "${STUB_FAIL:-0}" = "1" ] && exit 1
n=0
case "$kind:$state" in
  issue:all)    n="${STUB_ISSUES_OPENED:-0}" ;;
  issue:closed) n="${STUB_ISSUES_CLOSED:-0}" ;;
  pr:all)       n="${STUB_PRS_OPENED:-0}" ;;
  pr:merged)    n="${STUB_PRS_MERGED:-0}" ;;
esac
printf '['
for ((i=0;i<n;i++)); do [ $i -gt 0 ] && printf ','; printf '{"number":%d}' "$i"; done
printf ']\n'
STUB
chmod +x "$TMP/bin/gh"
RR_GH_BIN="$TMP/bin/gh"
export STUB_ISSUES_OPENED=0 STUB_ISSUES_CLOSED=0 STUB_PRS_OPENED=0 STUB_PRS_MERGED=0 STUB_FAIL=0

# A bare origin plus a work tree, rebuilt per case.
fresh() {
  cd "$TMP" || exit 1
  rm -rf "$TMP/origin.git" "$TMP/work" "$TMP/state"
  git init -q --bare -b main "$TMP/origin.git"
  git clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
  cd "$TMP/work" || exit 1
  echo base > file.txt
  git add file.txt && git commit -q -m base && git push -q -u origin main
}

echo "== 1. git probe: a run that committed AND pushed"
fresh
B="$(git rev-parse HEAD)"
echo more >> file.txt && echo new > added.txt && git add -A && git commit -q -m work && git push -q origin main
A="$(git rev-parse HEAD)"; R="$(git ls-remote origin -h refs/heads/main | cut -f1)"
run_record_probe_git "$B" "$A" "$R"
[ "$RR_COMMITS_ADDED" = "1" ] && ok "counted 1 commit" || bad "commits_added=$RR_COMMITS_ADDED"
[ "$RR_PUSHED" = "true" ] && ok "pushed=true" || bad "pushed=$RR_PUSHED"
[ "$RR_FILES_CHANGED" = "2" ] && ok "files_changed=2" || bad "files_changed=$RR_FILES_CHANGED"

echo "== 2. git probe: committed but NEVER PUSHED is not the same as no commits"
fresh
B="$(git rev-parse HEAD)"
echo x >> file.txt && git commit -qam local-only
A="$(git rev-parse HEAD)"; R="$(git ls-remote origin -h refs/heads/main | cut -f1)"
run_record_probe_git "$B" "$A" "$R"
[ "$RR_PUSHED" = "false" ] && ok "unpushed commit -> pushed=false" || bad "pushed=$RR_PUSHED"
run_record_compute_verdict 0
[ "$RR_VERDICT" = "FAILED" ] && ok "unpushed work computes FAILED" || bad "verdict=$RR_VERDICT"
# And a run with no commits at all must NOT read as an unpushed failure.
run_record_probe_git "$B" "$B" "$R"
[ "$RR_PUSHED" = "null" ] && ok "no commits -> pushed=null, not false" || bad "pushed=$RR_PUSHED"
run_record_compute_verdict 0
[ "$RR_VERDICT" = "IDLE" ] && ok "an idle run is IDLE, not FAILED" || bad "verdict=$RR_VERDICT"

echo "== 2b. REPO SLUG SURVIVES A SELF-DEV SSH ALIAS, not just literal github.com"
fresh
git remote set-url origin git@github.com:test/fixture.git
[ "$(run_record_repo_slug)" = "test/fixture" ] && ok "literal github.com resolves" || bad "literal github.com broke"
git remote set-url origin "git@github-realisateur:hf7y/realisateur.git"
[ "$(run_record_repo_slug)" = "hf7y/realisateur" ] && ok "per-repo SSH alias (git@github-<project>:) resolves" || bad "SSH alias slug: $(run_record_repo_slug)"
git remote set-url origin https://github.com/hf7y/realisateur.git
[ "$(run_record_repo_slug)" = "hf7y/realisateur" ] && ok "https github.com resolves" || bad "https slug: $(run_record_repo_slug)"
git remote set-url origin git@gitlab.com:hf7y/realisateur.git
[ -z "$(run_record_repo_slug)" ] && ok "non-github remote still returns empty" || bad "gitlab leaked a slug: $(run_record_repo_slug)"

echo "== 3. THE PROPERTY: the agent cannot write the sha, the counts, or the verdict"
fresh
B="$(git rev-parse HEAD)"
echo real >> file.txt && git commit -qam "real work" && git push -q origin main
A="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin -h refs/heads/main | cut -f1)"
BEFORE_SHA="$B"; AFTER_SHA="$A"
# The agent's self-report: a fabricated sha, a fabricated body of work, DONE.
FAKESHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
STATE_ROOT="$TMP/state"; mkdir -p "$STATE_ROOT/scheduler-verdict"
cat > "$STATE_ROOT/scheduler-verdict/proj" <<EOF
VERDICT=DONE
REASON=pushed $FAKESHA, merged 9 PRs, closed 12 issues, files_changed=400
AT=2026-08-07T00:00:00-05:00
EOF
git remote set-url origin git@github.com:test/fixture.git   # so the gh probe engages
JOB_NAME=projjob; PROJECT_KEY=proj; TIER=batch; BRANCH=main
START_TS=$(( $(date +%s) - 5 )); RUN_RC=0; STATUS=done
RUN_LEDGER_FILE="$TMP/state/scheduler-runs/proj.jsonl"
STUB_ISSUES_OPENED=0 STUB_ISSUES_CLOSED=0 STUB_PRS_OPENED=0 STUB_PRS_MERGED=0 \
  run_record_closeout > "$TMP/closeout.out" 2>&1
LINE="$(tail -1 "$RUN_LEDGER_FILE")"
grep -q "\"before_sha\":\"$B\"" <<<"$LINE" && ok "before_sha is git's, not the agent's" || bad "before_sha wrong: $LINE"
grep -q "\"after_sha\":\"$A\"" <<<"$LINE" && ok "after_sha is git's" || bad "after_sha wrong"
grep -q "\"commits_added\":1" <<<"$LINE" && ok "commits_added computed as 1, not the claimed 9/12/400" || bad "commits_added wrong"
grep -q '"prs_merged":0' <<<"$LINE" && ok "prs_merged=0 despite the claim of 9" || bad "prs_merged took the claim"
grep -q '"issues_closed":0' <<<"$LINE" && ok "issues_closed=0 despite the claim of 12" || bad "issues_closed took the claim"
# The fabricated sha may appear ONCE, inside claimed_reason, and nowhere else.
COUNT="$(grep -o "$FAKESHA" <<<"$LINE" | wc -l)"
[ "$COUNT" = "1" ] && ok "the fabricated sha appears exactly once (in claimed_reason)" || bad "fabricated sha appears $COUNT times"
grep -q "\"claimed_reason\":\"pushed $FAKESHA" <<<"$LINE" && ok "and that once is claimed_reason" || bad "fabricated sha escaped its namespace"
grep -q '"claimed_verdict":"DONE"' <<<"$LINE" && ok "prose is carried, namespaced" || bad "prose was dropped entirely"
grep -q '"verdict_computed":"WORKED"' <<<"$LINE" && ok "verdict_computed is derived (WORKED: it really did push)" || bad "verdict_computed wrong: $LINE"
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$LINE" \
  && ok "the line is valid JSON" || bad "unparseable JSONL"

echo "== 4. WORKED is not buyable with issues: filing is not working"
fresh
B="$(git rev-parse HEAD)"
run_record_probe_git "$B" "$B" "$B"
RR_ISSUES_OPENED=3; RR_ISSUES_CLOSED=3; RR_PRS_MERGED=0; RR_PRS_OPENED=3; RR_GH=ok
run_record_compute_verdict 0
[ "$RR_VERDICT" = "IDLE" ] && ok "3 issues opened + 3 closed, nothing pushed -> IDLE" || bad "verdict=$RR_VERDICT"
grep -q "nothing observable changed" <<<"$RR_REASONS" && ok "and says why" || bad "no reason given"

echo "== 5. the NET-closed credit: breaking even is not a failure, closing more is WORKED"
RR_ISSUES_OPENED=2; RR_ISSUES_CLOSED=2; RR_GH=ok; run_record_compute_verdict 0
[ "$RR_VERDICT" != "FAILED" ] && ok "2 opened / 2 closed is not a failure" || bad "even trade failed"
RR_ISSUES_OPENED=0; RR_ISSUES_CLOSED=2; run_record_compute_verdict 0
[ "$RR_VERDICT" = "WORKED" ] && ok "closing 2 and opening 0 is WORKED" || bad "verdict=$RR_VERDICT"

echo "== 5b. rc DOES NOT MASK EFFECTS (2026-08-19, gardien)"
# gardien 2026-08-19: 43 commits pushed, 2 PRs merged, 2 issues closed, then
# hit its turn ceiling. It recorded FAILED, byte-identical to a run that did
# nothing at all. Effects must survive a nonzero rc.
RR_PUSHED=true; RR_COMMITS_ADDED=43; RR_PRS_MERGED=2
RR_ISSUES_OPENED=0; RR_ISSUES_CLOSED=2; RR_GH=ok
run_record_compute_verdict 1
[ "$RR_VERDICT" = "WORKED-CUTOFF" ] && ok "shipped-then-cut-off is WORKED-CUTOFF, not FAILED" || bad "verdict=$RR_VERDICT"
grep -q "exited rc=1" <<<"$RR_REASONS" && ok "and the rc is still named in the reasons" || bad "rc hidden: $RR_REASONS"
grep -q "merged 2 PR" <<<"$RR_REASONS" && ok "and the effects are still counted" || bad "effects lost: $RR_REASONS"

echo "== 5c. a nonzero rc with NO effects is still FAILED"
RR_PUSHED=false; RR_COMMITS_ADDED=0; RR_PRS_MERGED=0
RR_ISSUES_OPENED=0; RR_ISSUES_CLOSED=0
run_record_compute_verdict 1
[ "$RR_VERDICT" = "FAILED" ] && ok "shipped nothing and broke -> FAILED" || bad "verdict=$RR_VERDICT"
# reset what this block set, so the cases below see the state they expect
unset RR_PUSHED; RR_COMMITS_ADDED=0; RR_PRS_MERGED=0

echo "== 6. gh probe: a failing gh is an ERROR, distinguishable from a real zero"
STUB_ISSUES_OPENED=4 STUB_ISSUES_CLOSED=1 STUB_PRS_OPENED=1 STUB_PRS_MERGED=2 \
  run_record_probe_gh o/r 2026-08-07T00:00:00-05:00 >/dev/null
[ "$RR_GH" = "ok" ] && [ "$RR_ISSUES_OPENED" = "4" ] && [ "$RR_PRS_MERGED" = "2" ] \
  && ok "counts parsed from gh (4 opened, 2 merged)" || bad "gh=$RR_GH opened=$RR_ISSUES_OPENED merged=$RR_PRS_MERGED"
STUB_FAIL=1 run_record_probe_gh o/r 2026-08-07T00:00:00-05:00 >/dev/null
[ "$RR_GH" = "error" ] && ok "a failing gh reports error" || bad "gh=$RR_GH"
[ -z "$RR_ISSUES_OPENED" ] && ok "and leaves the counts unmeasured, not 0" || bad "invented $RR_ISSUES_OPENED"
RR_GH_BIN="$TMP/bin/nonexistent-gh" run_record_probe_gh o/r 2026-08-07T00:00:00-05:00 >/dev/null
[ "$RR_GH" = "unavailable" ] && ok "a missing gh reports unavailable" || bad "gh=$RR_GH"

echo "== 7. THE REFUSAL: the ledger must never be written inside a work tree"
fresh
if run_record_append "$TMP/work/ledger.jsonl" '{"x":1}' >/dev/null 2>&1; then
  bad "wrote the ledger INTO the checkout -- the vim-arcade freeze, again"
else
  ok "refuses a path inside a git work tree"
fi
[ -f "$TMP/work/ledger.jsonl" ] && bad "file was created anyway" || ok "and created nothing"
run_record_append "$TMP/state/scheduler-runs/p.jsonl" '{"x":1}' >/dev/null 2>&1 \
  && ok "accepts a path outside any work tree" || bad "refused a legitimate state path"

echo "== 8. append-only: a second run adds a line and rewrites nothing"
run_record_append "$TMP/state/scheduler-runs/p.jsonl" '{"x":2}' >/dev/null 2>&1
[ "$(wc -l < "$TMP/state/scheduler-runs/p.jsonl")" = "2" ] && ok "two runs, two lines" || bad "line count wrong"
[ "$(head -1 "$TMP/state/scheduler-runs/p.jsonl")" = '{"x":1}' ] && ok "the first record is untouched" || bad "an earlier record was rewritten"

echo "== 9. the engine actually calls it, and folds a computed FAILED into rc"
ENG="$ROOT/lib/sweep-loop-common.sh"
grep -q 'source "$LIB_DIR_EARLY/run-record.sh"' "$ENG" && ok "engine sources the lib" || bad "lib is never sourced"
grep -q 'run_record_closeout' "$ENG" && ok "engine calls run_record_closeout" || bad "closeout is never called"
# Ordering: the closeout must run AFTER AFTER_SHA/REMOTE_SHA are read, or it
# would record the shas of a run that had not happened yet.
SHA_LINE="$(grep -n '^  AFTER_SHA=' "$ENG" | head -1 | cut -d: -f1)"
CALL_LINE="$(grep -n 'if ! run_record_closeout' "$ENG" | head -1 | cut -d: -f1)"
[ -n "$SHA_LINE" ] && [ -n "$CALL_LINE" ] || bad "could not locate AFTER_SHA ($SHA_LINE) or the call site ($CALL_LINE)"
[ -n "$SHA_LINE" ] && [ -n "$CALL_LINE" ] && [ "$CALL_LINE" -gt "$SHA_LINE" ] \
  && ok "closeout runs after the shas are read (line $CALL_LINE > $SHA_LINE)" \
  || bad "closeout at $CALL_LINE runs before AFTER_SHA at $SHA_LINE"
grep -q 'RUN_RC=1' <<<"$(sed -n "${CALL_LINE},$((CALL_LINE+2))p" "$ENG")" \
  && ok "a computed FAILED sets RUN_RC -- it changes the run's exit status" \
  || bad "computed FAILED does not reach RUN_RC, so it is just another self-report"

echo "== 10. a conf whose own prompt already names verdict.sh still gets a run record"
# hf7y/scheduler#259: crt and chezz both showed runs=0 in the fleet sensor
# (~/.local/share/scheduler-runs/<key>.jsonl did not exist) on a night both
# ran and finished. The issue's own diagnosis names the cause: their
# BATCH_PROMPT already contains the literal string "verdict.sh" (the
# hand-pasted `$HOME/.../verdict.sh set <key> ...` line, same as every conf
# predating append_verdict_closeout), so append_verdict_closeout's own
# grep -q 'verdict\.sh' skips APPENDING ITS CLOSEOUT TEXT -- see case 3
# above and tests/verdict-closeout-witness.sh case 3, both of which assert
# that skip is correct and intentional.
#
# What this case checks is a DIFFERENT question: does that skip also stop
# run_record_closeout from writing the ledger line? It must not -- the two
# are unrelated mechanisms (append_verdict_closeout edits $PROMPT before
# `claude -p` runs; run_record_closeout runs AFTER, unconditionally, per
# lib/sweep-loop-common.sh:982 / case 9 above) -- but the issue was filed
# on the theory that they are coupled, and nothing before this asserted
# they are not.
awk '/^append_verdict_closeout\(\) \{$/,/^\}$/' "$ROOT/lib/sweep-loop-common.sh" > "$TMP/avc.sh"
grep -q 'verdict\.sh\|VERDICT_BIN' "$TMP/avc.sh" \
  || bad "could not extract append_verdict_closeout() from lib/sweep-loop-common.sh"
# shellcheck disable=SC1090
. "$TMP/avc.sh"

fresh
B="$(git rev-parse HEAD)"
echo real >> file.txt && git commit -qam "real work" && git push -q origin main
A="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin -h refs/heads/main | cut -f1)"
BEFORE_SHA="$B"; AFTER_SHA="$A"
git remote set-url origin git@github.com:test/fixture.git

VERDICT_BIN="$ROOT/bin/verdict.sh"
TIER="nightly-batch"; PROJECT_KEY="crt"
PROMPT='Work the queue.
  $HOME/Documents/Projects/scheduler/bin/verdict.sh set crt <VERDICT> "..."'
AVC_OUT="$(append_verdict_closeout)"
grep -q 'skipped' <<<"$AVC_OUT" \
  && ok "append_verdict_closeout skipped, as crt's real conf triggers" \
  || bad "setup did not reproduce the skip -- test is not exercising the claim"

JOB_NAME=crt-nightly-batch; BRANCH=main
START_TS=$(( $(date +%s) - 5 )); RUN_RC=0; STATUS=done
RUN_LEDGER_FILE="$TMP/state/scheduler-runs/crt.jsonl"
STUB_ISSUES_OPENED=0 STUB_ISSUES_CLOSED=0 STUB_PRS_OPENED=0 STUB_PRS_MERGED=0 \
  run_record_closeout > "$TMP/closeout10.out" 2>&1

[ -f "$RUN_LEDGER_FILE" ] \
  && ok "the ledger file exists despite the closeout-text skip" \
  || bad "hf7y/scheduler#259 REPRODUCED: no ledger written when the conf's own prompt names verdict.sh"
if [ -f "$RUN_LEDGER_FILE" ]; then
  LINE="$(tail -1 "$RUN_LEDGER_FILE")"
  grep -q "\"participant\":\"crt\"" <<<"$LINE" \
    && ok "and it is a real record for this participant" || bad "wrong/garbled record: $LINE"
fi

cd /
echo
echo "run-record-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
