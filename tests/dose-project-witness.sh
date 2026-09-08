#!/usr/bin/env bash
# Witness for bin/dose-project.sh (hf7y/scheduler#80). Hermetic: fake gh,
# fake sudo, fake getent and a fixture crontab file on PATH -- never the
# live estate. See bin/dose-project.sh's own header for the full spec.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TARGET="$PWD/bin/dose-project.sh"

echo "dose-project-witness"

if [ ! -x "$TARGET" ]; then
  echo "  FAIL: $TARGET missing or not executable"
  echo "dose-project-witness: 0 passed, 1 failed"
  exit 1
fi

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"

# DOSE-PROJECT.SH NEVER CALLS gh AT ALL (#432, #350): the roster is read and
# written over curl, and _runner.conf reads local. A real `gh` further down
# PATH would otherwise reach the live estate, so this fixture traps the call
# rather than omitting it.
cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh: dose-project.sh must not call gh -- the roster is a service and _runner.conf ships in the build" >&2
exit 1
EOF
chmod +x "$FAKEBIN/gh"

# THE ROSTER IS A SERVICE (#432, #686): the fixture reaches both the read and
# the write through curl. FAKE_GH_MODE keeps its old meanings so existing
# cases still mean what they meant: `fail` is unreachable (BLIND), `absent` is
# reachable-but-empty (GAP). A POST records into FAKE_ROSTER_STATE_FILE, which
# a later GET on that one project consults first -- the re-read a real service
# would answer from committed state.
cat > "$FAKEBIN/curl" <<'CURLEOF'
#!/usr/bin/env bash
METHOD=GET; URL=""; DATA=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -X) METHOD="$2"; shift 2 ;;
    -d) DATA="$2"; shift 2 ;;
    -H) shift 2 ;;
    http://*|https://*) URL="$1"; shift ;;
    *) shift ;;
  esac
done
# FAKE_GH_MODE=fail is unreachable for EVERY call, same as the live estate
# would be; FAKE_ROSTER_POST_MODE=fail isolates just the write, so a witness
# can prove the read still succeeded and only the POST did not.
if [ "${FAKE_GH_MODE:-ok}" = fail ] \
   || { [ "$METHOD" = POST ] && [ "${FAKE_ROSTER_POST_MODE:-ok}" = fail ]; }; then
  echo "curl: (7) Failed to connect" >&2; exit 7
fi
STATE_FILE="${FAKE_ROSTER_STATE_FILE:-/dev/null}"
if [ "$METHOD" = POST ]; then
  proj="${URL##*/roster/}"
  state="$(sed -n 's/.*"state":"\([^"]*\)".*/\1/p' <<<"$DATA")"
  # A MISMATCH FIXTURE: the service says 200 but the row it later serves back
  # never moved -- the exact "reported success, did nothing" case #686 exists
  # to catch, modelled by simply not recording the write.
  [ "${FAKE_ROSTER_VERIFY_MISMATCH:-0}" = 1 ] || printf '%s %s\n' "$proj" "$state" >> "$STATE_FILE"
  printf '{"project":"%s","state":"%s"}' "$proj" "$state"
  exit 0
fi
case "$URL" in
  */roster)
    if [ "${FAKE_GH_MODE:-ok}" = "absent" ]; then printf '{"rows": []}'; exit 0; fi
    printf '{"rows": ['
    printf '%s\n' "$FAKE_ROSTER_CONTENT" | awk -F'|' '
      !/^[[:space:]]*(#|$)/ && NF>=4 {
        gsub(/[[:space:]]/,"",$1); gsub(/[[:space:]]/,"",$4)
        if ($1!="" && $4!="") { if(n++) printf ","; printf "{\"project\":\"%s\",\"state\":\"%s\"}", $1, $4 }
      }'
    printf ']}'
    exit 0 ;;
  */roster/*)
    proj="${URL##*/roster/}"
    state="$(grep "^$proj " "$STATE_FILE" 2>/dev/null | tail -1 | cut -d' ' -f2)"
    [ -n "$state" ] || state="$(printf '%s\n' "$FAKE_ROSTER_CONTENT" | awk -F'|' -v p="$proj" '
      !/^[[:space:]]*(#|$)/ && NF>=4 { gsub(/[[:space:]]/,"",$1); if ($1==p) { gsub(/[[:space:]]/,"",$4); print $4 } }')"
    [ -n "$state" ] || exit 22
    printf '{"project":"%s","state":"%s"}' "$proj" "$state"
    exit 0 ;;
esac
CURLEOF
chmod +x "$FAKEBIN/curl"

cat > "$FAKEBIN/crontab" <<'EOF'
#!/usr/bin/env bash
: "${CRONFILE:?}"
if [ "$1" = "-l" ]; then
  [ -s "$CRONFILE" ] || { echo "no crontab for $(id -un)" >&2; exit 1; }
  cat "$CRONFILE"
elif [ "$1" = "-" ]; then
  if [ "${FAKE_CRONTAB_IGNORE_WRITE:-0}" = "1" ]; then cat >/dev/null; else cat > "$CRONFILE"; fi
else
  echo "fake crontab: unsupported args: $*" >&2; exit 2
fi
EOF
chmod +x "$FAKEBIN/crontab"

# strips "-n -u <acct>" and execs the rest, so foreign-account paths reach
# the same fake crontab as the local path -- no real sudo rights needed.
cat > "$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in -n|-H) shift ;; -u) shift 2 ;; *) break ;; esac
done
exec "$@"
EOF
chmod +x "$FAKEBIN/sudo"

# any account "exists", synthetic home -- no real system accounts needed.
cat > "$FAKEBIN/getent" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "passwd" ] && [ -n "${2:-}" ]; then
  if [ "$2" = "${FAKE_GETENT_FAIL:-}" ]; then
    exit 2
  fi
  printf '%s:x:9999:9999::/home/%s:/bin/bash\n' "$2" "$2"
  exit 0
