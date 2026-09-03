#!/usr/bin/env bash
# selfdev-credentials.sh -- read every self-dev account's credentials SIDE BY
# SIDE against one declared baseline, and converge one account to it.
# RUNNER: no -- needs `ssh $CRED_HOST` + passwordless `sudo -n -u <account>`
# GUARD-TEST: tests/selfdev-credentials.test.sh
# TRAPS (the rest of this header is in vault:scheduler/provisioning-block-headers-20260826.md):
# TRAP: pass `-` as the no-filter sentinel, NEVER "". ssh joins every argument
#   after the remote command into ONE string the far shell re-parses, so a
#   zero-length argument DISAPPEARS and every argument after it shifts left.
#   That measured the whole fleet BLIND and the hermetic suite could not see
#   it -- its stub ssh got a real argv array.
# TRAP: --audit (default) is READ-ONLY throughout, so it needs no
#   notify-senechal and is safe on a clock.
# TRAP: the credential is HOST-WIDE (/etc/selfdev/{app.pem,gh-app.conf},
#   group `selfdev`) since 2026-08-12. ANY surviving file under the retired
#   per-account directory is drift, app.pem and gh-app.conf included: a
#   private copy beside the host-wide one is a second source a rotation misses.
# TRAP: there are NO canonical-source knobs, deliberately. A second script
#   holding its own opinion about where the key lives is realisateur#209.
# exit (audit):  0 clean   1 drift or a per-account BLIND   6 fleet BLIND
# exit (apply):  0 converged / nothing to do   5 a step failed

set -uo pipefail

CLI_NAME='selfdev-credentials.sh'
CLI_SUMMARY='side-by-side self-dev account credential audit against one declared baseline, and single-account converge'
CLI_USAGE='  selfdev-credentials.sh            --audit (default): read all ten accounts, report side by side
  selfdev-credentials.sh --audit    same, explicit
  selfdev-credentials.sh --apply <account>   converge ONE account to the baseline'
CLI_FLAGS='--audit --apply'
CLI_POSITIONAL=any
CLI_EXITS='  audit: 0 clean   1 drift found, or an account could not be read (BLIND)   6 the whole fleet is BLIND
  apply: 0 converged, or nothing to do   5 a converge step failed   2 usage error'
. "$(dirname "${BASH_SOURCE[0]}")/../lib/cli-guard.sh"
cli_guard "$@"

. "$(dirname "${BASH_SOURCE[0]}")/lib/selfdev-credentials-set.sh"

# knobs -- all overridable so the suite needs no live ssh, gh or account.
CRED_HOST="${CRED_HOST:-monkey}"
CRED_SSH_BIN="${CRED_SSH_BIN:-ssh}"
CRED_GH_BIN="${CRED_GH_BIN:-gh}"
CRED_SSH_TIMEOUT="${CRED_SSH_TIMEOUT:-20}"
CRED_PASSWD_FILE="${CRED_PASSWD_FILE:-/etc/passwd}"       # a REMOTE path

OK_PREFIX='  ok    '; GAP_PREFIX='  gap   '; BAD_PREFIX='  FLAG [drift] '; ACT_PREFIX='  DO    '
# shellcheck source=../lib/provision-witness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/provision-witness.sh"
BLIND_N=0
blind() { printf '  BLIND %s\n' "$*"; BLIND_N=$((BLIND_N+1)); }

