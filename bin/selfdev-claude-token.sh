#!/usr/bin/env bash
# selfdev-claude-token.sh -- install the shared Claude Code OAuth token in ONE
# host-wide place, and purge the per-account copies it replaces (realisateur#409).
#
# usage:
#   selfdev-claude-token.sh --check              report where the token is, and
#                                                every stale copy still on disk
#   selfdev-claude-token.sh --install <file>     write /etc/selfdev/claude-token
#                                                (0640 root:selfdev) from <file>
#   selfdev-claude-token.sh --install <f> --force-length   skip the length check
#   selfdev-claude-token.sh --fanout             LIST the accounts that would
#                                                be rewritten from the one copy
#   selfdev-claude-token.sh --fanout --apply     rewrite them
#   selfdev-claude-token.sh --purge              LIST the copies that would go
#   selfdev-claude-token.sh --purge --apply      shred them
#
# exit: 0 OK  1 BAD (found)  2 usage  4 GAP (to do)  6 BLIND  7 REFUSED
#
# ORDER MATTERS, unenforceable here: rotate, --install, --fanout, prove a
# dispatch, revoke. Purging first deletes copies of a value still live.
#
# --fanout IS TEMPORARY. Nothing reads the host-wide file at dispatch yet, so
# --install alone changes nothing and revoking first takes the fleet down
# silently. --fanout derives the per-account copies from the one file: still N
# copies, one source of truth. Delete it, and --purge the copies, the day
# dispatch reads /etc/selfdev/claude-token.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/selfdev-claude-token.sh
. "$ROOT/lib/selfdev-claude-token.sh"

UID_MIN="${SELFDEV_UID_MIN:-3000}"; UID_MAX="${SELFDEV_UID_MAX:-3099}"
# Overridable so the suite exercises THIS path, not a shape production never writes.
HOME_ROOT="${SELFDEV_HOME_ROOT:-/home}"
PASS=0; GAPS=0; BAD=0; BLIND=0
ok()    { printf '  OK      %s\n' "$*"; PASS=$((PASS+1)); }
gap()   { printf '  GAP     %s\n' "$*"; GAPS=$((GAPS+1)); }
bad()   { printf '  BAD     %s\n' "$*"; BAD=$((BAD+1)); }
blind() { printf '  BLIND   %s\n' "$*"; BLIND=$((BLIND+1)); }
die()   { printf 'selfdev-claude-token: %s\n' "$*" >&2; exit 2; }

# Prints the whole header: a fixed line range starts printing code once edited.
usage() { sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

MODE=""; SRC=""; APPLY=0; FORCE_LEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE=check ;;
    --install) MODE=install; SRC="${2:-}"; [ -n "$SRC" ] || die "--install needs a file"; shift ;;
    --fanout)  MODE=fanout ;;
    --purge)   MODE=purge ;;
    --apply)   APPLY=1 ;;
    --force-length) FORCE_LEN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 -- try --help" ;;
  esac
  shift
done
[ -n "$MODE" ] || { usage; exit 2; }

# selfdev_accounts -- rc 1 on an empty band: a finding, not an emptiness to pass over.
selfdev_accounts() {
  local out
  if [ -n "${SELFDEV_ACCOUNTS:-}" ]; then
    # word-split deliberately: the override is a space-separated list
    # shellcheck disable=SC2086
    out="$(printf '%s\n' $SELFDEV_ACCOUNTS)"
  else
    out="$(getent passwd | awk -F: -v lo="$UID_MIN" -v hi="$UID_MAX" \
      '$3>=lo && $3<=hi {print $1}')"
  fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# stale_copies <account> -- the paths this design replaces. Named, not globbed,
# except .bak-* whose names are timestamps.
stale_copies() {
  local h="$HOME_ROOT/$1" p
  for p in "$h/.claude-token" "$h/.claude/settings.json" "$h"/.claude/settings.json.bak-*; do
    [ -e "$p" ] && printf '%s\n' "$p"
  done
  return 0
}

# strip_token_key -- removes ONLY the token key. The file is not ours to delete:
# it holds hooks, permissions and model config the account needs.
strip_token_key() {
  python3 - "$1" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d.get("env", {}).pop("CLAUDE_CODE_OAUTH_TOKEN", None)
if d.get("env") == {}: d.pop("env")
p.write_text(json.dumps(d, indent=2) + "\n"); p.chmod(0o600)
PY
}

# SETTER_PY -- materialised once, run as each account. A file, not an inline
# heredoc through `sudo bash -c`: that nesting is where the quoting breaks.
# Takes the value from a FILE, never argv, which is readable in ps.
SETTER_PY=""
make_setter() {
  SETTER_PY="$(mktemp)"; chmod 644 "$SETTER_PY"
  cat > "$SETTER_PY" <<'PY'
import json, pathlib, sys
p, tokf = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
tok = tokf.read_text().strip()
d = json.loads(p.read_text()) if p.exists() and p.stat().st_size else {}
d.setdefault("env", {})["CLAUDE_CODE_OAUTH_TOKEN"] = tok
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(d, indent=2) + "\n")
p.chmod(0o600)
PY
  trap 'rm -f "$SETTER_PY"' EXIT
}

