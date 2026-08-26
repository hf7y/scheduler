# NAMING RULE: this suite prefixes its helpers `t_`. The script under test defines global ok()/gap()/bad() and sourcing it REDEFINES same-named functions -- a first draft passed 11/11 with every failing assertion swallowed into the SCRIPT's counter. A suite cannot catch its own silencing.
set -uo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"

REPO_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"  # tests/ -> bin/ (was bin/tests/ in realisateur)
SCRIPT="$REPO_BIN/selfdev-credentials.sh"
LIB="$REPO_BIN/lib/selfdev-credentials-set.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }
[ -f "$LIB" ]    || { echo "FAIL: $LIB missing"; exit 1; }

t_ok()  { echo "  ok   $1"; pass=$((pass+1)); }
t_bad() { echo "  FAIL $1"; fail=$((fail+1)); }
t_eq()    { if [ "$2" = "$3" ]; then t_ok "$1"; else t_bad "$1 (expected '$3', got '$2')"; fi; }
t_has()   { case "$2" in *"$3"*) t_ok "$1" ;; *) t_bad "$1 (missing: $3)" ;; esac; }
t_hasnt() { case "$2" in *"$3"*) t_bad "$1 (unexpectedly present: $3)" ;; *) t_ok "$1" ;; esac; }
t_rc()    { if [ "$2" = "$3" ]; then t_ok "$1"; else t_bad "$1 (expected exit $2, got $3)"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "-- A. bin/lib/selfdev-credentials-set.sh: the pure baseline functions --"
# shellcheck source=/dev/null
. "$LIB"

t_eq "classify: gho_ token"          "$(cred_classify_token 'oauth_token: gho_wkxBabc123')" gho
t_eq "classify: github_pat_ token"   "$(cred_classify_token 'oauth_token: github_pat_11ABC')" pat
t_eq "classify: classic ghp_ token"  "$(cred_classify_token 'oauth_token: ghp_abc123')" other
t_eq "classify: no line at all"      "$(cred_classify_token '')" missing

t_eq "own_repo: identity mapping"    "$(cred_own_repo ecosim)" ecosim
t_eq "own_repo: hyphenated account"  "$(cred_own_repo groc-mangr)" groc-mangr

[ -z "$(cred_list_grants ecosim)" ] && t_ok "grants: shipped CRED_GRANTS has no rows for ecosim" \
                                     || t_bad "grants: shipped CRED_GRANTS unexpectedly has rows"
if cred_grant_covers ecosim extra-file ecosim.pem; then
  t_bad "grants: ecosim.pem is covered, but no such grant is declared -- CRED_GRANTS drifted"
else
  t_ok "grants: an undeclared exception (ecosim.pem) is correctly NOT covered"
fi

# A locally-scoped grant, declared the same way the real file documents,
# proves the LOOKUP works without ever editing the shipped table.
CRED_GRANTS='
ecosim  extra-file  ecosim.pem  2026-08-11  fixture-only test grant
'
if cred_grant_covers ecosim extra-file ecosim.pem; then
  t_ok "grants: a declared exception IS covered"
else
  t_bad "grants: a declared exception was not recognized"
fi
if cred_grant_covers vim-arcade extra-file ecosim.pem; then
  t_bad "grants: a grant leaked to an account it was not declared for"
else
  t_ok "grants: a grant does not apply to a different account"
fi
t_has "grants: cred_list_grants prints the declared row" "$(cred_list_grants ecosim)" "2026-08-11"
. "$LIB"

echo
echo "-- B. cred_grade_account: pure grading, no network --------------------"
# shellcheck source=/dev/null
. "$SCRIPT"   # BASH_SOURCE guard keeps main()/cmd_audit's ssh call from firing

# grade <account> <row> -- sets GLOBALS, not a captured string: `read` stops at the first newline regardless of IFS, and this output is multi-line.
grade() {
  GRADE_OUT="$(cred_grade_account "$1" "$2" 2>&1)"; GRADE_RC=$?
  GRADE_FLAGS="$(grep -c '^  FLAG \[drift\]' <<<"$GRADE_OUT" || true)"
  GRADE_GAPS="$(grep -c '^  gap   '          <<<"$GRADE_OUT" || true)"
}

CLEAN_ROW=$'ok:600\tok\tmatch\tgho\t-\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade clean-acct "$CLEAN_ROW"
t_eq "clean row: 0 FLAG"   "$GRADE_FLAGS" 0
t_eq "clean row: exit 0"   "$GRADE_RC" 0
t_has "clean row: reports matches baseline" "$GRADE_OUT" "matches baseline"

grade ghost "BLIND"
t_eq "BLIND row: exit 2"          "$GRADE_RC" 2
t_has "BLIND row: reported as BLIND, not ok" "$GRADE_OUT" "BLIND"

grade nobody ""
t_eq "empty row: treated the same as BLIND (exit 2)" "$GRADE_RC" 2

# pem grades whether the account can READ /etc/selfdev/app.pem (host-wide since 2026-08-12). `unreadable` is the real case: group granted, not yet in effect for the session.
UNREADABLE_PEM_ROW=$'unreadable\tok\tmatch\tgho\t-\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$UNREADABLE_PEM_ROW"
t_has "host-wide key present but unreadable: flagged" "$GRADE_OUT" "CANNOT READ IT"
t_has "host-wide key unreadable: names the group to check" "$GRADE_OUT" "selfdev-app-key.sh --check"
[ "$GRADE_FLAGS" -ge 1 ] && t_ok "unreadable pem: at least one FLAG" || t_bad "unreadable pem: no FLAG counted"

MISSING_PEM_ROW=$'missing\tok\tn/a\tgho\t-\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$MISSING_PEM_ROW"
t_has "missing pem: flagged, names the consequence" "$GRADE_OUT" "no account on this host can mint an App token"
t_has "missing pem: names the one command that fixes it" "$GRADE_OUT" "selfdev-app-key.sh --apply"

MISSING_CONF_ROW=$'ok:600\tmissing\tn/a\tgho\t-\tapp\t0\t0\t0\t-\t-'
grade x "$MISSING_CONF_ROW"
t_has "missing conf: flagged" "$GRADE_OUT" "no host-wide /etc/selfdev/gh-app.conf"
t_hasnt "missing conf: does NOT also flag appid/owner (nothing to compare)" "$GRADE_OUT" "declares App id"

# A fixture path deliberately NOT shaped like /home/<name>/... -- hardcoded-home-lint scans tracked files and flags on sight, fixture or not.
MISMATCH_ROW=$'ok:600\tok\tmismatch:/var/tmp/selfdev-fixture/OTHER.pem\tgho\t-\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$MISMATCH_ROW"
t_has "SELFDEV_APP_KEY mismatch: flagged" "$GRADE_OUT" "points at /var/tmp/selfdev-fixture/OTHER.pem"

WRONG_APPID_ROW=$'ok:600\tok\tmatch\tgho\t-\tapp\t0\t0\t0\t9999999\t'"$CRED_GH_OWNER"
grade x "$WRONG_APPID_ROW"
t_has "divergent App id: flagged against the fleet baseline" "$GRADE_OUT" "fleet baseline is $CRED_APP_ID"

# The exact live shape found 2026-08-11: a fine-grained PAT, undeclared.
PAT_ROW=$'ok:600\tok\tmatch\tpat\t-\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade ecosim "$PAT_ROW"
t_has "undeclared PAT: flagged, names the ecosim incident" "$GRADE_OUT" "403ing on Pull requests"
[ "$GRADE_FLAGS" -ge 1 ] && t_ok "undeclared PAT: counted as FLAG, not gap" || t_bad "undeclared PAT: not counted as a FLAG"

# Same PAT, but declared: gap, not a FLAG.
CRED_GRANTS='
ecosim  token-type  pat  2026-08-11  fixture grant
'
grade ecosim "$PAT_ROW"
[ "$GRADE_FLAGS" -eq 0 ] && t_ok "declared PAT grant: no FLAG raised" || t_bad "declared PAT grant: still flagged ($GRADE_FLAGS FLAG)"
[ "$GRADE_GAPS" -ge 1 ] && t_ok "declared PAT grant: recorded as a gap (visible, not silent)" || t_bad "declared PAT grant: not recorded at all"
# shellcheck source=/dev/null
. "$LIB"   # restore the empty table

MISSING_TOKEN_ROW=$'ok:600\tok\tmatch\tmissing\t-\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$MISSING_TOKEN_ROW"
t_has "no gh-token at all: flagged" "$GRADE_OUT" "gh CLI cannot authenticate"


EXTRA_ROW=$'ok:600\tok\tmatch\tgho\tecosim.pem\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade ecosim "$EXTRA_ROW"
t_has "leftover private file: flagged" "$GRADE_OUT" "leftover private file 'ecosim.pem'"
t_has "leftover private file: names why a second copy is drift" "$GRADE_OUT" "a rotation will miss"

# app.pem under ~/.config/selfdev/ is a leftover now: the host-wide file is the credential, a private copy beside it is the second source.
LEFTOVER_BASELINE_ROW=$'ok:600\tok\tmatch\tgho\tapp.pem,gh-app.conf\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$LEFTOVER_BASELINE_ROW"
t_has "a private app.pem copy is itself drift now" "$GRADE_OUT" "leftover private file 'app.pem'"
t_has "...and so is a private gh-app.conf" "$GRADE_OUT" "leftover private file 'gh-app.conf'"

EXTRA_TWO_ROW=$'ok:600\tok\tmatch\tgho\ta.pem,b.pem\tapp\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$EXTRA_TWO_ROW"
t_has "two extra files: both named" "$GRADE_OUT" "'a.pem'"
t_has "two extra files: both named (second)" "$GRADE_OUT" "'b.pem'"
[ "$GRADE_FLAGS" -ge 2 ] && t_ok "two extra files: two separate FLAGs" || t_bad "two extra files: expected >=2 FLAGs, got $GRADE_FLAGS"

NO_HELPER_ROW=$'ok:600\tok\tmatch\tgho\t-\tnone\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade ecosim "$NO_HELPER_ROW"
t_has "no credential helper: flagged, names the consequence" "$GRADE_OUT" "https pushes have no credential at all"

GH_HELPER_ROW=$'ok:600\tok\tmatch\tgho\t-\tgh\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$GH_HELPER_ROW"
t_has "a gh-auth helper is the old shared token by another route" "$GRADE_OUT" "gh auth git-credential"

MULTI_HELPER_ROW=$'ok:600\tok\tmatch\tgho\t-\tmulti\t0\t0\t0\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$MULTI_HELPER_ROW"
t_has "two helpers: flagged as undecidable" "$GRADE_OUT" "MORE THAN ONE value"

LEFTOVER_REWRITE_ROW=$'ok:600\tok\tmatch\tgho\t-\tapp\t0\t0\t3\t'"$CRED_APP_ID"$'\t'"$CRED_GH_OWNER"
grade x "$LEFTOVER_REWRITE_ROW"
t_has "a leftover insteadOf rewrite is flagged by repo name" "$GRADE_OUT" "senechal still has 3 url.insteadOf rewrite(s)"

echo
echo "-- C. the CLI contract (cli-guard, --help, unknown flags) -------------"
"$SCRIPT" --not-a-real-flag >/dev/null 2>&1; t_rc "unknown flag exits 2" 2 $?
"$SCRIPT" --help >/dev/null 2>&1;            t_rc "--help exits 0" 0 $?
HELP_OUT="$("$SCRIPT" --help 2>&1)"
t_has "--help documents --audit as default" "$HELP_OUT" "--audit (default)"
t_has "--help documents --apply" "$HELP_OUT" "--apply <account>"
t_has "--help documents the BLIND exit" "$HELP_OUT" "BLIND"

"$SCRIPT" --apply >/dev/null 2>&1; t_rc "--apply with no account exits 2" 2 $?
STRAY_OUT="$("$SCRIPT" strayword 2>&1)"; STRAY_RC=$?
t_rc "a bare positional with no flag exits 2" 2 "$STRAY_RC"
t_has "the bare-positional error names the offending word" "$STRAY_OUT" "strayword"

echo
echo "-- D. --audit over a stubbed transport (no live ssh, no live gh) ------"
STUB="$T/stub"; mkdir -p "$STUB"

# A stub `ssh` that answers fetch_remote's `bash -s -- <args...>` shape (the
# FILTER positional is the 4th token after "--") from $STUB_ROWS, and treats
# any OTHER invocation (cmd_apply's one-shot commands) as "log it, succeed" --
cat > "$STUB/ssh" <<'STUBSH'
#!/usr/bin/env bash
LOG="${STUB_LOG:-/dev/null}"
flat="$*"
case "$flat" in
  *" -- "*)
    after="${flat#*-- }"
    # shellcheck disable=SC2206
    args=($after)
    filter="${args[3]:-}"
    cat < /dev/null
    if [ -n "$filter" ] && [ "$filter" != "-" ]; then
      printf '%s\n' "${STUB_ROWS:-}" | grep "^$filter"$'\t' || true
    else
      printf '%s\n' "${STUB_ROWS:-}"
    fi
    exit "${STUB_SSH_RC:-0}"
    ;;
