#!/usr/bin/env bash
set -uo pipefail

CLI_NAME='vault-group-provision.sh'
CLI_SUMMARY='own the vault group, the 2775 setgid bit on the vault dir, and every self-dev account'"'"'s membership -- the arrangement bin/consigne'"'"'s deposit lock depends on (#597), made by hand on monkey and owned by nothing in this repo until now'
CLI_USAGE='  vault-group-provision.sh            --check (default): report, write nothing
  vault-group-provision.sh --apply    create/fix the group, the dir mode, and membership
  (idempotent -- an --apply on a host already at the target changes nothing and says so)'
CLI_FLAGS='--check --apply --group --dir'
CLI_POSITIONAL=any
CLI_EXITS='  0  the host is at the target (or --check found it so)
  1  findings: something is missing or wrong -- read the rows
  5  refused: --apply without root
  6  BLIND: the roster matched no account at all -- nothing was checked, and
     a 0-account pass is NOT a clean result'
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib/cli-guard.sh"
cli_guard "$@"

MODE=--check
GROUP="${VAULT_GROUP:-vault}"
DIR="${VAULT_DIR:-/srv/ecosystem1-vault}"
HOME_ROOT="${HOME_ROOT:-/home}"
SUDO="${SUDO-sudo}"
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--apply) MODE="$1" ;;
    --group) shift; GROUP="${1:-}" ;;
    --dir)   shift; DIR="${1:-}" ;;
    *) cli_die "unexpected argument: $1" ;;
  esac
  shift
done

PASS=0; GAPS=0; BAD=0
ok()  { printf '  OK      %s\n' "$*"; PASS=$((PASS+1)); }
gap() { printf '  MISSING %s\n' "$*"; GAPS=$((GAPS+1)); }
bad() { printf '  BAD     %s\n' "$*"; BAD=$((BAD+1)); }
act() { printf '  DO      %s\n' "$*"; }
die() { printf '\n%s: %s\n' "$CLI_NAME" "$*" >&2; exit "${2:-5}"; }

echo "== vault-group-provision ($MODE) -- $(hostname -s), group $GROUP, dir $DIR =="

[ "$MODE" = --check ] || [ "$(id -u)" -eq 0 ] || die "$MODE needs root (sudo $CLI_NAME $MODE)" 5

accounts() {  # same roster selfdev-permissions-provision.sh derives -- every HOME_ROOT/* with a .claude dir, not a typed list
  local d u
  for d in "$HOME_ROOT"/*/; do
    u="$(basename "$d")"
    [ "$u" = "zach" ] && continue
    $SUDO test -d "$d/.claude" 2>/dev/null || continue
    printf '%s\n' "$u"
  done
}

if [ "$MODE" = --apply ] && ! getent group "$GROUP" >/dev/null 2>&1; then
  groupadd "$GROUP" && act "created group $GROUP"
fi
if getent group "$GROUP" >/dev/null 2>&1; then
  ok "group $GROUP exists ($(getent group "$GROUP" | cut -d: -f4))"
else
  gap "group $GROUP does not exist"
fi

if [ ! -d "$DIR" ]; then
  if [ "$MODE" = --apply ]; then
    install -d -m 2775 -o root -g "$GROUP" "$DIR" && act "created $DIR (2775 root:$GROUP)"
  else
    gap "$DIR does not exist"
  fi
fi
if [ -d "$DIR" ]; then
  m="$(stat -c '%a %G' "$DIR" 2>/dev/null)"
  if [ "$m" = "2775 $GROUP" ]; then
    ok "$DIR is $m"
  elif [ "$MODE" = --apply ]; then
    chgrp "$GROUP" "$DIR" && chmod 2775 "$DIR" && act "$DIR was '$m' -- set to 2775 $GROUP"
  else
    bad "$DIR is '$m', expected '2775 $GROUP'"
  fi
fi

roster="$(accounts)"
if [ -z "$roster" ]; then
  echo "BLIND: no self-dev account found under $HOME_ROOT -- nothing was checked." >&2
  echo "$CLI_NAME: nothing was measured. This is NOT a clean result." >&2
  exit 6
fi
missing=""
for a in $roster; do
  ingrp=no; id -nG "$a" 2>/dev/null | tr ' ' '\n' | grep -qx "$GROUP" && ingrp=yes
  if [ "$ingrp" = no ] && [ "$MODE" = --apply ]; then
    usermod -aG "$GROUP" "$a" && { act "$a added to group $GROUP"; ingrp=yes; }
  fi
  printf '  ..      %-16s group=%s\n' "$a" "$ingrp"
  [ "$ingrp" = yes ] || missing="$missing $a"
done
[ -z "$missing" ] && ok "every self-dev account is in group $GROUP" \
                  || gap "not in group $GROUP:$missing"

echo
printf '%s (%s): %d ok, %d missing, %d bad\n' "$CLI_NAME" "$MODE" "$PASS" "$GAPS" "$BAD"
if [ "$MODE" = --check ]; then
  [ "$GAPS" -eq 0 ] && [ "$BAD" -eq 0 ] && exit 0
  echo "Next: sudo $CLI_NAME --apply"
  exit 1
fi
[ "$GAPS" -eq 0 ] && [ "$BAD" -eq 0 ] && exit 0
exit 1
