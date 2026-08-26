#!/usr/bin/env bash
# wire-selfdev-git.sh -- give a self-dev account the git credentials it needs
# to clone and push ONE repo, and prove they work.
#
# TRAPS (the rest of this header is in the vault):
# NOT THE PUSH PATH ANY MORE (2026-08-21, #171). These keys grant access and
# confer no identity, and their url.insteadOf rewrites silently shadowed the
# App credential helper. Pushes go over https as the App; see
# selfdev-gh-app.sh --wire. This still registers keys for read access.

set -uo pipefail

REPO=""; MODE="--check"; ACCESS="read-only"
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--apply) MODE="$1" ;;
    --rw)            ACCESS="read-write" ;;
    -*)              echo "usage: $0 <repo> [--check|--apply] [--rw]" >&2; exit 2 ;;
    *)               [ -z "$REPO" ] && REPO="$1" || { echo "usage: $0 <repo> [--check|--apply] [--rw]" >&2; exit 2; } ;;
  esac
  shift
done
[ -n "$REPO" ] || { echo "usage: $0 <repo> [--check|--apply] [--rw]" >&2; exit 2; }

OWNER="${SELFDEV_GH_OWNER:-hf7y}"
USER_NAME="$(id -un)"
HOST_NAME="$(hostname -s 2>/dev/null || echo unknown)"
SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/deploy_$REPO"
INC="$SSH_DIR/config.selfdev"
ALIAS="github-$REPO"
# The deploy key title GitHub shows. Host and account are IN the title because
# the next person revoking one needs to know which machine loses access.
TITLE="$HOST_NAME-$USER_NAME-$REPO"

PASS=0; GAPS=0; BAD=0
ok()  { printf '  OK      %s\n' "$*"; PASS=$((PASS+1)); }
gap() { printf '  MISSING %s\n' "$*"; GAPS=$((GAPS+1)); }
bad() { printf '  BAD     %s\n' "$*"; BAD=$((BAD+1)); }
act() { printf '  DO      %s\n' "$*"; }

echo "== wire-selfdev-git $OWNER/$REPO ($MODE, $ACCESS) -- $USER_NAME@$HOST_NAME =="

[ "$(id -u)" -ne 0 ] || { bad "running as root -- these credentials belong to the PROJECT user, and root's copy would be unreadable to it"; exit 5; }

# --- 1. known_hosts ----------------------------------------------------------
# A fresh account has no known_hosts, and an unattended `git clone` against an
# unknown host key does not prompt -- it FAILS. This is the step whose absence
# looks like a broken key.
if [ -f "$SSH_DIR/known_hosts" ] && grep -q '^github.com ' "$SSH_DIR/known_hosts" 2>/dev/null; then
  ok "github.com host key already trusted"
elif [ "$MODE" = --check ]; then
  gap "github.com not in known_hosts -- an unattended clone would fail, not prompt"
else
  act "ssh-keyscan github.com >> known_hosts"
  mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
  if ssh-keyscan -t rsa,ecdsa,ed25519 github.com 2>/dev/null >> "$SSH_DIR/known_hosts"; then
    chmod 600 "$SSH_DIR/known_hosts"; ok "github.com host key pinned"
  else bad "ssh-keyscan github.com failed -- no network, or DNS is lying"; fi
fi

# --- 2. the keypair ----------------------------------------------------------
if [ -f "$KEY" ]; then
  ok "keypair exists: $(basename "$KEY")"
elif [ "$MODE" = --check ]; then
  gap "no keypair for $REPO (would create $KEY)"
else
  act "ssh-keygen ed25519 -> $(basename "$KEY")"
  mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
  if ssh-keygen -q -t ed25519 -N '' -C "$TITLE" -f "$KEY" </dev/null; then
    chmod 600 "$KEY"; chmod 644 "$KEY.pub"; ok "keypair created"
  else bad "ssh-keygen failed for $REPO"; fi
fi

# --- 3. ssh config -----------------------------------------------------------
# Written to a SEPARATE file that ~/.ssh/config Includes, so this script never
# rewrites a config a human may also be editing -- the multi-writer reason
# exists: two writers, one file, is how content gets lost.
if [ -f "$INC" ] && grep -q "^Host $ALIAS\$" "$INC" 2>/dev/null; then
  ok "ssh alias $ALIAS present"
elif [ "$MODE" = --check ]; then
  gap "no ssh alias $ALIAS in $(basename "$INC")"