esac
cmd="$flat"
stdin_hash="-"; [ -t 0 ] || stdin_hash="$(cat 2>/dev/null | sha256sum | cut -d' ' -f1)"
printf 'CMD: %s | STDIN: %s\n' "$cmd" "$stdin_hash" >> "$LOG"
[ -n "${STUB_FAIL_MATCH:-}" ] && [[ "$cmd" == *"$STUB_FAIL_MATCH"* ]] && exit 1
exit 0
STUBSH
chmod +x "$STUB/ssh"

# A stub `gh` for the deploy-key symmetry section. `readOnly` per repo is read
# from $STUB_JSON_<repo> so different scenarios can be expressed without
# touching this file.
cat > "$STUB/gh" <<'STUBGH'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") [ "${STUB_GH_AUTH_FAIL:-0}" = 1 ] && exit 1; exit 0 ;;
  "repo deploy-key")
    repo=""
    for ((i=1; i<=$#; i++)); do [ "${!i}" = "--repo" ] && { j=$((i+1)); repo="${!j}"; }; done
    var="STUB_JSON_${repo#hf7y/}"; var="${var//-/_}"
    printf '%s' "${!var:-[]}"
    ;;
  *) exit 1 ;;
esac
STUBGH
chmod +x "$STUB/gh"

FULL_CLEAN_ROWS='fleet-clean	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y'
# A GENUINELY clean run needs the deploy-key symmetry section clean too, not
# merely absent -- gh being unreachable is its own BLIND (asserted separately
# below) and correctly keeps the overall exit non-zero, matching this
# script's "BLIND is never ok" contract. So THIS case supplies a gh stub that
# reports the exact fixture account correctly wired on all four repos.
O="$(STUB_ROWS="$FULL_CLEAN_ROWS" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" \
     STUB_JSON_realisateur='[{"title":"monkey-fleet-clean-realisateur","readOnly":true}]' \
     STUB_JSON_scheduler='[{"title":"monkey-fleet-clean-scheduler","readOnly":true}]' \
     STUB_JSON_senechal='[{"title":"monkey-fleet-clean-senechal","readOnly":true}]' \
     STUB_JSON_fleet_clean='[{"title":"monkey-fleet-clean-fleet-clean","readOnly":false}]' \
     "$SCRIPT" --audit 2>&1)"; R=$?
