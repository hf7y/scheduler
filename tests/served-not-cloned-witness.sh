#!/usr/bin/env bash
# served-not-cloned-witness.sh -- a v2 dispatch entry point takes its repo as
# an ARGUMENT, never a fact derived from its own filesystem or its caller's
# identity (hf7y/scheduler#306).
#
# HISTORY. bin/served-not-cloned.sh enforced "a host is SERVED, not cloned"
# until it was deleted 2026-08-22 (#511), two days before its own declared
# sunset -- against a rule fourteen accounts were violating at that moment.
# The old assertion ("no account executes out of a checkout it does not
# own") presumed ownership-by-account, which v2 removes; #306's rewrite
# (2026-08-27) replaces it with one line: "A worker's repo is an argument it
# was handed, never a fact derived from its own filesystem or its own
# username" -- and names three mechanical, cheap tests for it, all here:
#
#   (1) the crontab row a converger emits names no project (a cadence-only
#       row is a fixed shape) -- see "test 1" below.
#   (2) the dispatch entry point refuses when given no repo argument, rather
#       than falling back to $USER, $HOME or basename $PWD -- see
#       check_refuses_with_no_repo_arg() below. Landed first (#644) because
#       it needed no fixture beyond a hostile identity.
#   (3) the SAME worker, run twice with two different repo arguments,
#       dispatches to both -- see "test 3" below. #306 calls this the one
#       "worth more than the other two together" because (1) and (2) can be
#       made to pass by a rename, and this issue exists because a rename
#       passed once already. It needed a hermetic two-repo fixture (modeled
#       on #304's scratch-account scenario) rather than a single hostile
#       identity, which is why it landed after (1) and (2).
#
# NOT A V1 ALARM (#306's own instruction): this checks the entry points
# scripts/humans call directly, not whether any of the 15 live accounts
# still clone -- that would fire daily against every account for a rule the
# project already knows it is mid-migration on.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/witness-common.sh"
echo "served-not-cloned-witness"

# A hostile identity: a $USER/$HOME/$PWD that, if any of the three fallbacks
# #306 names were live, would derive a DIFFERENT (and wrong) project name
# than the caller meant -- rather than refusing.
FAKE_HOME="$(mktemp -d)"; trap 'rm -rf "$FAKE_HOME"' EXIT
FAKE_USER="totally-not-a-project-$$"

check_refuses_with_no_repo_arg() {  # <label> <script> [extra args...]
  local label="$1" script="$2"; shift 2
  local out rc out2 rc2

  out="$(cd "$REPO_ROOT" && "$script" "$@" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "$label: exits nonzero ($rc) with no repo argument" \
    || bad "$label: exited 0 with no repo argument -- it dispatched SOMETHING"

  # Same call, under an identity that would name a real-looking project if
  # $USER, $HOME or `basename $PWD` were consulted as a fallback.
  out2="$(cd /tmp && HOME="$FAKE_HOME" USER="$FAKE_USER" LOGNAME="$FAKE_USER" "$script" "$@" 2>&1)"; rc2=$?
  [ "$rc2" -ne 0 ] && ok "$label: still refuses under a hostile \$USER/\$HOME/\$PWD" \
    || bad "$label: exited 0 under a hostile identity -- it derived a project instead of refusing"

  grep -qF "$FAKE_USER" <<<"$out2" && bad "$label: leaked the hostile \$USER into its output -- it read \$USER for the repo" \
    || ok "$label: never reads \$USER as a repo name"
}

check_refuses_with_no_repo_arg "bin/scheduler-run" "$REPO_ROOT/bin/scheduler-run"
check_refuses_with_no_repo_arg "bin/dose-project.sh" "$REPO_ROOT/bin/dose-project.sh"

# Structural guard: no fallback assignment of the form PROJECT=${1:-$USER} /
# ${1:-$(basename "$PWD")} / PROJECT="$USER" anywhere in either entry point.
# Belt-and-suspenders for the behavioural checks above -- this is what would
# have caught #511 as a diff, not just as a live failure three weeks later.
for f in bin/scheduler-run bin/dose-project.sh; do
  if grep -nE '\$\{?1?:?-\$(USER|LOGNAME)\}?|PROJECT="?\$(USER|LOGNAME)"?|basename "?\$(PWD|HOME)"?' "$REPO_ROOT/$f" | grep -q .; then
    bad "$f: contains a literal \$USER/\$LOGNAME/\$PWD/\$HOME fallback pattern"
  else
    ok "$f: no \$USER/\$LOGNAME/\$PWD/\$HOME fallback pattern in source"
  fi