fi
exit 2
EOF
chmod +x "$FAKEBIN/getent"

cat > "$FAKEBIN/id" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -u) echo "${FAKE_UID:-1000}" ;;
  -un|*) echo "${FAKE_UNAME:-testuser}" ;;
esac
EOF
chmod +x "$FAKEBIN/id"

export PATH="$FAKEBIN:$PATH"
export DOSE_HOST_OVERRIDE="testhost"
# --arm/--park POST through write_roster_state (#686): a fixture token, and
# the file the fake curl's POST/GET agree on for a project's live state.
export DOSE_ROSTER_WRITE_TOKEN="$WORK/roster-write.token"
printf 'test-roster-write-token\n' > "$DOSE_ROSTER_WRITE_TOKEN"
export FAKE_ROSTER_STATE_FILE="$WORK/roster-live-state"
: > "$FAKE_ROSTER_STATE_FILE"
ROSTER="ecosim | ecosim@testhost | 6h | live
ghosttown | ghosttown@testhost | 6h | parked
elsewhere-proj | elsewhere-proj@otherhost | 6h | live"
# scheduler#112/#350: RUNNER_JOB/RUNNER_CMD/RUNNER_ENV, real values, now a local file.
RUNNER_CONTENT='RUNNER_JOB="scheduler-paced-runner"
RUNNER_CMD="bin/usage-paced-runner.sh"
RUNNER_ENV="PACED_MAX_PER_TICK=1"
'
export DOSE_SCHEDULE_DIR="$WORK/schedule"
mkdir -p "$DOSE_SCHEDULE_DIR"
printf '%s' "$RUNNER_CONTENT" > "$DOSE_SCHEDULE_DIR/_runner.conf"

# stub abs_cmd resolves into (#350), so do_live()'s -x check passes
export VERB_HOST_BUILD_ROOT="$WORK/verb-builds"
mkdir -p "$VERB_HOST_BUILD_ROOT/current/scheduler/bin"
cat > "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh" <<'STUB'
#!/usr/bin/env bash
[ "${DOSE_REHEARSAL_DARK:-0}" = 1 ] && exit 0
printf '%s WOULD-DISPATCH [1/1] %s -> stub (mode=account)\n' \
  "$(date -Is)" "${DOSE_REHEARSAL_PROJECT:-ecosim}" >> "$PACED_STATE_DIR/run.log"
STUB
chmod +x "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh"
# the runner's account-mode gate ladder falls back to the build's copy
printf '#!/usr/bin/env bash\ntrue\n' > "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-gate.sh"
chmod +x "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-gate.sh"
DOSE_ABS_CMD="$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh"