t_rc "a genuinely clean fleet (files AND deploy keys) exits 0" 0 "$R"
t_has "clean fleet: reports matches baseline" "$O" "fleet-clean: matches baseline"

# The SAME file-level-clean fixture, with gh unreachable, must NOT read as
# clean -- BLIND on one section still makes the overall run non-zero.
O="$(STUB_ROWS="$FULL_CLEAN_ROWS" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN=/nonexistent-gh "$SCRIPT" --audit 2>&1)"; R=$?
t_rc "file-clean but gh unreachable still exits non-zero (BLIND is never ok)" 1 "$R"

FULL_DRIFT_ROWS='fleet-drift	missing	missing	n/a	pat	x.pem	0	3	3	3	-	-'
O="$(STUB_ROWS="$FULL_DRIFT_ROWS" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN=/nonexistent-gh "$SCRIPT" --audit 2>&1)"; R=$?
t_rc "a drifted fleet exits 1" 1 "$R"
t_has "drifted fleet: FLAG on missing pem" "$O" "no host-wide App key"
t_has "drifted fleet: prints the redundancy note" "$O" "redundant on that path"
t_has "drifted fleet: names hf7y/scheduler#103" "$O" "scheduler#103"

MIXED_ROWS=$'fleet-clean\tok:600\tok\tmatch\tgho\t-\tapp\t0\t0\t0\t4521586\thf7y\nfleet-blind\tBLIND'
O="$(STUB_ROWS="$MIXED_ROWS" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN=/nonexistent-gh "$SCRIPT" --audit 2>&1)"; R=$?
t_rc "one BLIND account among clean ones still exits 1 (never silently ok)" 1 "$R"
t_has "mixed fleet: BLIND account reported, not skipped" "$O" "fleet-blind"
t_has "mixed fleet: BLIND account marked BLIND, not ok" "$O" "BLIND fleet-blind"

