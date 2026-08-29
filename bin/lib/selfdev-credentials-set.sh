#!/usr/bin/env bash
# selfdev-credentials-set.sh -- THE SELF-DEV CREDENTIAL BASELINE, in one place.
# TRAPS (the rest of this header is in vault:scheduler/provisioning-block-headers-20260826.md):
# TRAP: THE DEFECT IS NEVER "the credential was wrong" -- that is a normal failure every script here reports loudly. It is that NOTHING COMPARED THE TEN. ecosim's fine-grained PAT missing Pull-requests returned 403 on that whole API for two days while `gh issue list`, green tests and pushed branches all kept working.
# TRAP: FORMAT is newline-separated rows consumed by `while read`, NOT shell code. A bare `"` in a row silently truncates this file, as it once truncated ownership-set.sh (deleted in #514).

CRED_GRANTS="
"

# --- the uid band -------------------------------------------------------
# Same band provision-selfdev-user.sh creates accounts in, same knob names
# selfdev-agent-survey.sh already uses -- one more reader of the same fact,
# not a second definition of it.
CRED_UID_MIN="${CRED_UID_MIN:-3000}"
CRED_UID_MAX="${CRED_UID_MAX:-3099}"

# --- the shared repos, read-only by baseline -----------------------------
CRED_SHARED_REPOS="realisateur scheduler senechal"

# --- the fleet-wide App, per vault:realisateur/MONKEY.md 11.1 -------------------------------
# One App across all ten accounts, decided 2026-08-07.
CRED_APP_GROUP="${CRED_APP_GROUP:-selfdev}"
CRED_APP_ID="${CRED_APP_ID:-4521586}"
CRED_GH_OWNER="${CRED_GH_OWNER:-hf7y}"

# --- the baseline file set, under ~/.config/selfdev/ ----------------------
CRED_BASELINE_FILES="app.pem gh-app.conf"

# cred_classify_token <line> -- given the raw `oauth_token:` line from
# hosts.yml (or empty), classify its SHAPE without ever handling the secret
# itself beyond a substring test. Pure, offline-testable.
cred_classify_token() {
  local line="$1"
  case "$line" in
    *gho_*)         echo gho ;;
    *github_pat_*)  echo pat ;;
    "")             echo missing ;;
    *)              echo other ;;
  esac
}

# cred_own_repo <account> -- the repo this account should hold WRITE on.
cred_own_repo() {
  printf '%s' "$1"
}

# cred_grant_covers <account> <kind> <what> -- is this exact exception
# declared? rc 0 = yes (and the caller must still REPORT it, never go quiet),
# rc 1 = no, this is undeclared drift.
cred_grant_covers() {
  local acct="$1" kind="$2" what="$3" g_acct g_kind g_what g_date
  while read -r g_acct g_kind g_what g_date _; do
    [ -n "$g_acct" ] || continue
    if [ "$g_acct" = "$acct" ] && [ "$g_kind" = "$kind" ] && [ "$g_what" = "$what" ]; then
      return 0
    fi
  done <<EOF
$CRED_GRANTS
EOF
  return 1
}

# cred_list_grants <account> -- print every declared grant for one account,
# one per line, for the audit's report section. Empty output means no grants.
cred_list_grants() {
  local acct="$1" g_acct g_kind g_what g_date g_rest
  while read -r g_acct g_kind g_what g_date g_rest; do
    [ -n "$g_acct" ] || continue
    [ "$g_acct" = "$acct" ] || continue
    printf '%s %s %s %s\n' "$g_kind" "$g_what" "$g_date" "$g_rest"
  done <<EOF
$CRED_GRANTS
EOF
}