# --- 1. unknown project exits 4, not 0 --------------------------------------
export FAKE_GH_MODE=ok FAKE_ROSTER_CONTENT="$ROSTER"
export CRONFILE="$WORK/cron1"; : > "$CRONFILE"
out="$("$TARGET" nope-not-a-project --check 2>&1)"; rc=$?
[ "$rc" -eq 4 ] && ok "unknown project exits 4 (gap)" || bad "unknown project exited $rc, want 4: $out"

# --- 2. unreachable/unauthenticated gh exits 6 BLIND, distinct from gap ----
export FAKE_GH_MODE=fail
out="$("$TARGET" ecosim --check 2>&1)"; rc=$?
[ "$rc" -eq 6 ] && ok "unreachable gh exits 6 (blind)" || bad "unreachable gh exited $rc, want 6: $out"
grep -qi blind <<<"$out" && ok "BLIND is named in the output, not silently swallowed" \
  || bad "exit 6 but message never says BLIND: $out"

# --- 2b. roster ABSENT on a REACHABLE repo is a GAP, not BLIND -------------
# The distinction this witness exists to hold: a 404 on the file while
# repos/<slug> reads fine on the same token is a positive statement that the
# ref carries no roster. Reporting that as BLIND sends the operator to look at
# credentials for a problem that is not one. Caught live on 2026-08-11, when
# the first implementation mapped both to 6.
export FAKE_GH_MODE=absent
out="$("$TARGET" ecosim --check 2>&1)"; rc=$?
[ "$rc" -eq 4 ] && ok "roster absent on a reachable repo exits 4 (gap), not 6" \
  || bad "absent roster exited $rc, want 4 (gap): $out"
grep -qi 'not a credential problem' <<<"$out" \
  && ok "the GAP says it is not a credential problem" \
  || bad "exit 4 but the message does not rule out credentials: $out"
export FAKE_GH_MODE=ok

# --- 3. parked project arms NOTHING -- fixture crontab byte-unchanged ------
export CRONFILE="$WORK/cron3"; : > "$CRONFILE"
before="$(sha256sum "$CRONFILE")"
out="$("$TARGET" ghosttown --apply 2>&1)"; rc=$?
after="$(sha256sum "$CRONFILE")"
[ "$rc" -eq 0 ] && ok "parked project --apply exits 0" || bad "parked --apply exited $rc: $out"
[ "$before" = "$after" ] && ok "parked project: fixture crontab byte-unchanged (arms nothing)" \
  || bad "parked project MODIFIED the crontab -- this is the most important test in the file: $out"

# --- 4. verify step FAILS on a planted drift it cannot silently trust ------
export CRONFILE="$WORK/cron4"
printf '59 23 * * * WRONG_ENV=1 /nonexistent/path # scheduler:scheduler-paced-runner:RUNNER (usage-paced dispatch)\n' > "$CRONFILE"
export FAKE_CRONTAB_IGNORE_WRITE=1   # the write silently no-ops; verify must still catch it
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
unset FAKE_CRONTAB_IGNORE_WRITE
[ "$rc" -eq 5 ] && ok "planted drift + inert write: --apply exits 5 (broken)" \
  || bad "planted drift: --apply exited $rc, want 5: $out"
grep -qi verify <<<"$out" && ok "the failure names verify, not a generic error" \
  || bad "drift failure doesn't mention verify: $out"
grep -qF "WRONG_ENV" "$CRONFILE" && ok "re-read caught the inert write instead of trusting crontab's exit 0" \
  || bad "cronfile changed even though the write was inert: $(cat "$CRONFILE")"


# --- 5. roster names a different host: refuse, touch nothing (#112) --------
# DOSE_HOST_OVERRIDE=testhost (set above), but this row's host is
# 'otherhost' -- exercises bin/dose-project.sh's `exit 7` branch (the guard
# that stops `dose ecosim` typed on the wrong machine from converging a host
# the roster never named). Landed in #111 unwitnessed; this closes that gap.
export CRONFILE="$WORK/cron5"; : > "$CRONFILE"
before="$(sha256sum "$CRONFILE")"
# "NOT THIS MACHINE'S" IS NOW THE ABSENCE OF A UNIX ACCOUNT (#432).
export FAKE_GETENT_FAIL=elsewhere-proj
out="$("$TARGET" elsewhere-proj --apply 2>&1)"; rc=$?
unset FAKE_GETENT_FAIL
after="$(sha256sum "$CRONFILE")"
[ "$rc" -eq 7 ] && ok "wrong-host row exits 7 (refused)" \
  || bad "wrong-host row exited $rc, want 7: $out"