O="$(STUB_SSH_RC=255 CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN=/nonexistent-gh "$SCRIPT" --audit 2>&1)"; R=$?
t_rc "an unreachable host exits 6 BLIND, not 0 and not 1" 6 "$R"
t_has "unreachable host: says BLIND and names nothing was verified" "$O" "Nothing was verified"

O="$(STUB_ROWS="" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN=/nonexistent-gh "$SCRIPT" --audit 2>&1)"; R=$?
t_rc "zero accounts found exits 6 (BLIND, not a clean empty fleet)" 6 "$R"

# --- gh missing/unauthenticated degrades to BLIND, not a crash -------------
O="$(STUB_ROWS="$FULL_CLEAN_ROWS" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN=/nonexistent-gh "$SCRIPT" --audit 2>&1)"
t_has "gh absent: deploy-key section reports BLIND by name" "$O" "not on PATH -- could not check GitHub-side"

O="$(STUB_ROWS="$FULL_CLEAN_ROWS" CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" STUB_GH_AUTH_FAIL=1 "$SCRIPT" --audit 2>&1)"
t_has "gh unauthenticated: deploy-key section reports BLIND by name" "$O" "not authenticated here"

echo
echo "-- D2. deploy-key symmetry grading -- the false/null jq regression ----"
# THE REGRESSION THIS PINS: jq's `//` treats `false` as falsy, same as
# `null`. A first draft used `.readOnly // empty`, which turned every
STUB_JSON_solo="$(printf '[{"title":"monkey-solo-solo","readOnly":false}]')"
O="$(STUB_ROWS='solo	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y' \
     CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" \
     STUB_JSON_realisateur='[]' STUB_JSON_scheduler='[]' STUB_JSON_senechal='[]' \
     STUB_JSON_solo="$STUB_JSON_solo" \
     "$SCRIPT" --audit 2>&1)"
