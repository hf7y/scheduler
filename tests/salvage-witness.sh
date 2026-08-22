#!/usr/bin/env bash
# Witness for lib/salvage.sh -- the replacement for `git reset --hard`.
#
# The bug this exists to prevent is work DISAPPEARING: the old path stashed
# uncommitted changes and branched unpushed commits into local-only refs, then
# reset over the top, so a run that died mid-flight left its work somewhere
# nothing in the system would ever look. Cases 2, 3 and 5 are that direction.
#
# Case 5 is the one that must never go green by accident: if the salvage
# cannot be PUSHED, the run must abort with the work still on disk. A version
# of this lib that resets anyway would pass every other case here.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/salvage.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
quiet() { :; }

# shellcheck source=../lib/salvage.sh
. "$LIB"
type salvage_then_restore >/dev/null 2>&1 \
  || { echo "lib did not define salvage_then_restore"; exit 1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A bare "origin" plus a working checkout, rebuilt fresh for each case.
fresh() {
  cd "$TMP" || exit 1   # never rm -rf the shell's own cwd
  rm -rf "$TMP/origin.git" "$TMP/work" "$TMP/other"
  git init -q --bare -b main "$TMP/origin.git"
  git clone -q "$TMP/origin.git" "$TMP/work" 2>/dev/null
  cd "$TMP/work" || exit 1
  echo base > file.txt
  git add file.txt && git commit -q -m base && git push -q -u origin main
}

echo "== 1. clean workspace already at origin -> no salvage branch, no noise"
fresh
salvage_then_restore main testjob quiet && ok "returns 0 on a clean tree" || bad "failed on a clean tree: $SALVAGE_ERROR"
[ -z "$SALVAGE_REF" ] && ok "no salvage branch invented" || bad "invented $SALVAGE_REF"
[ "$(git -C "$TMP/origin.git" for-each-ref --format='%(refname)' 'refs/heads/salvage/*' | wc -l)" = 0 ] \
  && ok "origin has no salvage refs" || bad "origin grew a salvage ref"

echo "== 2. THE REGRESSION: uncommitted work is PUSHED, not stashed"
fresh
echo "PARADIGM 4 -- verdict designs" > designs.md   # untracked, like the real loss
echo mutated >> file.txt                            # tracked modification
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ -n "$SALVAGE_REF" ] && ok "reported salvage ref $SALVAGE_REF" || bad "no salvage ref reported"
git -C "$TMP/origin.git" cat-file -e "refs/heads/$SALVAGE_REF:designs.md" 2>/dev/null \
  && ok "the UNTRACKED file reached ORIGIN (the thing a stash never did)" \
  || bad "untracked work did not reach origin"
[ "$(git -C "$TMP/origin.git" show "refs/heads/$SALVAGE_REF:file.txt")" = "$(printf 'base\nmutated')" ] \
  && ok "the tracked modification reached origin" || bad "tracked modification lost"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok "workspace restored to origin/main" || bad "workspace not restored"
[ -z "$(git status --porcelain)" ] && ok "workspace is clean afterwards" || bad "workspace still dirty"
[ "$(git stash list | wc -l)" = 0 ] && ok "nothing was hidden in a stash" || bad "a stash was created"

echo "== 3. unpushed commits (the chezz case: died after commit, before push)"
fresh
echo work > feature.txt && git add feature.txt && git commit -q -m "real work nobody pushed"
LOST="$(git rev-parse HEAD)"
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
git -C "$TMP/origin.git" merge-base --is-ancestor "$LOST" "refs/heads/$SALVAGE_REF" 2>/dev/null \
  && ok "the unpushed commit is reachable ON ORIGIN" || bad "unpushed commit did not reach origin"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok "workspace restored to origin/main" || bad "workspace not restored"

echo "== 4. workspace behind origin -> fast-forwards, still no salvage"
fresh
git -C "$TMP/work" push -q origin main
( cd "$TMP" && git clone -q "$TMP/origin.git" other && cd other \
  && echo more > other.txt && git add other.txt && git commit -q -m later && git push -q origin main )
git fetch -q origin
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ -z "$SALVAGE_REF" ] && ok "no salvage for a merely stale workspace" || bad "salvaged $SALVAGE_REF needlessly"
[ -f other.txt ] && ok "picked up origin's newer commit" || bad "did not advance to origin"

echo "== 5. THE ONE THAT MUST NOT GO GREEN: push fails -> abort, work intact"
fresh
echo "irreplaceable" > precious.txt
git remote set-url origin "$TMP/does-not-exist.git"   # push cannot succeed
if salvage_then_restore main testjob quiet; then
  bad "returned 0 despite being unable to preserve the work"
else
  ok "returns non-zero when the work could not be pushed"
fi
[ -n "$SALVAGE_ERROR" ] && ok "named the failure: ${SALVAGE_ERROR:0:40}..." || bad "aborted without saying why"
[ -f precious.txt ] && ok "THE WORK IS STILL ON DISK -- nothing was discarded" || bad "work was destroyed after a failed push"
git log --oneline --all | grep -q "salvage: uncommitted work" \
  && ok "work is committed locally on the salvage branch, recoverable" || bad "work left uncommitted"