grep -qi 'REFUSED' <<<"$out" && ok "the refusal is named, not a generic error" \
  || bad "exit 7 but the message never says REFUSED: $out"
[ "$before" = "$after" ] && ok "wrong-host row: fixture crontab byte-unchanged (nothing touched)" \
  || bad "wrong-host row MODIFIED the crontab -- the guard is supposed to stop before any write: $out"

# --- 6. schedule/_runner.conf is read fresh off disk, not hardcoded (#112/#350) --
export CRONFILE="$WORK/cron6"; : > "$CRONFILE"
printf '%s' 'RUNNER_JOB="renamed-job"
RUNNER_CMD="bin/usage-paced-runner.sh"
RUNNER_ENV="PACED_MAX_PER_TICK=1"
' > "$DOSE_SCHEDULE_DIR/_runner.conf"
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "apply with a renamed shared RUNNER_JOB still converges" \
  || bad "apply exited $rc with a renamed RUNNER_JOB: $out"
grep -qF 'scheduler:renamed-job:RUNNER' "$CRONFILE" \
  && ok "the emitted crontab TAG carries the on-disk RUNNER_JOB, not a hardcoded one" \
  || bad "crontab does not reflect the on-disk RUNNER_JOB: $(cat "$CRONFILE")"
printf '%s' "$RUNNER_CONTENT" > "$DOSE_SCHEDULE_DIR/_runner.conf"

# --- 6c. schedule/_runner.conf missing beside the script is BROKEN (#350) --
export CRONFILE="$WORK/cron6c"; : > "$CRONFILE"
mv "$DOSE_SCHEDULE_DIR/_runner.conf" "$WORK/_runner.conf.bak"
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
mv "$WORK/_runner.conf.bak" "$DOSE_SCHEDULE_DIR/_runner.conf"
[ "$rc" -eq 5 ] && ok "missing schedule/_runner.conf exits 5 (broken)" \
  || bad "missing _runner.conf exited $rc, want 5: $out"
grep -qi 'shipped beside this script' <<<"$out" \
  && ok "the failure names what's missing, not a generic error" \
  || bad "exit 5 but the message doesn't name the missing payload: $out"

# --- 6d. no installed build at the command path is BROKEN, never a clone path (#350) --
export CRONFILE="$WORK/cron6d"; : > "$CRONFILE"
mv "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh" "$WORK/usage-paced-runner.sh.bak"
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
mv "$WORK/usage-paced-runner.sh.bak" "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh"
chmod +x "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-paced-runner.sh"
[ "$rc" -eq 5 ] && ok "no installed build at the command path exits 5 (broken)" \
  || bad "missing installed build exited $rc, want 5: $out"
grep -qi 'no installed scheduler build' <<<"$out" \
  && ok "the failure names the missing build, not a generic error" \
  || bad "exit 5 but the message doesn't name the missing build: $out"
if [ -s "$CRONFILE" ]; then
  bad "a crontab line was written even though the build was missing: $(cat "$CRONFILE")"
else
  ok "nothing was written to the crontab when the build was missing"
fi

# --- 6e. AN INSTALLED BUILD THAT CANNOT DISPATCH IS REFUSED, NOT CONVERGED (#350) --
# Before this, `-x` was the only test: a build that installs fine and
# dispatches nothing got a crontab line and a `converged:`.
export CRONFILE="$WORK/cron6e"; : > "$CRONFILE"
out="$(DOSE_REHEARSAL_DARK=1 "$TARGET" ecosim --apply 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && ok "a build that rehearses dark exits 5 (broken), not 0" \
  || bad "dark build exited $rc, want 5: $out"
grep -qi 'CANNOT DISPATCH' <<<"$out" \
  && ok "the refusal says the build cannot dispatch" \
  || bad "exit 5 but the message never says CANNOT DISPATCH: $out"
grep -qi 'would take .* dark' <<<"$out" \
  && ok "the refusal names the consequence it prevented" \
  || bad "the refusal does not say what converging would have done: $out"