done


# --- test 1 (#306): the crontab row a converger emits names no project -----
# bin/dose-project.sh's do_live() writes ONE line per converged account:
# "<cron-fields> <RUNNER_ENV> <abs_cmd> <TAG>", where TAG comes from
# schedule/_runner.conf's RUNNER_JOB (shared across every project) and
# abs_cmd is the shared usage-paced-runner.sh build path -- neither is a
# function of the calling PROJECT. Proven here against a live --check run,
# not read off the source: a future refactor that slipped $PROJECT into the
# line would be caught even if it never touched runner_tag()/TAG, the same
# way #511 was a rename nothing here would have caught structurally.
echo
echo "-- test 1 (#306): the crontab row names no project --"
T1_WORK="$(mktemp -d)"; T1_FAKEBIN="$T1_WORK/fakebin"; mkdir -p "$T1_FAKEBIN"
T1_PROJECT="scratch-crontab-shape-$$"

cat > "$T1_FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
# minimal fetch-only fake: --check only ever needs schedule/ROSTER's content.
for a in "$@"; do
  case "$a" in
    */contents/schedule/ROSTER*) printf '%s' "$FAKE_ROSTER_CONTENT" | base64 -w0; exit 0 ;;
  esac
done
echo scheduler
EOF
chmod +x "$T1_FAKEBIN/gh"

cat > "$T1_FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do case "$1" in -n|-H) shift ;; -u) shift 2 ;; *) break ;; esac; done
exec "$@"
EOF
chmod +x "$T1_FAKEBIN/sudo"

cat > "$T1_FAKEBIN/crontab" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-l" ] && { echo "no crontab for tester" >&2; exit 1; }
exit 0
EOF
chmod +x "$T1_FAKEBIN/crontab"

cat > "$T1_FAKEBIN/getent" <<'EOF'
#!/usr/bin/env bash
[ "$1" = passwd ] && { printf '%s:x:9999:9999::/home/%s:/bin/bash\n' "$2" "$2"; exit 0; }
exit 2
EOF
chmod +x "$T1_FAKEBIN/getent"

T1_SCHED_DIR="$T1_WORK/schedule"; mkdir -p "$T1_SCHED_DIR"
printf 'RUNNER_JOB="scheduler-paced-runner"\nRUNNER_CMD="bin/usage-paced-runner.sh"\nRUNNER_ENV="PACED_MAX_PER_TICK=1"\n' \
  > "$T1_SCHED_DIR/_runner.conf"

T1_BUILD_ROOT="$T1_WORK/verb-builds"; mkdir -p "$T1_BUILD_ROOT/current/scheduler/bin"
cat > "$T1_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh" <<'EOF'
#!/usr/bin/env bash
true
EOF
chmod +x "$T1_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh"

T1_OUT="$(
  PATH="$T1_FAKEBIN:$PATH" \
  DOSE_HOST_OVERRIDE=t1host \
  DOSE_SCHEDULE_DIR="$T1_SCHED_DIR" \
  VERB_HOST_BUILD_ROOT="$T1_BUILD_ROOT" \
  FAKE_ROSTER_CONTENT="$T1_PROJECT | scratchacct@t1host | 6h | live" \
  "$REPO_ROOT/bin/dose-project.sh" "$T1_PROJECT" --check 2>&1
)"; T1_RC=$?
T1_DESIRED_LINE="$(grep -F 'desired  =' <<<"$T1_OUT")"

[ "$T1_RC" -eq 0 ] && [ -n "$T1_DESIRED_LINE" ] \
  && ok "dose-project.sh --check produced a desired crontab line" \
  || bad "dose-project.sh --check did not produce a desired line (rc=$T1_RC): $T1_OUT"

if [ -n "$T1_DESIRED_LINE" ] && ! grep -qF "$T1_PROJECT" <<<"$T1_DESIRED_LINE"; then
  ok "the crontab row itself names no project -- '$T1_PROJECT' does not appear in it"
else
  bad "the crontab row names the project -- a cadence-only row must not: $T1_DESIRED_LINE"
fi

rm -rf "$T1_WORK"

