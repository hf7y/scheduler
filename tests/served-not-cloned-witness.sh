#!/usr/bin/env bash
# served-not-cloned-witness.sh -- a v2 dispatch entry point takes its repo as
# an ARGUMENT, never a fact derived from its own filesystem or its caller's
# identity (hf7y/scheduler#306). Not a v1 alarm: this checks entry points
# directly, not whether the 15 live accounts still clone.
#
# #306's three tests, all here: (1) a converged crontab row names no
# project, (2) the entry point refuses with no repo arg (check_refuses_with_
# no_repo_arg, #644), (3) the same worker dispatches to two repo args in
# turn -- "worth more than the other two together" per #306.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/witness-common.sh"
echo "served-not-cloned-witness"

# A hostile identity: would derive a wrong project name if $USER/$HOME/$PWD
# were ever consulted as a fallback.
FAKE_HOME="$(mktemp -d)"; trap 'rm -rf "$FAKE_HOME"' EXIT
FAKE_USER="totally-not-a-project-$$"

check_refuses_with_no_repo_arg() {  # <label> <script> [extra args...]
  local label="$1" script="$2"; shift 2
  local out rc out2 rc2

  out="$(cd "$REPO_ROOT" && "$script" "$@" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "$label: exits nonzero ($rc) with no repo argument" \
    || bad "$label: exited 0 with no repo argument -- it dispatched SOMETHING"

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


# test 1 (#306): dose-project.sh's do_live() crontab row has no $PROJECT in
# it (TAG/abs_cmd both derive from the shared _runner.conf) -- proven live,
# not read off the source.
echo
echo "-- test 1 (#306): the crontab row names no project --"
T1_WORK="$(mktemp -d)"; T1_FAKEBIN="$T1_WORK/fakebin"; mkdir -p "$T1_FAKEBIN"
T1_PROJECT="scratch-crontab-shape-$$"

cat > "$T1_FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
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

# test 3 (#306, "worth more than the other two together"): one account, two
# repo args, dispatches to both. Models #304's scratch-account scenario.
# Hermetic: do_now() runs for real (fake gh/sudo/getent/pgrep only) against a
# scheduler-run stub planted at DOSE_BUILD_ROOT -- no clone anywhere (#350:
# do_now() now dispatches the installed build, same as do_live()).
echo
echo "-- test 3 (#306): the SAME worker, two repo arguments, dispatches to both --"
T3_WORK="$(mktemp -d)"; T3_FAKEBIN="$T3_WORK/fakebin"; mkdir -p "$T3_FAKEBIN"
T3_ACCT="scratchworker"
T3_HOME="$T3_WORK/home/$T3_ACCT"
mkdir -p "$T3_HOME"
T3_BUILD_ROOT="$T3_WORK/verb-builds"
T3_BUILD="$T3_BUILD_ROOT/current/scheduler"
mkdir -p "$T3_BUILD/bin" "$T3_BUILD/schedule"

cat > "$T3_BUILD/schedule/scratch-repo-a.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/selfdev-permission-witness-scratch-a.git"
EOF
cat > "$T3_BUILD/schedule/scratch-repo-b.conf" <<'EOF'
REPO_URL="https://github.com/hf7y/selfdev-permission-witness-scratch-b.git"
EOF

T3_DISPATCH_LOG="$T3_WORK/dispatch.log"; : > "$T3_DISPATCH_LOG"
T3_RUNNING_MARKER="$T3_WORK/running-marker"

cat > "$T3_BUILD/bin/scheduler-run" <<EOF
#!/usr/bin/env bash
proj="\$1"; tier="\$2"
here="\$(cd "\$(dirname "\$0")/.." && pwd)"
repo_url="\$(grep -E '^REPO_URL=' "\$here/schedule/\$proj.conf" | head -1 | cut -d= -f2- | tr -d '"')"
printf '%s\t%s\t%s\n' "\$proj" "\$tier" "\$repo_url" >> "$T3_DISPATCH_LOG"
touch "$T3_RUNNING_MARKER"
EOF
chmod +x "$T3_BUILD/bin/scheduler-run"

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

cat > "$T3_FAKEBIN/pgrep" <<EOF
#!/usr/bin/env bash
# stands in for the real 'claude -p' probe: seen once the marker exists.
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

T3_HOSTILE_HOME="$(mktemp -d)"
T3_HOSTILE_USER="totally-not-scratch-repo-$$"

rm -f "$T3_RUNNING_MARKER"

T3_OUT_A="$(
  cd /tmp && \
  PATH="$T3_FAKEBIN:$PATH" \
  HOME="$T3_HOSTILE_HOME" USER="$T3_HOSTILE_USER" LOGNAME="$T3_HOSTILE_USER" \
  DOSE_HOST_OVERRIDE=t3host \
  DOSE_SCHEDULE_DIR="$T3_SCHED_DIR" \
  VERB_HOST_BUILD_ROOT="$T3_BUILD_ROOT" \
  FAKE_ROSTER_CONTENT="$T3_ROSTER" \
  "$REPO_ROOT/bin/dose-project.sh" scratch-repo-a --now 2>&1
)"; T3_RC_A=$?
[ "$T3_RC_A" -eq 0 ] && ok "dispatch #1 (scratch-repo-a) exits 0" \
  || bad "dispatch #1 (scratch-repo-a) exited $T3_RC_A: $T3_OUT_A"

rm -f "$T3_RUNNING_MARKER"  # same worker, free again for its second ticket

T3_OUT_B="$(
  cd /tmp && \
  PATH="$T3_FAKEBIN:$PATH" \
  HOME="$T3_HOSTILE_HOME" USER="$T3_HOSTILE_USER" LOGNAME="$T3_HOSTILE_USER" \
  DOSE_HOST_OVERRIDE=t3host \
  DOSE_SCHEDULE_DIR="$T3_SCHED_DIR" \
  VERB_HOST_BUILD_ROOT="$T3_BUILD_ROOT" \
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