grep -qi 'converged:' <<<"$out" \
  && bad "THE BUG ITSELF: a dark build still printed 'converged:': $out" \
  || ok "a dark build never prints 'converged:'"
if [ -s "$CRONFILE" ]; then
  bad "a crontab line was written for a build that cannot dispatch: $(cat "$CRONFILE")"
else
  ok "nothing was written to the crontab when the build could not dispatch"
fi

# --- 6f. no usage-gate.sh is its OWN named refusal, not a generic one -------
# A missing gate does not crash: it logs `HOLD (gate rc=127)`, forever.
export CRONFILE="$WORK/cron6f"; : > "$CRONFILE"
mv "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-gate.sh" "$WORK/usage-gate.sh.bak"
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
mv "$WORK/usage-gate.sh.bak" "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-gate.sh"
chmod +x "$VERB_HOST_BUILD_ROOT/current/scheduler/bin/usage-gate.sh"
[ "$rc" -eq 5 ] && ok "a build with no usage-gate.sh exits 5 (broken)" \
  || bad "missing gate exited $rc, want 5: $out"
grep -qi 'usage-gate.sh' <<<"$out" \
  && ok "the refusal names usage-gate.sh, not just 'the rehearsal failed'" \
  || bad "exit 5 but the message never names the gate: $out"
grep -qi 'busy quota' <<<"$out" \
  && ok "the refusal says what the symptom would have looked like" \
  || bad "the refusal does not say the failure reads as a busy quota: $out"
[ -s "$CRONFILE" ] && bad "a crontab line was written with no gate in the build" \
  || ok "nothing was written to the crontab when the build had no gate"

# --- 6g. --check refuses the same way, and does NOT escalate ---------------
export CRONFILE="$WORK/cron6g"; : > "$CRONFILE"
cat > "$FAKEBIN/demande" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$WORK/demande-calls.log"
EOF
chmod +x "$FAKEBIN/demande"
: > "$WORK/demande-calls.log"
out="$(DOSE_REHEARSAL_DARK=1 "$TARGET" ecosim --check 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && ok "--check on a dark build exits 5 too, not 0" \
  || bad "--check on a dark build exited $rc, want 5: $out"
grep -qi 'would   converge' <<<"$out" \
  && bad "--check still previewed a converge onto a build that cannot dispatch: $out" \
  || ok "--check does not preview a converge it knows would go dark"
[ -s "$WORK/demande-calls.log" ] \
  && bad "--check escalated to Zach; only --apply should: $(cat "$WORK/demande-calls.log")" \
  || ok "--check does not escalate"

# --- 6h. --apply DOES escalate, through the demande verb (Zach, 2026-09-07) --
export CRONFILE="$WORK/cron6h"; : > "$CRONFILE"
: > "$WORK/demande-calls.log"
out="$(DOSE_REHEARSAL_DARK=1 "$TARGET" ecosim --apply 2>&1)"; rc=$?
grep -q 'ask ' "$WORK/demande-calls.log" \
  && ok "--apply escalates the refusal through 'demande ask'" \
  || bad "--apply refused but never escalated: $(cat "$WORK/demande-calls.log")"
grep -q 'ecosim' "$WORK/demande-calls.log" \
  && ok "the escalation names the project that was refused" \
  || bad "the escalation does not name the project: $(cat "$WORK/demande-calls.log")"

# --- 6i. escalation is NEVER fatal: no demande on PATH still refuses cleanly --
# PATH restricted to FAKEBIN+bare essentials, not just "$FAKEBIN:$PATH": a host
# that ships a real /usr/local/bin/demande (crt's verb build) would otherwise
# still resolve one behind FAKEBIN once the fixture copy is removed, exercising
# the live estate instead of the "nothing answers" path this case tests.
export CRONFILE="$WORK/cron6i"; : > "$CRONFILE"
rm -f "$FAKEBIN/demande"
out="$(DOSE_REHEARSAL_DARK=1 PATH="$FAKEBIN:/usr/bin:/bin" "$TARGET" ecosim --apply 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && ok "with no demande on PATH the refusal is still exit 5" \
  || bad "missing demande changed the exit code to $rc: $out"