# --- test 3 (#306, "worth more than the other two together"): the SAME -----
# worker, run twice with two different repo arguments, dispatches to both.
#
# Models #304's scratch-account scenario: one account/worker, no checkout of
# its own beyond the shared scheduler clone dose-project.sh already resolves
# via the roster, pointed at TWO different scratch repos in turn. This is
# the one #306 says "cannot be satisfied by accident" -- (1) and (2) above
# can be made to pass by a rename, and #306 exists because a rename passed
# once already.
#
# Hermetic: bin/dose-project.sh's do_now() is exercised for real (fake
# gh/sudo/getent/git/pgrep only), executing its OWN constructed command
# against a stub ./bin/scheduler-run planted INSIDE the fixture clone at the
# exact relative path do_now() execs -- so what runs is the real argv
# dose-project.sh builds, not a re-implementation of it.
echo
echo "-- test 3 (#306): the SAME worker, two repo arguments, dispatches to both --"
T3_WORK="$(mktemp -d)"; T3_FAKEBIN="$T3_WORK/fakebin"; mkdir -p "$T3_FAKEBIN"
T3_ACCT="scratchworker"
T3_HOME="$T3_WORK/home/$T3_ACCT"
T3_CLONE="$T3_HOME/Documents/Projects/scheduler"
mkdir -p "$T3_CLONE/.git" "$T3_CLONE/bin" "$T3_CLONE/schedule"

# Two distinct scratch repos, ONE account -- if the worker's repo were baked
# into its filesystem or username instead of read from argv, these two calls
# would collapse onto the same repo (or fail outright).
cat > "$T3_CLONE/schedule/scratch-repo-a.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/selfdev-permission-witness-scratch-a.git"
EOF
cat > "$T3_CLONE/schedule/scratch-repo-b.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/selfdev-permission-witness-scratch-b.git"
EOF

T3_DISPATCH_LOG="$T3_WORK/dispatch.log"; : > "$T3_DISPATCH_LOG"
T3_RUNNING_MARKER="$T3_WORK/running-marker"

# Stands in for the real bin/scheduler-run, planted AT THE PATH do_now()
# execs relative to the clone it resolved via getent -- so replacing it here
# intercepts exactly what a real dispatch would run, with the same argv
# dose-project.sh itself constructs, not a hand-rebuilt approximation of it.
cat > "$T3_CLONE/bin/scheduler-run" <<EOF
#!/usr/bin/env bash
proj="\$1"; tier="\$2"
here="\$(cd "\$(dirname "\$0")/.." && pwd)"
repo_url="\$(grep -E '^REPO_URL=' "\$here/schedule/\$proj.conf" | head -1 | cut -d= -f2- | tr -d '"')"
printf '%s\t%s\t%s\n' "\$proj" "\$tier" "\$repo_url" >> "$T3_DISPATCH_LOG"
touch "$T3_RUNNING_MARKER"
EOF
chmod +x "$T3_CLONE/bin/scheduler-run"

cat > "$T3_FAKEBIN/getent" <<EOF
#!/usr/bin/env bash
if [ "\$1" = passwd ] && [ "\$2" = "$T3_ACCT" ]; then
  printf '%s:x:9999:9999::%s:/bin/bash\n' "$T3_ACCT" "$T3_HOME"
  exit 0
fi
exit 2
EOF
chmod +x "$T3_FAKEBIN/getent"

cat > "$T3_FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do case "$1" in -n|-H) shift ;; -u) shift 2 ;; *) break ;; esac; done
exec "$@"
EOF
chmod +x "$T3_FAKEBIN/sudo"

cat > "$T3_FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
# do_now()'s "pull first, always" -- always fast-forwards cleanly here.
exit 0
EOF
chmod +x "$T3_FAKEBIN/git"

cat > "$T3_FAKEBIN/pgrep" <<EOF
#!/usr/bin/env bash
# stands in for the real 'claude -p' process probe: "seen" once this
# fixture's own scheduler-run stub has touched its marker, "not seen" once
# the test clears it -- so both the ALREADY-RUNNING pre-check and the
# post-dispatch wait key off one hermetic signal instead of a real process.
[ -f "$T3_RUNNING_MARKER" ] && exit 0 || exit 1
EOF
chmod +x "$T3_FAKEBIN/pgrep"

T3_ROSTER="scratch-repo-a | $T3_ACCT@t3host | 6h | live
scratch-repo-b | $T3_ACCT@t3host | 6h | live"

cat > "$T3_FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    */contents/schedule/ROSTER*) printf '%s' "$FAKE_ROSTER_CONTENT" | base64 -w0; exit 0 ;;
  esac
done
echo scheduler
EOF
chmod +x "$T3_FAKEBIN/gh"