# THE REMOTE PROBE -- the ONLY place this script touches the network.
fetch_remote() { # fetch_remote [account-filter]
  # THE NO-FILTER SENTINEL: see the header TRAP. Do not pass "".
  local filter="${1:--}"
  "$CRED_SSH_BIN" -o BatchMode=yes -o ConnectTimeout="$CRED_SSH_TIMEOUT" "$CRED_HOST" "bash -s" \
      -- "$CRED_UID_MIN" "$CRED_UID_MAX" "$CRED_PASSWD_FILE" "$filter" "$CRED_GH_OWNER" $CRED_SHARED_REPOS \
      <<'REMOTE_PROBE'
set -uo pipefail
UMIN="$1"; UMAX="$2"; PWFILE="$3"; FILTER="$4"; shift 4
OWNER="$1"; shift
REPOS="$*"

probe_one() {
  local owner="$1"; shift
  local pem="${SELFDEV_APP_PEM:-/etc/selfdev/app.pem}"
  local conf="${SELFDEV_APP_CONF:-/etc/selfdev/gh-app.conf}"
  local hosts="$HOME/.config/gh/hosts.yml"
  local d="$HOME/.config/selfdev"
  local pem_state="missing"
  if [ -e "$pem" ]; then
    if head -c 1 -- "$pem" >/dev/null 2>&1; then pem_state="ok:600"; else pem_state="unreadable"; fi
  fi
  local conf_state="missing" keymatch="n/a" appid="-" ownerd="-"
  if [ -r "$conf" ]; then
    conf_state="ok"
    local dkey; dkey="$(sed -n "s/^SELFDEV_APP_KEY=//p" "$conf" | tail -1)"
    local a;    a="$(sed -n "s/^SELFDEV_APP_ID=//p" "$conf" | tail -1)"; [ -n "$a" ] && appid="$a"
    local o;    o="$(sed -n "s/^SELFDEV_GH_OWNER=//p" "$conf" | tail -1)"; [ -n "$o" ] && ownerd="$o"
    if [ -n "$dkey" ]; then
      [ "$dkey" = "$pem" ] && keymatch="match" || keymatch="mismatch:$dkey"
    fi
  fi
  local extra="-"
  if [ -d "$d" ]; then
    local ex; ex="$(ls -A "$d" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
    [ -n "$ex" ] && extra="$ex"
  fi
  local token="missing"
  if [ -r "$hosts" ]; then
    local line; line="$(grep oauth_token "$hosts" 2>/dev/null | head -1)"
    case "$line" in
      *gho_*)        token="gho" ;;
      *github_pat_*) token="pat" ;;
      *)             [ -n "$line" ] && token="other" ;;
    esac
  fi
  # "WIRED" was url.insteadOf; now the helper's shape, counts ZERO (#171).
  local wo; wo="$(git config --global --get-all credential."https://github.com".helper 2>/dev/null)"
  case "$(printf '%s' "$wo" | grep -c .)" in
    0) wo=none ;;
    1) case "$wo" in
         *selfdev-gh-app.sh*) wo=app ;;
         *"gh auth git-credential"*) wo=gh ;;
         *) wo=other ;;
       esac ;;
    *) wo=multi ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s' "$pem_state" "$conf_state" "$keymatch" "$token" "$extra" "$wo"
  local r wr
  for r in "$@"; do
    wr="$(git config --global --get-all "url.git@github-$r:$owner/$r.git.insteadof" 2>/dev/null | wc -l | tr -d ' ')"
    printf '\t%s' "$wr"
  done
  printf '\t%s\t%s\n' "$appid" "$ownerd"
}

while IFS=: read -r acct _ uid _ _ home _; do
  [ "$uid" -ge "$UMIN" ] 2>/dev/null || continue
  [ "$uid" -le "$UMAX" ] || continue
  [ "$FILTER" = "-" ] || [ "$acct" = "$FILTER" ] || continue
  # shellcheck disable=SC2086
  out="$(sudo -n -u "$acct" bash -c "$(declare -f probe_one); probe_one \"\$@\"" _ "$OWNER" $REPOS 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    printf '%s\tBLIND\n' "$acct"
  else
    printf '%s\t%s\n' "$acct" "$out"
  fi
done < "$PWFILE"
REMOTE_PROBE
}

# GRADING -- pure given a row, no network. cred_grade_account <account> <row>: prints the line(s), returns 0 clean / 1 drift / 2 blind.