echo "== 5b. HEAD on its OWN already-pushed feature branch -> no duplicate salvage (hf7y/realisateur#533)"
fresh
git checkout -q -b in-flight-pr
echo "already reviewed" > pr-work.txt && git add pr-work.txt && git commit -q -m "in-flight PR work"
git push -q -u origin in-flight-pr
BEFORE_SALVAGE_REFS="$(git -C "$TMP/origin.git" for-each-ref --format='%(refname)' 'refs/heads/salvage/*' | wc -l)"
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ -z "$SALVAGE_REF" ] && ok "no duplicate salvage branch for an already-pushed PR branch" || bad "invented $SALVAGE_REF for work already safe on origin"
[ "$(git -C "$TMP/origin.git" for-each-ref --format='%(refname)' 'refs/heads/salvage/*' | wc -l)" = "$BEFORE_SALVAGE_REFS" ] \
  && ok "origin grew no new salvage ref" || bad "origin grew a salvage ref anyway"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok "workspace restored to origin/main" || bad "workspace not restored"
git -C "$TMP/origin.git" cat-file -e "refs/heads/in-flight-pr:pr-work.txt" 2>/dev/null \
  && ok "the PR branch itself is untouched on origin" || bad "PR branch content missing"

echo "== 5c. HEAD on a feature branch with a LOCAL-ONLY commit still salvages (not a free pass)"
fresh
git checkout -q -b in-flight-pr
echo "pushed" > pr-work.txt && git add pr-work.txt && git commit -q -m "pushed part"
git push -q -u origin in-flight-pr
echo "not pushed yet" > pr-work2.txt && git add pr-work2.txt && git commit -q -m "local-only commit"
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ -n "$SALVAGE_REF" ] && ok "still salvages when HEAD is ahead of the pushed branch too" || bad "silently dropped a genuinely unpushed commit"

echo "== 6. origin/<branch> missing -> refuse rather than guess a base"
fresh
if salvage_then_restore nosuchbranch testjob quiet; then
  bad "proceeded against a branch origin does not have"
else
  ok "refuses when origin/<branch> does not exist"
fi
[ -z "$SALVAGE_REF" ] && ok "no salvage branch created on refusal" || bad "created $SALVAGE_REF"

echo "== 7. SECRETS must never ride out on a salvage branch (it gets PUSHED)"
fresh
mkdir -p .session-handoff && echo "oauth-token-DO-NOT-PUBLISH" > .session-handoff/creds
echo "real work" > notes.md
SALVAGE_EXCLUDE=".session-handoff"
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ -n "$SALVAGE_REF" ] && ok "still salvaged the real work" || bad "did not salvage alongside excluded paths"
git -C "$TMP/origin.git" cat-file -e "refs/heads/$SALVAGE_REF:notes.md" 2>/dev/null \
  && ok "the real work reached origin" || bad "real work lost"
git -C "$TMP/origin.git" cat-file -e "refs/heads/$SALVAGE_REF:.session-handoff/creds" 2>/dev/null \
  && bad "SECRET WAS PUSHED TO ORIGIN" || ok "the secret did NOT reach origin"
[ -f .session-handoff/creds ] && ok "secret still on disk for the run to use" || bad "secret was deleted"

echo "== 8. an EXCLUDED path alone is not 'work' -- no empty salvage every run"
fresh
mkdir -p .session-handoff && echo tok > .session-handoff/creds
SALVAGE_EXCLUDE=".session-handoff"
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ -z "$SALVAGE_REF" ] && ok "no salvage branch for secrets-only dirt" || bad "salvaged $SALVAGE_REF for nothing"
SALVAGE_EXCLUDE=""

echo "== 9. a salvage branch gets a reader: files an issue naming it (hf7y/scheduler#257)"
fresh
git remote set-url origin "git@github.com:testorg/testrepo.git"
git remote set-url --push origin "$TMP/origin.git"
echo work > important.txt
GH_CALLS_LOG="$TMP/gh-calls.log"; : > "$GH_CALLS_LOG"
export GH_CALLS_LOG
STUBBIN="$TMP/bin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$GH_CALLS_LOG"
echo "https://github.com/testorg/testrepo/issues/999"
EOF
chmod +x "$STUBBIN/gh"
SALVAGE_GH_BIN="$STUBBIN/gh"
salvage_then_restore main testjob quiet && ok "returns 0" || bad "failed: $SALVAGE_ERROR"
[ "$SALVAGE_ISSUE_URL" = "https://github.com/testorg/testrepo/issues/999" ] \
  && ok "captured the filed issue's URL" || bad "no issue URL captured: $SALVAGE_ISSUE_URL"
grep -q "issue create -R testorg/testrepo" "$GH_CALLS_LOG" \
  && ok "filed against the repo the branch was pushed to" || bad "wrong call: $(cat "$GH_CALLS_LOG")"
grep -q "$SALVAGE_REF" "$GH_CALLS_LOG" \
  && ok "the issue names the salvage branch" || bad "issue does not name the branch"
unset SALVAGE_GH_BIN GH_CALLS_LOG

echo "== 10. gh missing or failing does not turn a successful salvage into a failed run"
fresh
echo work > important.txt
SALVAGE_GH_BIN="$TMP/no-such-gh-binary"
salvage_then_restore main testjob quiet && ok "still returns 0 -- salvage succeeded even though filing could not" || bad "failed: $SALVAGE_ERROR"
[ -n "$SALVAGE_REF" ] && ok "still salvaged the work" || bad "salvage itself was skipped"
[ -z "$SALVAGE_ISSUE_URL" ] && ok "no issue URL when filing was impossible" || bad "invented an issue URL: $SALVAGE_ISSUE_URL"
unset SALVAGE_GH_BIN

cd /
echo
echo "salvage-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
