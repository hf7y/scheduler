#!/usr/bin/env bash
# lib/gh-app-token.sh -- mint a one-hour GitHub App installation token when
# this account is wired for one, and export it as GH_TOKEN. Witness:
# tests/gh-app-token-witness.sh.
# TRAP: without this, `gh` uses whatever long-lived token sits in the
# account's own ~/.config/gh/hosts.yml, and those drift per account with
# nothing comparing them -- measured on monkey 2026-08-11, three armed
# accounts gave three different answers.
#
# Hoisted out of bin/scheduler-run (#682): usage-paced-runner.sh's milestone
# gate and bin/tempo.sh read a project's own tracker with ambient `gh` auth
# and hold BLIND on any account that has none, though scheduler-run mints a
# token for that exact repo twenty lines further into the same dispatch.
set -uo pipefail

mint_gh_app_token() {  # <owner/repo to verify against> <log prefix> -- exports GH_TOKEN on success, else leaves the env untouched
  local _gh_own="${1:?mint_gh_app_token needs an owner/repo}" _log="${2:-gh-app-token}"
  local GH_APP_HELPER="${SELFDEV_GH_APP_SH:-$HOME/.local/libexec/selfdev/selfdev-gh-app.sh}"
  local GH_APP_CONF="${SELFDEV_APP_CONF:-$HOME/.config/selfdev/gh-app.conf}"
  [ -z "${GH_TOKEN:-}" ] && [ -f "$GH_APP_CONF" ] && [ -x "$GH_APP_HELPER" ] || return 0
  local _gh_tok
  if _gh_tok="$(SELFDEV_APP_CONF="$GH_APP_CONF" "$GH_APP_HELPER" --token 2>/dev/null)" \
     && [ -n "$_gh_tok" ]; then
    # A MINTED TOKEN IS NOT A USEFUL TOKEN: the first version of this checked
    # only that the helper printed something. Found within an hour of arming
    # (hf7y/realisateur#175) -- the App `unattended-monkey` is installed on
    # the ten product repos and NOT on hf7y/realisateur or hf7y/scheduler, so
    # on those two accounts the mint succeeds and returns a token that 404s
    # on the account's own repo. Probe before exporting; fail open, loudly.
    if GH_TOKEN="$_gh_tok" gh api "repos/$_gh_own" --jq .full_name >/dev/null 2>&1; then
      GH_TOKEN="$_gh_tok"
      export GH_TOKEN
      echo "$_log: minted a GitHub App installation token for $(id -un) (verified against $_gh_own)" >&2
    else
      echo "$_log: WARNING -- minted an App token for $(id -un), but it cannot see $_gh_own, so it was NOT exported. The App installation does not cover that repository; widening it is a browser click (hf7y/realisateur#175). Falling back to this account's stored gh auth, which is what the account was using before." >&2
    fi
  else
    echo "$_log: WARNING -- $GH_APP_CONF exists but '$GH_APP_HELPER --token' produced nothing. Falling back to this account's stored gh auth, which is the credential shape that stranded ecosim's work for two days. Check it before trusting this run's PR steps." >&2
  fi
}