cred_grade_account() {
  local acct="$1" row="$2"
  if [ -z "$row" ] || [ "$row" = "BLIND" ]; then
    blind "$acct: could not be read at all (sudo -n failed, or it does not exist in the uid band)"
    return 2
  fi

  local pem conf keymatch token extra wire_own wire_r1 wire_r2 wire_r3 appid ownerd
  IFS=$'\t' read -r pem conf keymatch token extra wire_own wire_r1 wire_r2 wire_r3 appid ownerd <<<"$row"

  printf '  %-16s pem=%-8s conf=%-4s token=%-4s extra=%-16s wire own=%s/3 shared=%s,%s,%s\n' \
    "$acct" "$pem" "$conf" "$token" "$extra" "$wire_own" "$wire_r1" "$wire_r2" "$wire_r3"

  local drift=0

  case "$pem" in
    ok:600) : ;;
    unreadable) bad "$acct: the host-wide App key exists but this account CANNOT READ IT -- check group '${CRED_APP_GROUP:-selfdev}' membership has taken effect (sudo bin/selfdev-app-key.sh --check)"; drift=1 ;;
    missing|*) bad "$acct: no host-wide App key at /etc/selfdev/app.pem -- no account on this host can mint an App token (sudo bin/selfdev-app-key.sh --apply)"; drift=1 ;;
  esac

  case "$conf" in
    ok) : ;;
    *) bad "$acct: no host-wide /etc/selfdev/gh-app.conf -- selfdev-gh-app.sh has nothing to read (sudo bin/selfdev-app-key.sh --apply)"; drift=1 ;;
  esac

  case "$keymatch" in
    match|n/a) : ;;
    mismatch:*) bad "$acct: gh-app.conf's SELFDEV_APP_KEY points at ${keymatch#mismatch:}, not the app.pem actually present"; drift=1 ;;
  esac

  if [ "$conf" = ok ]; then
    [ "$appid" = "$CRED_APP_ID" ]  || { bad "$acct: gh-app.conf declares App id '$appid', fleet baseline is $CRED_APP_ID"; drift=1; }
    [ "$ownerd" = "$CRED_GH_OWNER" ] || { bad "$acct: gh-app.conf declares owner '$ownerd', fleet baseline is $CRED_GH_OWNER"; drift=1; }
  fi

  case "$token" in
    # gho_ stays the baseline: git pushes as the App, `gh` uses this token.
    gho) : ;;
    missing) bad "$acct: no gh-token at all (~/.config/gh/hosts.yml unreadable or absent) -- gh CLI cannot authenticate: no issue filing, no deploy-key registration"; drift=1 ;;
    pat|other)
      if cred_grant_covers "$acct" token-type "$token"; then
        gap "$acct: gh-token is '$token' -- DECLARED in CRED_GRANTS, not baseline but on record"
      else
        bad "$acct: gh-token is '$token', not the fleet's 'gho_' baseline, and UNDECLARED in CRED_GRANTS -- this exact shape is what left ecosim 403ing on Pull requests for two days"
        drift=1
      fi
      ;;
  esac

  if [ "$extra" != "-" ]; then
    local old_ifs="$IFS" f
    local -a files=()
    IFS=','; read -ra files <<<"$extra"; IFS="$old_ifs"
    for f in "${files[@]}"; do
      [ -n "$f" ] || continue
      if cred_grant_covers "$acct" extra-file "$f"; then
        gap "$acct: extra file '$f' under ~/.config/selfdev/ -- DECLARED in CRED_GRANTS"
      else
        bad "$acct: leftover private file '$f' under ~/.config/selfdev/ -- the credential is host-wide now, so a private copy is a second source a rotation will miss; retire with \`sudo bin/selfdev-app-key.sh --retire-copies\`, or declare it in CRED_GRANTS with a dated reason"
        drift=1
      fi
    done
  fi

  case "$wire_own" in
    app) : ;;
    none)  bad "$acct: no git credential helper -- https pushes have no credential at all"; drift=1 ;;
    gh)    bad "$acct: git credential helper is still \`gh auth git-credential\`, i.e. the shared gho_ token -- run selfdev-gh-app.sh --wire"; drift=1 ;;
    multi) bad "$acct: credential.https://github.com.helper holds MORE THAN ONE value -- git takes the first that answers, so which credential pushes is not decidable from config. This is the shape that made --wire report OK on a write it never made"; drift=1 ;;
    *)     bad "$acct: git credential helper is '$wire_own', not the App"; drift=1 ;;
  esac
  local r i=0
  for r in $CRED_SHARED_REPOS; do
    i=$((i + 1))
    local w=""
    case "$i" in 1) w="$wire_r1" ;; 2) w="$wire_r2" ;; 3) w="$wire_r3" ;; esac
    [ "${w:-0}" = 0 ] || { bad "$acct: $r still has ${w} url.insteadOf rewrite(s) -- ssh wins over the helper, so this repo keeps pushing as a deploy key"; drift=1; }
  done

  [ "$drift" -eq 0 ] && ok "$acct: matches baseline"
  return "$drift"
}

