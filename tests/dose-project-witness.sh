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

cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\${FAKE_GH_MODE:-ok}" = "fail" ]; then
  echo "gh: authentication failed" >&2
  exit 1
fi
WORK="$WORK"
path="\$2"; shift 2 || true
declare -A F
JQEXPR=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -f) k="\${2%%=*}"; F["\$k"]="\${2#*=}"; shift 2 ;;
    --jq) JQEXPR="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "\$path" in
  graphql)
    if [ "\${FAKE_GH_AUTOMERGE_MODE:-ok}" = "fail" ]; then
      echo "gh: auto-merge is not allowed on this repository" >&2; exit 1
    fi
    echo "graphql" >> "\$WORK/gh-calls.log" ;;
  */git/ref/heads/*)
    if [ "\${FAKE_GH_BRANCH_MODE:-ok}" = "fail" ]; then
      echo "gh: could not resolve ref" >&2; exit 1
    fi
    echo "deadbeef0000" ;;
  */git/refs)
    if [ "\${FAKE_GH_BRANCH_MODE:-ok}" = "fail" ]; then
      echo "gh: Reference already exists" >&2; exit 1
    fi
    printf 'branch ref=%s sha=%s\n' "\${F[ref]:-}" "\${F[sha]:-}" >> "\$WORK/gh-calls.log" ;;
  */pulls)
    if [ "\${FAKE_GH_PR_MODE:-ok}" = "fail" ]; then
      echo "gh: could not create pull request" >&2; exit 1
    fi
    printf 'pr title=%s head=%s base=%s\n' "\${F[title]:-}" "\${F[head]:-}" "\${F[base]:-}" >> "\$WORK/gh-calls.log"
    echo "42 https://github.com/hf7y/scheduler/pull/42" ;;
  */pulls/*)
    echo "PR_kwFake" ;;
  */contents/schedule/ROSTER*)
    if [ -n "\${F[content]:-}" ]; then
      printf '%s' "\${F[content]}" | base64 -d > "\$WORK/written-roster"
      printf 'write dest=roster branch=%s\n' "\${F[branch]:-}" >> "\$WORK/gh-calls.log"
    else
      # absent: the FILE 404s but the REPO probe (the catch-all below) still
      # succeeds -- the exact pair that proves "not there" is knowable, and is
      # not the same event as "cannot look".
      if [ "\${FAKE_GH_MODE:-ok}" = "absent" ]; then
        echo "gh: Not Found (HTTP 404)" >&2; exit 1
      fi
      if [ "\$JQEXPR" = ".sha" ]; then echo "roster-sha-1"; else
        printf '%s' "\$FAKE_ROSTER_CONTENT" | base64 -w0
      fi
    fi ;;
  */contents/schedule/_runner.conf*)
    printf '%s' "\${FAKE_RUNNER_CONTENT:-}" | base64 -w0 ;;
  */contents/schedule/_runner.*.conf*)
    # scheduler#112: dose-project.sh reads a host override the same way
    # sync-crontab.sh does. Absent by default (most hosts have none of these
    # three fields overridden); FAKE_RUNNER_HOST_MODE=present serves one.
    if [ "\${FAKE_RUNNER_HOST_MODE:-absent}" = "absent" ]; then
      echo "gh: Not Found (HTTP 404)" >&2; exit 1
    fi
    printf '%s' "\${FAKE_RUNNER_HOST_CONTENT:-}" | base64 -w0 ;;
  *)
    # repo-reachability probe (repos/<slug>, no /contents/) -- always
    # succeeds here; FAKE_GH_MODE=fail above is the only "gh itself is down"
    # case this fixture models.
    echo "scheduler"; exit 0 ;;
esac
EOF
chmod +x "$FAKEBIN/gh"

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
  case "$1" in -n) shift ;; -u) shift 2 ;; *) break ;; esac
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
ROSTER="ecosim | ecosim@testhost | 6h | live
ghosttown | ghosttown@testhost | 6h | parked
elsewhere-proj | elsewhere-proj@otherhost | 6h | live"
# scheduler#112: RUNNER_JOB/RUNNER_CMD/RUNNER_ENV come from schedule/_runner.conf
# now, not a hardcoded second copy -- same values real _runner.conf carries
# today, so the TAG/cmd-path assertions below read exactly as they did before.
RUNNER_CONTENT='RUNNER_JOB="scheduler-paced-runner"
RUNNER_CMD="bin/usage-paced-runner.sh"
RUNNER_ENV="PACED_MAX_PER_TICK=1"
'

# --- 1. unknown project exits 4, not 0 --------------------------------------
export FAKE_GH_MODE=ok FAKE_ROSTER_CONTENT="$ROSTER" FAKE_RUNNER_CONTENT="$RUNNER_CONTENT"
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
out="$("$TARGET" elsewhere-proj --apply 2>&1)"; rc=$?
after="$(sha256sum "$CRONFILE")"
[ "$rc" -eq 7 ] && ok "wrong-host row exits 7 (refused)" \
  || bad "wrong-host row exited $rc, want 7: $out"
grep -qi 'REFUSED' <<<"$out" && ok "the refusal is named, not a generic error" \
  || bad "exit 7 but the message never says REFUSED: $out"
[ "$before" = "$after" ] && ok "wrong-host row: fixture crontab byte-unchanged (nothing touched)" \
  || bad "wrong-host row MODIFIED the crontab -- the guard is supposed to stop before any write: $out"