TOKPATH="$(selfdev_token_path)"

case "$MODE" in
install)
  [ -r "$SRC" ] || die "cannot read $SRC"
  # ALL whitespace, not just \r\n: a pasted token carries a stray space, and
  # on 2026-08-19 that reached 15 accounts as a 401 (#409).
  tok="$(tr -d '[:space:]' < "$SRC")"
  case "$tok" in sk-ant-oat*) ;; *) die "$SRC does not hold an sk-ant-oat* token -- refusing to install it" ;; esac

  # A prefix is not a shape; the replaced value is the only known-good example.
  if [ -e "$TOKPATH" ] && selfdev_token_readable "$TOKPATH"; then
    cur_len="$(tr -d '[:space:]' < "$TOKPATH" | wc -c)"
    new_len="${#tok}"
    if [ "$cur_len" -ne "$new_len" ] && [ "$FORCE_LEN" -eq 0 ]; then
      printf 'selfdev-claude-token: REFUSING -- the new value is %d characters, the one it replaces is %d.\n' "$new_len" "$cur_len" >&2
      printf '  A token that is the wrong length is a bad paste, and --fanout would carry it to every account.\n' >&2
      printf '  Re-copy it, or pass --force-length if the token format genuinely changed.\n' >&2
      exit 7
    fi
    ok "length matches the value being replaced ($new_len characters)"
  else
    gap "no existing value to compare length against -- installing $new_len characters unchecked"
  fi
  getent group "$SELFDEV_TOKEN_GROUP" >/dev/null || die "no group $SELFDEV_TOKEN_GROUP on this host"
  install -d -m 755 -o root -g root "$SELFDEV_TOKEN_DIR" || die "cannot create $SELFDEV_TOKEN_DIR (run as root)"
  # Via a mode-600 temp file: argv is readable in ps by any local user.
  tmp="$(mktemp)"; chmod 600 "$tmp"; printf '%s\n' "$tok" > "$tmp"
  install -m 640 -o root -g "$SELFDEV_TOKEN_GROUP" "$tmp" "$TOKPATH" || { rm -f "$tmp"; die "install to $TOKPATH failed"; }
  shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
  ok "wrote $TOKPATH (0640 root:$SELFDEV_TOKEN_GROUP)"
  echo
  echo "Next: prove one dispatch reads it before purging anything."
  exit 0
  ;;

check)
  echo "== selfdev-claude-token --check on $(hostname -s) =="
  echo
  echo "-- the one copy --"
  if [ -e "$TOKPATH" ]; then
    perm="$(stat -c '%a %U:%G' "$TOKPATH" 2>/dev/null || echo '?')"
    if [ "$perm" = "640 root:$SELFDEV_TOKEN_GROUP" ]; then
      ok "$TOKPATH ($perm)"
    else
      bad "$TOKPATH is $perm, want 640 root:$SELFDEV_TOKEN_GROUP"
    fi
    if selfdev_token_readable "$TOKPATH"; then
      ok "readable by this process ($(id -un))"
    else
      blind "present but NOT readable by $(id -un) -- cannot verify its contents"
    fi
  else
    gap "$TOKPATH does not exist -- the host-wide copy has not been installed"
  fi
  echo
  echo "-- the copies it replaces --"
  if ! accts="$(selfdev_accounts)"; then
    blind "no account in uid band $UID_MIN-$UID_MAX on this host -- nothing to survey, which on a self-dev host is itself a finding"
  else
    n=0
    while read -r a; do
      [ -n "$a" ] || continue
      # ABSENT is a fact; UNREADABLE is a domain we did not read. Only the
      # second is BLIND, and folding it into "clean" is reporting clean by
      # not looking.
      if [ ! -e "$HOME_ROOT/$a" ]; then
        ok "$a has no home under $HOME_ROOT -- no copy to hold"
        continue
      fi
      if ! [ -x "$HOME_ROOT/$a" ]; then
        blind "$HOME_ROOT/$a not traversable by $(id -un) -- cannot say whether it holds a copy"
        continue
      fi
      while read -r p; do
        [ -n "$p" ] || continue
        n=$((n+1)); gap "stale copy: $p"
      done <<<"$(stale_copies "$a")"
    done <<<"$accts"
    [ "$n" -eq 0 ] && [ "$BLIND" -eq 0 ] && ok "no per-account copy found"
  fi
  echo
  echo "ORDER: rotate -> --install -> prove a dispatch -> --purge. Purging an"
  echo "unrotated token deletes copies of a value that is still live."
  ;;