t_has "own-repo readOnly:false is recognized as WRITE, not 'no key'" "$O" "solo: solo deploy key is WRITE, matching the symmetry rule"
t_hasnt "own-repo readOnly:false is NOT reported as missing" "$O" "no deploy key registered on solo"

STUB_JSON_realisateur='[{"title":"monkey-writer-realisateur","readOnly":false}]'
O="$(STUB_ROWS='writer	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y' \
     CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" \
     STUB_JSON_realisateur="$STUB_JSON_realisateur" STUB_JSON_scheduler='[]' STUB_JSON_senechal='[]' \
     STUB_JSON_writer='[]' \
     "$SCRIPT" --audit 2>&1)"
t_has "a WRITE key on a SHARED repo is flagged (the cross-repo-push shape)" "$O" "realisateur (SHARED repo) deploy key is WRITE"

echo
echo "-- D3. deploy-key symmetry grading -- the read_only field-name regression"
# THE REGRESSION THIS PINS, FOUND LIVE AGAINST THE REAL FLEET (not a fixture):
# `gh repo deploy-key list --json title,readOnly` on gh 2.45.0 VALIDATES
STUB_JSON_realword='[{"title":"monkey-realword-realword","read_only":false}]'
O="$(STUB_ROWS='realword	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y' \
     CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" \
     STUB_JSON_realisateur='[{"title":"monkey-realword-realisateur","read_only":true}]' \
     STUB_JSON_scheduler='[{"title":"monkey-realword-scheduler","read_only":true}]' \
     STUB_JSON_senechal='[{"title":"monkey-realword-senechal","read_only":true}]' \
     STUB_JSON_realword="$STUB_JSON_realword" \
     "$SCRIPT" --audit 2>&1)"