# THE SYMMETRY CHECK -- deploy-key READ/WRITE level, from GitHub itself.
cred_check_deploy_keys() { # cred_check_deploy_keys <account>...
  if ! command -v "$CRED_GH_BIN" >/dev/null 2>&1; then
    blind "deploy-key symmetry: '$CRED_GH_BIN' not on PATH -- could not check GitHub-side read/write permissions"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    blind "deploy-key symmetry: jq not on PATH -- could not parse deploy-key listings"
    return
  fi
  if ! "$CRED_GH_BIN" auth status >/dev/null 2>&1; then
    blind "deploy-key symmetry: '$CRED_GH_BIN' is not authenticated here -- could not check GitHub-side read/write permissions"
    return
  fi
  # AN ACCOUNT OWNS ITS OWN REPO even when that repo is also on the shared list -- one unix user per project is the monkey design.
  local repo acct others
  for repo in $CRED_SHARED_REPOS; do
    others=""
    for acct in "$@"; do
      [ "$(cred_own_repo "$acct")" = "$repo" ] && continue
      others="$others $acct"
    done
    # shellcheck disable=SC2086
    [ -n "$others" ] && cred_check_repo_keys "$repo" ro $others
  done
  for acct in "$@"; do
    cred_check_repo_keys "$(cred_own_repo "$acct")" rw "$acct"
  done
}

# cred_check_repo_keys <repo> <ro|rw> <accounts...> -- list a repo's deploy keys ONCE and grade every named account, so a shared repo costs one call.
cred_check_repo_keys() {
  local repo="$1" want="$2"; shift 2
  # TRAP: gh 2.45.0 VALIDATES `--json readOnly` and then ignores the filter, so the field must be read out of the full object.
  local json; json="$("$CRED_GH_BIN" repo deploy-key list --repo "$CRED_GH_OWNER/$repo" --json title,readOnly 2>/dev/null)"
  if [ -z "$json" ]; then
    blind "deploy-key symmetry: could not list keys on $CRED_GH_OWNER/$repo (no admin access here, or the repo/call failed)"
    return
  fi
  local acct want_word; [ "$want" = rw ] && want_word="WRITE" || want_word="READ-ONLY"
  for acct in "$@"; do
    # TRAP: two jq calls, never `.readOnly // empty` -- jq's `//` falls through on `false` as well as null, which silently turned every WRITE key into "absent". Resolve readOnly-OR-read_only by KEY PRESENCE for the same reason.
    local suf="-$acct-$repo" found
    found="$(printf '%s' "$json" | jq -r --arg suf "$suf" '[.[] | select(.title | endswith($suf))] | length')"
    if [ "${found:-0}" -eq 0 ] 2>/dev/null; then
      bad "$acct: no deploy key registered on $repo (title ending '$suf') -- expected $want_word"
      continue
    fi
    local ro; ro="$(printf '%s' "$json" | jq -r --arg suf "$suf" '
      [.[] | select(.title | endswith($suf))][0] as $m
      | if ($m | has("readOnly")) then ($m.readOnly | tostring) else ($m.read_only | tostring) end
    ')"
    case "$want:$ro" in
      rw:false|ro:true) ok "$acct: $repo deploy key is $want_word, matching the symmetry rule" ;;
      rw:true)  bad "$acct: $repo (OWN repo) deploy key is READ-ONLY -- cannot push its own work" ;;
      ro:false) bad "$acct: $repo (SHARED repo) deploy key is WRITE -- the symmetry rule says shared repos are read-only; a stray write key here is exactly the cross-repo-push shape Zach flagged" ;;
      *)
        # TRAP: no default arm is how this hid the first time -- $ro read the literal string "null". Fail loud on an unrecognized shape.
        blind "deploy-key symmetry: $acct on $repo returned an unreadable readOnly value ('$ro') -- gh's JSON shape may have changed" ;;
    esac
  done
}