fanout)
  [ "$APPLY" -eq 1 ] || echo "== DRY RUN (no --apply): listing only =="
  if [ ! -e "$TOKPATH" ]; then
    bad "nothing to fan out: $TOKPATH does not exist -- run --install first"
    printf '\n== %d BAD ==\n' "$BAD"; exit 1
  fi
  if ! selfdev_token_readable "$TOKPATH"; then
    blind "cannot read $TOKPATH as $(id -un) -- refusing to fan out a value I cannot verify"
    printf '\n== %d BLIND ==\n' "$BLIND"; exit 6
  fi
  if ! accts="$(selfdev_accounts)"; then
    blind "no account in uid band $UID_MIN-$UID_MAX -- nothing enumerated, which is not the same as nothing present"
    printf '\n== %d BLIND ==\n' "$BLIND"; exit 6
  fi
  [ "$APPLY" -eq 1 ] && make_setter
  while read -r a; do
    [ -n "$a" ] || continue
    h="$HOME_ROOT/$a"
    [ -d "$h" ] || { ok "$a has no home under $HOME_ROOT -- skipped"; continue; }
    if [ "$APPLY" -ne 1 ]; then
      gap "would rewrite $h/.claude/settings.json and $h/.claude-token from $TOKPATH"
      continue
    fi
    # Written AS the account, so ownership and mode stay the account's own and
    # no root-owned file is left in a home that must remain self-managed.
    if install -m 600 -o "$a" -g "$a" "$TOKPATH" "$h/.claude-token" \
       && sudo -n -u "$a" python3 "$SETTER_PY" "$h/.claude/settings.json" "$h/.claude-token"; then
      ok "$a rewritten from the one copy"
    else
      bad "$a could not be rewritten -- it is now UNKNOWN whether it holds the old or the new value, so re-run --fanout before trusting the fleet"
    fi
  done <<<"$accts"
  echo
  [ "$APPLY" -eq 1 ] && echo "Re-run bin/tests/../fleet fingerprints, or --check, to witness the change." \
                     || echo "Re-run with --apply to act."
  ;;

purge)
  [ "$APPLY" -eq 1 ] || echo "== DRY RUN (no --apply): listing only =="
  if [ ! -e "$TOKPATH" ]; then
    bad "refusing to purge: $TOKPATH does not exist, so purging would leave NO copy of the token anywhere and every account would dispatch and produce nothing, silently"
    printf '\n== %d BAD ==\n' "$BAD"; exit 1
  fi
  selfdev_token_readable "$TOKPATH" || { blind "cannot read $TOKPATH as $(id -un) -- refusing to purge against a replacement I cannot verify"; printf '\n== %d BLIND ==\n' "$BLIND"; exit 6; }
  if ! accts="$(selfdev_accounts)"; then
    blind "no account in uid band $UID_MIN-$UID_MAX -- nothing enumerated, which is not the same as nothing present"
    printf '\n== %d BLIND ==\n' "$BLIND"; exit 6
  fi
  while read -r a; do
    [ -n "$a" ] || continue
    while read -r p; do
      [ -n "$p" ] || continue
      case "$p" in
        */.claude/settings.json)
          if grep -q CLAUDE_CODE_OAUTH_TOKEN "$p" 2>/dev/null; then
            if [ "$APPLY" -eq 1 ]; then
              if strip_token_key "$p"; then
                ok "stripped CLAUDE_CODE_OAUTH_TOKEN from $p"
              else
                bad "could not strip $p"
              fi
            else
              gap "would strip CLAUDE_CODE_OAUTH_TOKEN from $p"
            fi
          fi
          ;;
        *)
          if [ "$APPLY" -eq 1 ]; then
            shred -u "$p" 2>/dev/null || rm -f "$p"
            if [ -e "$p" ]; then bad "could not remove $p"; else ok "shredded $p"; fi
          else
            gap "would shred $p"
          fi
          ;;
      esac
    done <<<"$(stale_copies "$a")"
  done <<<"$accts"
  echo
  [ "$APPLY" -eq 1 ] || echo "Re-run with --apply to act. Session transcripts under"
  [ "$APPLY" -eq 1 ] || echo "\$HOME/.claude/projects/**.jsonl are NOT touched here -- see #409; they need"
  [ "$APPLY" -eq 1 ] || echo "a decision about the transcript archive, not a blind delete."
  ;;
esac

printf '\n== %d OK, %d GAP, %d BAD, %d BLIND ==\n' "$PASS" "$GAPS" "$BAD" "$BLIND"
[ "$BAD"   -gt 0 ] && exit 1
[ "$BLIND" -gt 0 ] && exit 6
[ "$GAPS"  -gt 0 ] && exit 4
exit 0