R_RC=$?
t_has "real gh shape (read_only, own repo, false=WRITE): recognized" "$O" "realword: realword deploy key is WRITE, matching the symmetry rule"
t_has "real gh shape (read_only, shared repo, true=READ-ONLY): recognized" "$O" "realword: realisateur deploy key is READ-ONLY, matching the symmetry rule"
t_rc "a fully correct real-shape fleet exits 0" 0 "$R_RC"

# A WRITE key on a shared repo, expressed in the REAL field name, must still
# be caught -- not just the camelCase fixture D2 already exercises.
O="$(STUB_ROWS='badword	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y' \
     CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" \
     STUB_JSON_realisateur='[{"title":"monkey-badword-realisateur","read_only":false}]' \
     STUB_JSON_scheduler='[]' STUB_JSON_senechal='[]' STUB_JSON_badword='[]' \
     "$SCRIPT" --audit 2>&1)"
t_has "real gh shape: a WRITE key on a shared repo is still flagged" "$O" "realisateur (SHARED repo) deploy key is WRITE"

# The fail-loud default arm itself: an unrecognized readOnly-shaped value
# must read as BLIND, never as silence. Exercised directly, not by trying to
# reproduce a gh version skew: `has()` on the fixture object true either way,
O="$(STUB_ROWS='oddshape	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y' \
     CRED_SSH_BIN="$STUB/ssh" CRED_GH_BIN="$STUB/gh" \
     STUB_JSON_realisateur='[{"title":"monkey-oddshape-realisateur","readOnly":"maybe"}]' \
     STUB_JSON_scheduler='[]' STUB_JSON_senechal='[]' STUB_JSON_oddshape='[]' \
     "$SCRIPT" --audit 2>&1)"
t_has "an unrecognized readOnly value is reported BLIND, never silent" "$O" "returned an unreadable readOnly value"

echo
echo "-- E. --apply: idempotency, converge actions, and refusals ------------"
# NO FIXTURE SOURCE KEY any more. --apply used to push a private copy of the
# App key into the account from a local source path, and the source-path knobs

LOG="$T/apply.log"; : > "$LOG"
CLEAN_SINGLE='conv-clean	ok:600	ok	match	gho	-	app	0	0	0	4521586	hf7y'
O="$(STUB_ROWS="$CLEAN_SINGLE" CRED_SSH_BIN="$STUB/ssh" STUB_LOG="$LOG" \
     "$SCRIPT" --apply conv-clean 2>&1)"; R=$?
t_rc "apply on an already-compliant account exits 0" 0 "$R"
t_has "apply on a compliant account reports nothing to do" "$O" "nothing to do"
[ -s "$LOG" ] && t_bad "apply on a compliant account issued a remote command (log not empty)" \
              || t_ok "apply on a compliant account issued NO remote command"

: > "$LOG"
NEEDS_CREDS='conv-fix	missing	missing	n/a	gho	-	none	0	0	0	-	-'
O="$(STUB_ROWS="$NEEDS_CREDS" CRED_SSH_BIN="$STUB/ssh" STUB_LOG="$LOG" \
     "$SCRIPT" --apply conv-fix 2>&1)"; R=$?