grep -qi 'reached nobody' <<<"$out" \
  && ok "an undelivered escalation says so rather than passing silently" \
  || bad "the escalation failed silently: $out"


# --- 7. a HOST-scoped override wins over the shared conf, per field (#112/#350) --
export CRONFILE="$WORK/cron7"; : > "$CRONFILE"
printf '%s' 'RUNNER_ENV="PACED_MAX_PER_TICK=3"
' > "$DOSE_SCHEDULE_DIR/_runner.testhost.conf"
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "apply with a host-scoped RUNNER_ENV override converges" \
  || bad "apply exited $rc with a host override present: $out"
grep -qF 'PACED_MAX_PER_TICK=3' "$CRONFILE" \
  && ok "the host-scoped RUNNER_ENV overrides the shared conf's value" \
  || bad "host override did not take effect: $(cat "$CRONFILE")"
grep -qF 'scheduler:scheduler-paced-runner:RUNNER' "$CRONFILE" \
  && ok "RUNNER_JOB, which the host file does NOT set, still comes from the shared conf" \
  || bad "an unset host field should not have blanked the shared value: $(cat "$CRONFILE")"
rm -f "$DOSE_SCHEDULE_DIR/_runner.testhost.conf"

# --- 8-9. --arm/--park (#291) guards, both refused before any gh write -----
export FAKE_UID=3011
out="$("$TARGET" ecosim --arm 2>&1)"; rc=$?
unset FAKE_UID
[ "$rc" -eq 7 ] && ok "--arm from a self-dev uid exits 7 (refused)" \
  || bad "--arm from uid 3011 exited $rc, want 7: $out"
grep -qi 'REFUSED' <<<"$out" && ok "the self-dev refusal is named" \
  || bad "exit 7 but message never says REFUSED: $out"
[ -f "$WORK/gh-calls.log" ] && bad "self-dev refusal still reached gh -- $(cat "$WORK/gh-calls.log")" \
  || ok "self-dev refusal touched gh not at all"

export FAKE_GETENT_FAIL=ghosttown
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
unset FAKE_GETENT_FAIL
[ "$rc" -eq 5 ] && ok "--arm on a missing unix account exits 5 (broken)" \
  || bad "--arm with no unix account exited $rc, want 5: $out"
grep -qi 'no unix account' <<<"$out" && ok "the missing-account refusal names what's missing" \
  || bad "exit 5 but message doesn't name the missing account: $out"
[ -f "$WORK/gh-calls.log" ] && bad "missing-account refusal still reached gh -- $(cat "$WORK/gh-calls.log")" \
  || ok "missing-account refusal wrote nothing"

# --- 10. --arm POSTs the service and confirms by re-reading it (#686) ------
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--arm on a parked project exits 0" || bad "--arm exited $rc: $out"
grep -qF 'armed:' <<<"$out" && ok "--arm reports the flip, not an opened PR" \
  || bad "--arm did not report 'armed:': $out"
grep -qF 're-reading' <<<"$out" && ok "--arm says the state was confirmed by re-reading" \
  || bad "--arm's success message never mentions re-reading: $out"
grep -qF 'ghosttown live' "$FAKE_ROSTER_STATE_FILE" \
  && ok "the fake service actually recorded ghosttown -> live" \
  || bad "no POST reached the fake service: $(cat "$FAKE_ROSTER_STATE_FILE")"
[ -f "$WORK/gh-calls.log" ] && bad "--arm reached gh -- $(cat "$WORK/gh-calls.log")" \
  || ok "no gh call at all -- the write goes straight to the service"

# --- 11. already at the target state: kept, no network write ---------------
: > "$FAKE_ROSTER_STATE_FILE"
out="$("$TARGET" ecosim --arm 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--arm on an already-live project exits 0" || bad "--arm exited $rc: $out"
grep -qF 'kept' <<<"$out" && ok "--arm on an already-live project reports kept" \
  || bad "--arm on a live project didn't say kept: $out"
[ -s "$FAKE_ROSTER_STATE_FILE" ] && bad "a no-op --arm still posted a write: $(cat "$FAKE_ROSTER_STATE_FILE")" \
  || ok "a no-op --arm wrote nothing"