# --audit
cmd_audit() {
  echo "== selfdev-credentials --audit -- $CRED_HOST, uid $CRED_UID_MIN-$CRED_UID_MAX (read-only) =="
  echo "   baseline: bin/lib/selfdev-credentials-set.sh (App $CRED_APP_ID @ $CRED_GH_OWNER, shared repos: $CRED_SHARED_REPOS)"
  echo

  local out; out="$(fetch_remote "")"; local rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    echo "BLIND: could not reach $CRED_HOST at all (ssh rc=$rc). Nothing was verified." >&2
    return 6
  fi

  # TRAP: IFS=tab with MORE than two fields puts the whole rest of the line in the last variable -- which is the row string we want. Here-string, not a pipe, so `accounts+=` survives.
  local accounts=() acct row
  while IFS=$'\t' read -r acct row; do
    [ -n "$acct" ] || continue
    accounts+=("$acct")
    cred_grade_account "$acct" "$row"
  done <<<"$out"

  if [ "${#accounts[@]}" -eq 0 ]; then
    echo "BLIND: $CRED_HOST answered, but no account in uid $CRED_UID_MIN-$CRED_UID_MAX was found." >&2
    return 6
  fi

  echo
  echo "-- deploy-key symmetry (GitHub-side read/write, own repo vs shared) --"
  cred_check_deploy_keys "${accounts[@]}"

  echo
  echo "-- the redundancy note (informational; nothing acted on) --"
  echo "  every 'gho'/'pat' token above lives in ~/.config/gh/hosts.yml and is"
  echo "  used by the gh CLI (issue/PR listing, deploy-key registration)."
  echo "  hf7y/scheduler#103 (merged 2026-08-11) now mints a GitHub App"
  echo "  installation token at DISPATCH time, which makes this stored,"
  echo "  long-lived token redundant on that path. Not removed here -- see"
  echo "  this script's header. Filing the removal is a separate decision."

  echo
  printf 'selfdev-credentials: %d ok, %d gap, %d FLAG, %d BLIND, %d account(s)\n' \
    "$PASS" "$GAPS" "$BAD" "$BLIND_N" "${#accounts[@]}"
  if [ "$BAD" -gt 0 ] || [ "$BLIND_N" -gt 0 ]; then
    return 1
  fi
  return 0
}