t_rc "apply that converges credential+wiring exits 0" 0 "$R"
t_has "apply reports the host-wide placement" "$O" "host-wide App credential"
t_has "apply reminds the operator to notify-senechal" "$O" "notify-senechal 'selfdev-credentials --apply"
t_has "apply delegates placement to selfdev-app-key.sh --apply" "$(cat "$LOG")" "selfdev-app-key.sh --apply"
t_hasnt "apply never writes a per-account app.pem again" "$(cat "$LOG")" "/.config/selfdev/app.pem"
t_has "apply switches the account with selfdev-gh-app.sh --wire" "$(cat "$LOG")" "selfdev-gh-app.sh --wire"
t_hasnt "apply no longer wires per-repo deploy keys" "$(cat "$LOG")" "wire-selfdev-git.sh"
t_hasnt "apply never touches hosts.yml without the flag" "$(cat "$LOG")" "hosts.yml"

: > "$LOG"
# The placement step failing on the host is reported, not swallowed: the
# account is left exactly as it was and the operator is pointed at the one
# command that explains why.
O="$(STUB_ROWS='conv-nokey	missing	missing	n/a	gho	-	app	0	0	0	-	-' \
     CRED_SSH_BIN="$STUB/ssh" STUB_LOG="$LOG" \
     STUB_FAIL_MATCH="selfdev-app-key.sh" \
     "$SCRIPT" --apply conv-nokey 2>&1)"; R=$?
t_rc "apply exits 5 when the host-wide placement fails" 5 "$R"
t_has "apply names the command that explains it" "$O" "selfdev-app-key.sh --check"

: > "$LOG"
O="$(STUB_ROWS='conv-blind	BLIND' CRED_SSH_BIN="$STUB/ssh" STUB_LOG="$LOG" "$SCRIPT" --apply conv-blind 2>&1)"; R=$?
t_rc "apply against a BLIND account exits 5" 5 "$R"
t_has "apply on a BLIND account refuses by name" "$O" "read as BLIND"
[ -s "$LOG" ] && t_bad "apply on a BLIND account still issued a remote command" \
              || t_ok "apply on a BLIND account issued NO remote command"

: > "$LOG"
O="$(STUB_ROWS='conv-fail	ok:600	ok	match	gho	-	none	0	0	0	4521586	hf7y' \
     STUB_FAIL_MATCH="selfdev-gh-app.sh --wire" \
     CRED_SSH_BIN="$STUB/ssh" STUB_LOG="$LOG" \
     "$SCRIPT" --apply conv-fail 2>&1)"; R=$?
t_rc "apply propagates a failed delegate step as exit 5" 5 "$R"
t_has "apply reports the failed step and does not claim success" "$O" "FAILED"

O="$(STUB_ROWS="" CRED_SSH_BIN="$STUB/ssh" "$SCRIPT" --apply unknown-account 2>&1)"; R=$?
t_rc "apply against an account outside the uid band exits 5" 5 "$R"

echo
echo "-- F. source invariants -- what --apply must never even attempt -------"
SRC_TXT="$(cat "$SCRIPT")"
t_hasnt "never deletes anything (no rm -f/-r on a credential path)" "$SRC_TXT" 'rm -'
t_hasnt "never truncates or writes ~/.config/gh/hosts.yml" "$SRC_TXT" 'hosts.yml"'$'\n''>'
t_hasnt "never opens hosts.yml for writing (> or >>)" "$SRC_TXT" '> "$hosts'
t_hasnt "never mints a NEW key (no ssh-keygen)" "$SRC_TXT" "ssh-keygen"
t_hasnt "never mints a NEW key (no openssl genrsa/req)" "$SRC_TXT" "openssl genrsa"
t_has "does delegate the git switch to selfdev-gh-app.sh --wire (reuse, not reimplement)" "$SRC_TXT" "selfdev-gh-app.sh} --wire"
t_has "declares its opt-out with a reason" "$SRC_TXT" "# RUNNER: no --"
t_has "reads the token's oauth_token line but never echoes the token value" "$SRC_TXT" "grep oauth_token"
t_hasnt "the token classifier never captures anything past the shape prefix" "$SRC_TXT" 'printf.*oauth_token.*\$token'

echo
summary