# --park never needed the account to exist, and still does not check for one.
export FAKE_GETENT_FAIL=ecosim
out="$("$TARGET" ecosim --park 2>&1)"; rc=$?
unset FAKE_GETENT_FAIL
[ "$rc" -eq 0 ] && ok "--park does not require the account to exist" \
  || bad "--park with no unix account exited $rc, want 0: $out"
grep -qF 'ecosim parked' "$FAKE_ROSTER_STATE_FILE" \
  && ok "--park posts the flip to parked" || bad "--park did not post: $(cat "$FAKE_ROSTER_STATE_FILE")"
: > "$FAKE_ROSTER_STATE_FILE"

# --- 12. a missing or unreadable token REFUSES, never opens (#686) ---------
mv "$DOSE_ROSTER_WRITE_TOKEN" "$WORK/roster-write.token.bak"
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
mv "$WORK/roster-write.token.bak" "$DOSE_ROSTER_WRITE_TOKEN"
[ "$rc" -eq 5 ] && ok "--arm with no token exits 5 (broken), not open" \
  || bad "--arm with no token exited $rc, want 5: $out"
grep -qi 'token' <<<"$out" && ok "the refusal names the missing token" \
  || bad "exit 5 but the refusal never mentions the token: $out"
[ -s "$FAKE_ROSTER_STATE_FILE" ] && bad "a missing-token --arm still posted: $(cat "$FAKE_ROSTER_STATE_FILE")" \
  || ok "a missing-token --arm reached the service not at all"

# --- 13. unreachable during the write is BLIND, same as the read (#686) ----
# FAKE_ROSTER_POST_MODE, not FAKE_GH_MODE: the read must succeed so this
# proves the WRITE's own BLIND path, not the read's (already covered by #2).
export FAKE_ROSTER_POST_MODE=fail
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
unset FAKE_ROSTER_POST_MODE
[ "$rc" -eq 6 ] && ok "an unreachable service during --arm's POST is BLIND (6)" \
  || bad "--arm with an unreachable POST exited $rc, want 6: $out"

# --- 13b. a silent no-op -- POST 200s but the re-read never moved -- FAILS --
# The exact measured failure this issue exists to catch: a write that reports
# success and did nothing (40% of the old PR-based writes never merged).
export FAKE_ROSTER_VERIFY_MISMATCH=1
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
unset FAKE_ROSTER_VERIFY_MISMATCH
[ "$rc" -eq 5 ] && ok "a POST that does not stick fails the re-read (5), not a false 0" \
  || bad "the silent no-op exited $rc, want 5: $out"
grep -qi 'verify failed' <<<"$out" && ok "the failure names verify, not a generic error" \
  || bad "exit 5 but the message never says verify failed: $out"

# --- 14. --shotgun parses, and NO LONGER travels (#432) -------------------
# The hop went with the host column. An ssh on PATH must stay untouched: a hop
# that still fired would dispatch on a host this one only guessed at.
cat > "$FAKEBIN/ssh" <<'SSH'
#!/usr/bin/env bash
echo "SSH-WAS-CALLED" >> "$WORK/ssh-calls.log"
SSH
chmod +x "$FAKEBIN/ssh"
rm -f "$WORK/ssh-calls.log"

export FAKE_GETENT_FAIL=elsewhere-proj
out="$("$TARGET" elsewhere-proj --shotgun 2>&1)"; rc=$?
grep -qi 'unknown flag' <<<"$out" && bad "--shotgun was not parsed as a flag: $out" || ok "--shotgun parses"
[ "$rc" -eq 7 ] && ok "--shotgun on a project with no account here is REFUSED (7)" \
  || bad "--shotgun exited $rc, want 7: $out"

out="$("$TARGET" elsewhere-proj --now 2>&1)"; rc=$?
[ "$rc" -eq 7 ] && ok "--now likewise refuses instead of hopping" \
  || bad "--now exited $rc, want 7: $out"
unset FAKE_GETENT_FAIL
[ -f "$WORK/ssh-calls.log" ] \
  && bad "the hop is gone but ssh was still called: $(cat "$WORK/ssh-calls.log")" \
  || ok "no ssh was attempted -- there is no host column to hop by"
rm -f "$FAKEBIN/ssh"

"$TARGET" --help 2>&1 | grep -qF -- '--shotgun'   && ok "--shotgun is in the usage block"   || bad "--shotgun works but --help never mentions it"

echo
echo "dose-project-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