# Idempotent, fails loud, NEVER touches ~/.config/gh/hosts.yml, NEVER deletes an "extra" file. Every step DELEGATES to a tested script -- no new way to mint a credential here.
cmd_apply() {
  local acct="$1"
  echo "== selfdev-credentials --apply $acct -- $CRED_HOST =="
  local fetched; fetched="$(fetch_remote "$acct")"; local rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$fetched" ]; then
    echo "selfdev-credentials --apply: could not reach $CRED_HOST, or '$acct' is not in the uid $CRED_UID_MIN-$CRED_UID_MAX band there (ssh rc=$rc) -- refusing to guess" >&2
    return 5
  fi
  local seen_acct data
  IFS=$'\t' read -r seen_acct data <<<"$fetched"
  if [ "$seen_acct" != "$acct" ] || [ -z "$data" ]; then
    echo "selfdev-credentials --apply: unexpected response reading $acct from $CRED_HOST -- refusing to guess" >&2
    return 5
  fi
  if [ "$data" = BLIND ]; then
    echo "selfdev-credentials --apply: $acct read as BLIND (sudo -n failed) -- fix sudo access before converging anything" >&2
    return 5
  fi

  local pem conf keymatch token extra wire_own wire_r1 wire_r2 wire_r3 appid ownerd
  IFS=$'\t' read -r pem conf keymatch token extra wire_own wire_r1 wire_r2 wire_r3 appid ownerd <<<"$data"

  local failed=0 changed=0

  # --- 1. the App credential: HOST-WIDE, placed by the script that owns it --
  if [ "$pem" != "ok:600" ] || [ "$conf" = missing ]; then
    act "placing the host-wide App credential and adding $acct to group $CRED_APP_GROUP (selfdev-app-key.sh --apply)"
    if "$CRED_SSH_BIN" -o BatchMode=yes "$CRED_HOST" \
         "sudo -n /home/${CRED_APPKEY_RUNNER:-zach}/Documents/Projects/realisateur/bin/selfdev-app-key.sh --apply --owner '$CRED_GH_OWNER'" 2>&1 | sed 's/^/    /'; then
      echo "  OK    host-wide App credential in place and readable by $acct"
      changed=1
    else
      echo "  FLAG  selfdev-app-key.sh --apply did not complete on $CRED_HOST -- run it there and read its rows: sudo bin/selfdev-app-key.sh --check" >&2
      failed=1
    fi
  else
    echo "  --    $acct already reads the host-wide App credential; left alone"
  fi

  # --- 2. the push path: the App over https, not per-repo ssh deploy keys --
  local leftover=$(( ${wire_r1:-0} + ${wire_r2:-0} + ${wire_r3:-0} ))
  if [ "$wire_own" = app ] && [ "$leftover" -eq 0 ]; then
    echo "  --    $acct already pushes as the App over https; left alone"
  else
    act "selfdev-gh-app.sh --wire as $acct (helper=$wire_own, $leftover leftover rewrite(s))"
    if "$CRED_SSH_BIN" -o BatchMode=yes "$CRED_HOST" \
         "sudo -n -u '$acct' bash -lc '${CRED_APP_WIRE:-/usr/local/libexec/selfdev/selfdev-gh-app.sh} --wire'"; then
      echo "  OK    $acct wired to the App"
      changed=1
    else
      echo "  FLAG  wiring $acct FAILED -- see selfdev-gh-app.sh's own output above" >&2
      failed=1
    fi
  fi

  # --- 3. what this NEVER does, said out loud in the run itself -------------
  echo "  --    ~/.config/gh/hosts.yml (the gh-token) was not touched -- gho_ is the baseline and stays; the App is the PUSH credential, not a replacement for gh's own auth"
  if [ "$extra" != "-" ]; then
    echo "  --    extra file(s) under ~/.config/selfdev/ ($extra) were not touched -- declare them in CRED_GRANTS or remove them by hand"
  fi

  echo
  if [ "$changed" -eq 0 ] && [ "$failed" -eq 0 ]; then
    echo "selfdev-credentials --apply $acct: nothing to do -- already at baseline."
    return 0
  fi
  if [ "$failed" -gt 0 ]; then
    echo "selfdev-credentials --apply $acct: FAILED -- see FLAG rows above. This IS machine-wide config; run notify-senechal once the remaining rows are clear." >&2
    return 5
  fi
  echo "selfdev-credentials --apply $acct: converged. This changed machine-wide config on $CRED_HOST -- run:"
  echo "    notify-senechal 'selfdev-credentials --apply converged $acct@$CRED_HOST to the credential baseline, owned by realisateur'"
  return 0
}

# main
main() {
  local mode=audit account=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --audit) mode=audit ;;
      --apply) mode=apply; account="${2:-}"; shift ;;
      *) echo "$CLI_NAME: unexpected argument: $1" >&2; exit 2 ;;
    esac
    shift
  done

  if [ "$mode" = apply ]; then
    [ -n "$account" ] || { echo "$CLI_NAME: --apply needs an account name" >&2; exit 2; }
    cmd_apply "$account"; exit $?
  fi
  cmd_audit; exit $?
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