T3_SCHED_DIR="$T3_WORK/dose-schedule"; mkdir -p "$T3_SCHED_DIR"
printf 'RUNNER_JOB="scheduler-paced-runner"\nRUNNER_CMD="bin/usage-paced-runner.sh"\nRUNNER_ENV="PACED_MAX_PER_TICK=1"\n' \
  > "$T3_SCHED_DIR/_runner.conf"

# A hostile ambient identity for BOTH calls -- neither $USER/$HOME nor cwd
# names either scratch repo, so a regression that derived the repo from
# identity rather than argv would either dispatch nothing distinguishable
# between the two calls, or leak this name into the log.
T3_HOSTILE_HOME="$(mktemp -d)"
T3_HOSTILE_USER="totally-not-scratch-repo-$$"

rm -f "$T3_RUNNING_MARKER"

T3_OUT_A="$(
  cd /tmp && \
  PATH="$T3_FAKEBIN:$PATH" \
  HOME="$T3_HOSTILE_HOME" USER="$T3_HOSTILE_USER" LOGNAME="$T3_HOSTILE_USER" \
  DOSE_HOST_OVERRIDE=t3host \
  DOSE_SCHEDULE_DIR="$T3_SCHED_DIR" \
  FAKE_ROSTER_CONTENT="$T3_ROSTER" \
  "$REPO_ROOT/bin/dose-project.sh" scratch-repo-a --now 2>&1
)"; T3_RC_A=$?
[ "$T3_RC_A" -eq 0 ] && ok "dispatch #1 (scratch-repo-a) exits 0" \
  || bad "dispatch #1 (scratch-repo-a) exited $T3_RC_A: $T3_OUT_A"

# Marker cleared: the SAME worker is free again before its second ticket.
# This fixture proves argument-driven repo selection across two sequential
# dispatches, not concurrent execution of two repos at once.
rm -f "$T3_RUNNING_MARKER"

T3_OUT_B="$(
  cd /tmp && \
  PATH="$T3_FAKEBIN:$PATH" \
  HOME="$T3_HOSTILE_HOME" USER="$T3_HOSTILE_USER" LOGNAME="$T3_HOSTILE_USER" \
  DOSE_HOST_OVERRIDE=t3host \
  DOSE_SCHEDULE_DIR="$T3_SCHED_DIR" \
  FAKE_ROSTER_CONTENT="$T3_ROSTER" \
  "$REPO_ROOT/bin/dose-project.sh" scratch-repo-b --now 2>&1
)"; T3_RC_B=$?
[ "$T3_RC_B" -eq 0 ] && ok "dispatch #2 (scratch-repo-b) exits 0" \
  || bad "dispatch #2 (scratch-repo-b) exited $T3_RC_B: $T3_OUT_B"

T3_LOG_CONTENT="$(cat "$T3_DISPATCH_LOG" 2>/dev/null)"
T3_LINES="$(wc -l < "$T3_DISPATCH_LOG" 2>/dev/null || echo 0)"

[ "$T3_LINES" -eq 2 ] && ok "the SAME worker's clone actually ran scheduler-run twice, once per call" \
  || bad "expected 2 dispatch lines from one worker's clone, got $T3_LINES: $T3_LOG_CONTENT"

T3_EXPECT_A="$(printf 'scratch-repo-a\tbatch\thttps://github.com/hf7y/selfdev-permission-witness-scratch-a.git')"
T3_EXPECT_B="$(printf 'scratch-repo-b\tbatch\thttps://github.com/hf7y/selfdev-permission-witness-scratch-b.git')"

grep -qF "$T3_EXPECT_A" "$T3_DISPATCH_LOG" \
  && ok "dispatch #1 ran scratch-repo-a's OWN conf/repo" \
  || bad "dispatch #1 did not resolve to scratch-repo-a's repo: $T3_LOG_CONTENT"

grep -qF "$T3_EXPECT_B" "$T3_DISPATCH_LOG" \
  && ok "dispatch #2 ran scratch-repo-b's OWN conf/repo -- the SAME worker, a DIFFERENT repo" \
  || bad "dispatch #2 did not resolve to scratch-repo-b's repo: $T3_LOG_CONTENT"

grep -qF "$T3_HOSTILE_USER" "$T3_DISPATCH_LOG" \
  && bad "the hostile \$USER leaked into a dispatched repo -- identity, not argument, picked it" \
  || ok "neither dispatch was swayed by the hostile \$USER/\$HOME ambient identity"

rm -rf "$T3_WORK" "$T3_HOSTILE_HOME"

printf '\nserved-not-cloned-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