# --- 6. schedule/_runner.conf is read fresh, not hardcoded (#112) ----------
# A shared RUNNER_JOB of "renamed-job" (no host override) must show up in the
# emitted crontab TAG -- proves the value came from the fetched conf, not the
# old literal "scheduler-paced-runner" constant.
export CRONFILE="$WORK/cron6"; : > "$CRONFILE"
export FAKE_RUNNER_CONTENT='RUNNER_JOB="renamed-job"
RUNNER_CMD="bin/usage-paced-runner.sh"
RUNNER_ENV="PACED_MAX_PER_TICK=1"
'
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "apply with a renamed shared RUNNER_JOB still converges" \
  || bad "apply exited $rc with a renamed RUNNER_JOB: $out"
grep -qF 'scheduler:renamed-job:RUNNER' "$CRONFILE" \
  && ok "the emitted crontab TAG carries the fetched RUNNER_JOB, not a hardcoded one" \
  || bad "crontab does not reflect the fetched RUNNER_JOB: $(cat "$CRONFILE")"
export FAKE_RUNNER_CONTENT="$RUNNER_CONTENT"

# --- 7. a HOST-scoped override wins over the shared conf, per field (#112) -
export CRONFILE="$WORK/cron7"; : > "$CRONFILE"
export FAKE_RUNNER_HOST_MODE=present
export FAKE_RUNNER_HOST_CONTENT='RUNNER_ENV="PACED_MAX_PER_TICK=3"
'
out="$("$TARGET" ecosim --apply 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "apply with a host-scoped RUNNER_ENV override converges" \
  || bad "apply exited $rc with a host override present: $out"
grep -qF 'PACED_MAX_PER_TICK=3' "$CRONFILE" \
  && ok "the host-scoped RUNNER_ENV overrides the shared conf's value" \
  || bad "host override did not take effect: $(cat "$CRONFILE")"
grep -qF 'scheduler:scheduler-paced-runner:RUNNER' "$CRONFILE" \
  && ok "RUNNER_JOB, which the host file does NOT set, still comes from the shared conf" \
  || bad "an unset host field should not have blanked the shared value: $(cat "$CRONFILE")"
unset FAKE_RUNNER_HOST_MODE FAKE_RUNNER_HOST_CONTENT

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

# --- 10-12. arm/park writes schedule/ROSTER only now (#429, case 4 above) -
rm -f "$WORK/gh-calls.log" "$WORK/written-roster"
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--arm on a parked project exits 0" || bad "--arm exited $rc: $out"
grep -qF 'armed: PR #42' <<<"$out" && ok "--arm reports the PR armed for auto-merge" \
  || bad "--arm did not report an armed PR: $out"
grep -qF 'branch ref=refs/heads/dose-arm-ghosttown-' "$WORK/gh-calls.log" \
  && ok "a fresh branch was created for the write" \
  || bad "no branch-create call logged: $(cat "$WORK/gh-calls.log" 2>&1)"
grep -qF 'write dest=roster' "$WORK/gh-calls.log" \
  && ok "schedule/ROSTER was written on that branch" \
  || bad "no roster write logged: $(cat "$WORK/gh-calls.log" 2>&1)"
grep -qF 'ghosttown | ghosttown@testhost | 6h | live' "$WORK/written-roster" \
  && ok "the written ROSTER flips ghosttown's row to live" \
  || bad "written ROSTER does not carry the flipped row: $(cat "$WORK/written-roster" 2>&1)"
grep -qF 'ecosim | ecosim@testhost | 6h | live' "$WORK/written-roster" \
  && ok "the written ROSTER leaves ecosim's row untouched" \
  || bad "an unrelated row changed: $(cat "$WORK/written-roster" 2>&1)"

rm -f "$WORK/gh-calls.log"
out="$("$TARGET" ecosim --arm 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--arm on an already-live project exits 0" || bad "--arm exited $rc: $out"
grep -qF 'kept' <<<"$out" && ok "--arm on an already-live project reports kept" \
  || bad "--arm on a live project didn't say kept: $out"
[ -f "$WORK/gh-calls.log" ] && bad "a no-op --arm still wrote to gh -- $(cat "$WORK/gh-calls.log")" \
  || ok "a no-op --arm wrote nothing"

rm -f "$WORK/gh-calls.log" "$WORK/written-roster"
out="$("$TARGET" ecosim --park 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "--park on a live project exits 0" || bad "--park exited $rc: $out"
grep -qF 'ecosim | ecosim@testhost | 6h | parked' "$WORK/written-roster" \
  && ok "--park flips the ROSTER row to parked" \
  || bad "written ROSTER does not carry parked: $(cat "$WORK/written-roster" 2>&1)"
export FAKE_GETENT_FAIL=ecosim
out2="$("$TARGET" ecosim --park 2>&1)"; rc2=$?
unset FAKE_GETENT_FAIL
[ "$rc2" -eq 0 ] && ok "--park does not require the account to exist" \
  || bad "--park with no unix account exited $rc2, want 0: $out2"

# --- 13. degrade path: no auto-merge -----------------------------------
rm -f "$WORK/gh-calls.log"
export FAKE_GH_AUTOMERGE_MODE=fail
out="$("$TARGET" ghosttown --arm 2>&1)"; rc=$?
unset FAKE_GH_AUTOMERGE_MODE
[ "$rc" -eq 0 ] && ok "--arm still exits 0 when auto-merge cannot be armed" \
  || bad "--arm exited $rc when auto-merge failed, want 0: $out"
grep -qF 'opened: PR #42' <<<"$out" && ok "--arm reports opened-not-armed when auto-merge fails" \
  || bad "--arm did not degrade its message: $out"

echo
echo "dose-project-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