else
  act "append Host $ALIAS to $(basename "$INC")"
  { [ -f "$INC" ] && echo; cat <<EOF
Host $ALIAS
    HostName github.com
    User git
    IdentityFile $KEY
    IdentitiesOnly yes
EOF
  } >> "$INC" && chmod 600 "$INC" && ok "ssh alias written" || bad "could not write $INC"
fi

# `Include` must be present, and FIRST: ssh takes the first value it sees for
# any keyword, so an Include placed after a matching Host block is silently
# outranked by it.
if [ -f "$SSH_DIR/config" ] && grep -q 'config.selfdev' "$SSH_DIR/config" 2>/dev/null; then
  ok "~/.ssh/config includes config.selfdev"
elif [ "$MODE" = --check ]; then
  gap "~/.ssh/config does not Include config.selfdev -- the aliases would be inert"
else
  act "prepend Include to ~/.ssh/config"
  tmp="$(mktemp)"; printf 'Include ~/.ssh/config.selfdev\n' > "$tmp"
  [ -f "$SSH_DIR/config" ] && cat "$SSH_DIR/config" >> "$tmp"
  mv "$tmp" "$SSH_DIR/config" && chmod 600 "$SSH_DIR/config" && ok "Include prepended" \
    || bad "could not write ~/.ssh/config"
fi

# NO url.insteadOf here any more (#171): it shadowed the App helper, so
# re-adding it would quietly undo the push-path switch.

# --- 5. register the deploy key with GitHub ----------------------------------
# The one step that needs a credential this script cannot mint. If gh is not
# authenticated here, say the exact command and WHERE to run it rather than
# failing with a permission error six lines later.
if [ ! -f "$KEY.pub" ]; then
  [ "$MODE" = --check ] && gap "no public key yet -- registration deferred to --apply"
elif ! gh auth status >/dev/null 2>&1; then
  gap "gh not authenticated as $USER_NAME -- register this key from a host that is:"
  printf '            gh repo deploy-key add - --repo %s/%s --title %s%s <<< "%s"\n' \
    "$OWNER" "$REPO" "$TITLE" "$([ "$ACCESS" = read-write ] && echo ' --allow-write')" "$(cat "$KEY.pub")"
elif gh repo deploy-key list --repo "$OWNER/$REPO" 2>/dev/null | grep -qF "$TITLE"; then
  ok "deploy key '$TITLE' already registered"
elif [ "$MODE" = --check ]; then
  gap "deploy key '$TITLE' not registered on $OWNER/$REPO ($ACCESS)"
else
  act "gh repo deploy-key add ($ACCESS)"
  # rc captured explicitly: `$?` read after an if/else block is the status of
  # whichever branch ran, which is correct and unreadable.
  if [ "$ACCESS" = read-write ]; then
    err="$(gh repo deploy-key add "$KEY.pub" --repo "$OWNER/$REPO" --title "$TITLE" --allow-write 2>&1)"; rc=$?
  else
    err="$(gh repo deploy-key add "$KEY.pub" --repo "$OWNER/$REPO" --title "$TITLE" 2>&1)"; rc=$?
  fi
  if [ "$rc" -eq 0 ]; then ok "deploy key registered ($ACCESS)"
  else bad "gh could not register the key (rc=$rc): ${err:-no output} -- the token may lack repo administration rights"; fi
fi

# --- 6. the witness ----------------------------------------------------------
# Configuration is not capability. Everything above is a file; this is GitHub
# answering. This ecosystem has already lost four days to "a key exists" being
# read as "GitHub accepts it".
if [ "$MODE" = --apply ] || [ -f "$KEY" ]; then
  if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" \
     git ls-remote "$TARGET" HEAD >/dev/null 2>&1; then
    ok "WITNESS: GitHub served $OWNER/$REPO over $ALIAS"
  else
    [ "$MODE" = --check ] && gap "read not proven yet (expected before --apply)" \
                          || bad "WITNESS FAILED: $TARGET did not serve -- the wiring is not live"
  fi
fi

echo
if [ "$MODE" = --check ]; then
  printf 'check only, nothing changed: %d ok, %d missing, %d bad\n' "$PASS" "$GAPS" "$BAD"
  [ "$GAPS" -eq 0 ] && echo "nothing to do." || echo "Next: $0 $REPO --apply$([ "$ACCESS" = read-write ] && echo ' --rw')"
else
  printf 'wired %s/%s: %d ok, %d missing, %d bad\n' "$OWNER" "$REPO" "$PASS" "$GAPS" "$BAD"
fi
[ "$BAD" -eq 0 ] || exit 5
exit 0
