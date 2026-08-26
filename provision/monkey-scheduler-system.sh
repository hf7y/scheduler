#!/usr/bin/env bash
# monkey-scheduler-system.sh -- install scheduler ONCE per host, system-wide.
#
# ONE COPY PER HOST, owned by root, readable by everyone, writable by nobody
# else -- so "what will this host dispatch" is answerable without reading INTO
# another account's 0700 home, which is what made a read-only monitor need a
# privilege grant.
#
#     /srv/scheduler             root:root 0755, world-readable (a+rX)
#     /etc/scheduler/deploy_key  root:root 0600, the READ-ONLY deploy key
#     /etc/ssh/ssh_known_hosts   github.com, so root can pull unattended
#
# TRAPS (the rest of this header is in vault:scheduler/provisioning-block-headers-20260826.md):
# TRAP: OWNERSHIP IS THE POINT, not the path. When `scheduler` becomes a
#   self-dev user here it must POINT AT /srv/scheduler, never chown it. A
#   shared tool one participant owns is that participant's tool.
# TRAP: needs passwordless sudo on the target (senechal
#   provision/monkey-nopasswd.sh) and a reachable host. Run from mandark.
#
#   ./monkey-scheduler-system.sh --check     probe only; changes nothing
#   ./monkey-scheduler-system.sh --install   idempotent; safe to re-run
#   ./monkey-scheduler-system.sh --sync      fast-forward /srv/scheduler

set -euo pipefail

HOST="${MONKEY_HOST:-monkey}"
PREFIX="${SCHEDULER_PREFIX:-/srv/scheduler}"
KEYDIR="${SCHEDULER_KEYDIR:-/etc/scheduler}"
REPO="${SCHEDULER_REPO:-git@github.com:hf7y/scheduler.git}"
# Where to find a read-only deploy key to SEED the system copy. Read once, at
# install time, and copied to a root-owned path -- after which nothing here
# reads a project user's home again.
SEED_KEY="${SCHEDULER_SEED_KEY:-/home/ecosim/.ssh/deploy_scheduler}"  # hardcoded-home-ok: ecosim is the provisioning seed account by design; SCHEDULER_SEED_KEY overrides

die() { printf 'scheduler-system: %s\n' "$*" >&2; exit 1; }

on_host() {                      # $1 = script text
  local b64; b64="$(printf '%s' "$1" | base64 -w0)"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" \
    "echo $b64 | base64 -d | bash -s"
}

case "${1:---check}" in
--check)
  echo "== system-wide scheduler on $HOST (--check) =="
  on_host '
    printf "  %-8s %s\n" HOST "$(hostname -s)"
    if [ -d '"$PREFIX"'/.git ]; then
      printf "  %-8s %s at %s\n" OK "installed" "'"$PREFIX"'"
      # `git log` as a non-owner trips gits dubious-ownership guard, so this
      # asks via sudo. The guard is correct and is not worth disabling with a
      # global safe.directory just to print a revision.
      printf "  %-8s %s\n" ""   "$(stat -c "%a %U:%G" '"$PREFIX"') $(sudo -n git -C '"$PREFIX"' log --oneline -1 2>/dev/null)"
      # The witness that matters is a read by an UNPRIVILEGED account.
      if [ -r '"$PREFIX"'/schedule ]; then
        printf "  %-8s %s\n" OK "readable by $(id -un) with no sudo"
      else
        printf "  %-8s %s\n" BAD "NOT readable without privilege -- defeats the point"
      fi
    else
      printf "  %-8s %s\n" MISSING "no checkout at '"$PREFIX"'"
    fi
    sudo -n true 2>/dev/null \
      && printf "  %-8s %s\n" OK "passwordless sudo available" \
      || printf "  %-8s %s\n" NEEDS "passwordless sudo (senechal provision/monkey-nopasswd.sh)"
  '
  echo; echo "check only. Nothing changed."
  ;;

--install)
  echo "== system-wide scheduler on $HOST (--install) =="
  on_host '
    set -e
    sudo -n true 2>/dev/null || { echo "REFUSED: needs passwordless sudo" >&2; exit 2; }

    # github.com host key, verified against the PUBLISHED fingerprint rather
    # than trusted blind. Root has no known_hosts of its own by default, and
    # the clone fails with "Host key verification failed" until this exists.
    WANT="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
    GOT="$(ssh-keyscan -t ed25519 github.com 2>/dev/null | ssh-keygen -lf - | awk "{print \$2}")"
    [ "$GOT" = "$WANT" ] || { echo "REFUSED: github.com ed25519 key is $GOT, expected $WANT" >&2; exit 3; }
    if ! sudo -n grep -q "github.com" /etc/ssh/ssh_known_hosts 2>/dev/null; then
      ssh-keyscan -t ed25519,rsa github.com 2>/dev/null | sudo -n tee -a /etc/ssh/ssh_known_hosts >/dev/null
      sudo -n chmod 644 /etc/ssh/ssh_known_hosts
      echo "installed github.com host key (fingerprint verified)"
    fi

    # Seed the ROOT-OWNED key from a project user, once. After this the system
    # copy has its own credential and never reads a project home again.
    if ! sudo -n test -f '"$KEYDIR"'/deploy_key; then
      sudo -n test -f '"$SEED_KEY"' || { echo "REFUSED: no seed key at '"$SEED_KEY"'" >&2; exit 4; }
      sudo -n install -d -m 0700 -o root -g root '"$KEYDIR"'
      sudo -n install -m 0600 -o root -g root '"$SEED_KEY"' '"$KEYDIR"'/deploy_key
      echo "installed root-owned deploy key"
    fi

    if [ -d '"$PREFIX"'/.git ]; then
      echo "already cloned at '"$PREFIX"'"
    else
      sudo -n env GIT_SSH_COMMAND="ssh -i '"$KEYDIR"'/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes" \
        git clone -q '"$REPO"' '"$PREFIX"'
      echo "cloned '"$REPO"'"
    fi
    # Pin the key into the repo so `git -C PREFIX pull` needs no environment.
    sudo -n git -C '"$PREFIX"' config core.sshCommand \
      "ssh -i '"$KEYDIR"'/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes"

    # root owns, everyone reads. a+rX (capital X) sets +x on directories only,
    # never on data files.
    sudo -n chown -R root:root '"$PREFIX"'
    sudo -n chmod -R a+rX '"$PREFIX"'
    echo "HEAD: $(sudo -n git -C '"$PREFIX"' log --oneline -1)"
  '
  echo
  echo "Verify as an UNPRIVILEGED account -- that is the whole point:"
  echo "    ssh $HOST 'head -1 $PREFIX/schedule/_paced.\$(hostname -s).conf'"
  echo
  echo "Machine-wide config on another host. File it:"
  echo "    notify-senechal '$HOST: system-wide scheduler at $PREFIX ...'"
  ;;

--sync)
  # Fast-forward only. A system copy that can silently diverge is a second
  # source of truth, which is the thing this install exists to prevent.
  on_host '
    set -e
    sudo -n git -C '"$PREFIX"' fetch -q origin
    sudo -n git -C '"$PREFIX"' merge --ff-only origin/main
    sudo -n chmod -R a+rX '"$PREFIX"'
    echo "HEAD: $(sudo -n git -C '"$PREFIX"' log --oneline -1)"
  '
  ;;

*) die "usage: monkey-scheduler-system.sh [--check|--install|--sync]" ;;
esac
