#!/usr/bin/env bash
# provision-selfdev-user.sh -- add a self-dev project account to this host.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/lib/selfdev-claude-token.sh"

PROJECT="${1:-}"
MODE="${2:---check}"
case "$PROJECT" in ""|-*) echo "usage: $0 <project> [--check|--apply]" >&2; exit 2 ;; esac
case "$MODE" in --check|--apply) ;; *) echo "usage: $0 <project> [--check|--apply]" >&2; exit 2 ;; esac

# The uid band vault:realisateur/MONKEY.md reserves for self-dev projects: clear of the human
# 1000s and of the office's romulus=1001, so a future merge of conventions
# cannot collide.
UID_MIN="${SELFDEV_UID_MIN:-3000}"
UID_MAX="${SELFDEV_UID_MAX:-3099}"
CRED_HOME="$HOME"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  CRED_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  [ -n "$CRED_HOME" ] || CRED_HOME="$HOME"
fi
# Read FROM the HOST-WIDE copy first, a human's home only as fallback:
# ~zach/.claude-token on monkey was stale, and a stale token installs CLEAN --
# mode 600, every --check row OK, dispatching into nothing (realisateur#624).
# The env overrides still win, and the row below names the file that was read.
SRC_HOST="$(selfdev_token_path)"
SRC_SETTINGS="${SELFDEV_TOKEN_SRC:-$CRED_HOME/.claude/settings.json}"
SRC_TOKEN_FILE="$CRED_HOME/.claude-token"

PASS=0; GAPS=0; BAD=0
ok()  { printf '  OK      %s\n' "$*"; PASS=$((PASS+1)); }
gap() { printf '  MISSING %s\n' "$*"; GAPS=$((GAPS+1)); }
bad() { printf '  BAD     %s\n' "$*"; BAD=$((BAD+1)); }
act() { printf '  DO      %s\n' "$*"; }
die() { printf 'provision-selfdev-user: FATAL %s\n' "$*" >&2; exit 1; }

HOME_DIR="/home/$PROJECT"
echo "== provision-selfdev-user $PROJECT ($MODE) on $(hostname -s) =="

# --- where does the token come from ------------------------------------------
# Read it now, in --check too, because "there is a credential to copy" is the
# single fact this script exists to act on. Never printed.
TOKEN=""
settings_token() {  # the env-block token in a settings.json, or nothing
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("env",{}).get("CLAUDE_CODE_OAUTH_TOKEN",""))' "$1" 2>/dev/null || true
}
SOURCES=()   # an explicit SELFDEV_TOKEN_SRC outranks the host-wide copy
[ -n "${SELFDEV_TOKEN_SRC:-}" ] && SOURCES+=("settings:$SRC_SETTINGS")
SOURCES+=("file:$SRC_HOST" "settings:$SRC_SETTINGS" "file:$SRC_TOKEN_FILE")
for src in "${SOURCES[@]}"; do
  [ -n "$TOKEN" ] && break
  p="${src#*:}"
  case "$src" in
    settings:*) [ -f "$p" ] || continue
                TOKEN="$(settings_token "$p")"
                [ -n "$TOKEN" ] && ok "source credential: $p (env block)" ;;
    file:*)     selfdev_token_readable "$p" || continue
                TOKEN="$(tr -d '\r\n' < "$p")"
                [ -n "$TOKEN" ] && ok "source credential: $p" ;;
  esac
done
[ -n "$TOKEN" ] || bad "no credential to copy -- looked in $SRC_HOST, $SRC_SETTINGS (env block) and $SRC_TOKEN_FILE. Run \`selfdev-claude-token.sh --install\` (or \`claude setup-token\`) first; a project account with no token dispatches and produces NOTHING, silently."

# --- account -----------------------------------------------------------------
if id "$PROJECT" >/dev/null 2>&1; then
  cur_uid="$(id -u "$PROJECT")"
  if [ "$cur_uid" -ge "$UID_MIN" ] && [ "$cur_uid" -le "$UID_MAX" ]; then
    ok "account $PROJECT exists, uid $cur_uid (in the self-dev band)"
  else
    bad "account $PROJECT exists at uid $cur_uid, OUTSIDE the self-dev band $UID_MIN-$UID_MAX -- refusing to adopt an account this script did not create"
  fi
else
  # Lowest free uid in the band, so accounts are dense and predictable.
  NEXT=""
  for u in $(seq "$UID_MIN" "$UID_MAX"); do
    id -u "$u" >/dev/null 2>&1 || { NEXT="$u"; break; }
  done
  [ -n "$NEXT" ] || bad "no free uid in $UID_MIN-$UID_MAX"
  gap "account $PROJECT does not exist (would create at uid ${NEXT:-?})"
fi

if [ "$(id -u)" -eq 0 ]; then
  ok "running as root"
elif sudo -n true >/dev/null 2>&1; then
  ok "passwordless sudo available"
else
  gap "sudo will prompt and there may be no tty -- invoke as: sudo $0 $PROJECT --apply"
fi

if [ "$MODE" = --check ]; then
  echo
  printf 'check only, nothing changed: %d ok, %d missing, %d bad\n' "$PASS" "$GAPS" "$BAD"
  [ "$BAD" -eq 0 ] || { echo "resolve the BAD rows before --apply."; exit 5; }
  echo "Next: $0 $PROJECT --apply"
  exit 0
fi

[ "$BAD" -eq 0 ] || die "refusing to apply with $BAD BAD row(s) above"

# --- apply -------------------------------------------------------------------
if ! id "$PROJECT" >/dev/null 2>&1; then
  NEXT=""
  for u in $(seq "$UID_MIN" "$UID_MAX"); do id -u "$u" >/dev/null 2>&1 || { NEXT="$u"; break; }; done
  [ -n "$NEXT" ] || die "no free uid in $UID_MIN-$UID_MAX"
  act "useradd $PROJECT uid=$NEXT"
  sudo useradd -u "$NEXT" -m -s /bin/bash "$PROJECT" || die "useradd failed"
fi

# 0700: repos and working state are isolated per project. SPEND is not, and
# cannot be, because the credential is shared -- said out loud here because a
# reader could otherwise mistake this mode for budget isolation.
act "home 0700, and the WHOLE tree owned by $PROJECT"
sudo chmod 700 "$HOME_DIR"
# chown -R, not `install -d -o`: install chowns only the final component, which
# is exactly how /home/ecosim/.local ended up root-owned and broke the first
# dispatch. This is the bug this script exists to stop repeating.
sudo chown -R "$PROJECT:$PROJECT" "$HOME_DIR"

# Ubuntu's ~/.profile only prepends ~/.local/bin if it EXISTS AT LOGIN. Created
# later, it is not on PATH until the next login -- a shim installed correctly
# that still cannot be found.
act "~/.local/bin, before the account's first login"
sudo -u "$PROJECT" mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.local/share" "$HOME_DIR/.claude"
sudo -u "$PROJECT" chmod 700 "$HOME_DIR/.claude"

# PER-TENANT TMPDIR AND A PRIVATE UMASK (#620). Thirteen accounts share one
# /tmp. On 2026-08-25 gardien's `git commit -F /tmp/commit-msg.txt` silently
# read ecosim's leftover file of the same name and committed another project's
# prose, under the wrong author, with no error anywhere -- caught only by a
# habit of reading `git log -1` back. Two independent holes: a predictable
# name space shared across tenants, and a default umask that leaves scratch
# files world-readable. Both close in ~/.profile, which is read by the login
# shell cron and ssh both start from.
act "private TMPDIR and umask 077 in ~/.profile"
sudo -u "$PROJECT" mkdir -p "$HOME_DIR/tmp"
sudo -u "$PROJECT" chmod 700 "$HOME_DIR/tmp"
if sudo -u "$PROJECT" grep -q '^# selfdev: private scratch' "$HOME_DIR/.profile" 2>/dev/null; then
  act "  already present, left alone"
else
  sudo -u "$PROJECT" tee -a "$HOME_DIR/.profile" >/dev/null <<'PROFILE'

# selfdev: private scratch (realisateur#620) -- a shared /tmp let one tenant's
# stale file satisfy another tenant's read. Do not point these at /tmp.
export TMPDIR="$HOME/tmp"
umask 077
PROFILE
fi

act "linger (a --user unit outlives logout; cheap now, needs root later)"
sudo loginctl enable-linger "$PROJECT" >/dev/null 2>&1 || gap "enable-linger failed"

# No sudoers file. Stated as an action so its ABSENCE is visible in the log.
act "no sudoers entry for $PROJECT (deliberate)"
sudo rm -f "/etc/sudoers.d/90-$PROJECT"

# --- the credential ----------------------------------------------------------
# Written as the project user, via a mode-600 temp file, so the token never
# appears in argv (visible in ps to any local user) and never transits a
# world-readable path.
act "copy the shared credential into $PROJECT's settings.json"
TMP="$(mktemp)"; chmod 600 "$TMP"
printf '%s' "$TOKEN" > "$TMP"
sudo install -m 600 -o "$PROJECT" -g "$PROJECT" "$TMP" "$HOME_DIR/.claude-token"
shred -u "$TMP" 2>/dev/null || rm -f "$TMP"
sudo -u "$PROJECT" python3 - "$HOME_DIR" <<'PY'
import json, pathlib, sys
home = pathlib.Path(sys.argv[1])
tok = (home / ".claude-token").read_text().strip()
p = home / ".claude" / "settings.json"
d = json.loads(p.read_text()) if p.exists() else {}
d.setdefault("env", {})["CLAUDE_CODE_OAUTH_TOKEN"] = tok
p.write_text(json.dumps(d, indent=2) + "\n")
p.chmod(0o600)
PY

# --- the OTHER credential ------------------------------------------------------
# gh, on the same argument as the claude token above.
GH_SRC="${SELFDEV_GH_HOSTS:-$CRED_HOME/.config/gh/hosts.yml}"
if [ -r "$GH_SRC" ]; then
  # No `MODE` guard here: --check has already exited above. Everything from
  # this point down runs only under --apply.
  act "copy the shared gh credential into $PROJECT's hosts.yml"
  sudo install -d -m 700 -o "$PROJECT" -g "$PROJECT" "$HOME_DIR/.config" "$HOME_DIR/.config/gh"
  sudo install -m 600 -o "$PROJECT" -g "$PROJECT" "$GH_SRC" "$HOME_DIR/.config/gh/hosts.yml"
  # The witness is gh answering, not the file existing -- `gh auth status`
  # actually calls GitHub, which is the same distinction the claude witness
  # below draws between configuration and capability.
  if sudo -u "$PROJECT" -H env -i HOME="$HOME_DIR" PATH=/usr/local/bin:/usr/bin:/bin \
       gh auth status >/dev/null 2>&1; then
    ok "$PROJECT can reach GitHub as an authenticated user"
  else
    bad "$PROJECT's gh copy does not authenticate -- deploy keys cannot be registered and issue queues cannot be worked"
  fi
else
  gap "no gh credential at $GH_SRC -- $PROJECT will not be able to register deploy keys or work an issue queue. Run \`gh auth login\` as ${SUDO_USER:-$(id -un)} first."
fi

# --- witness -----------------------------------------------------------------
# Configuration is not capability. The only proof is a call, and it is made
# under a STRIPPED environment because that is how cron will make it.
echo
act "witness: a real call, as $PROJECT, with nothing inherited"
if sudo -u "$PROJECT" -H env -i HOME="$HOME_DIR" PATH=/usr/local/bin:/usr/bin:/bin \
     claude -p 'reply with the single word ok' </dev/null 2>&1 | grep -qi '^ok'; then
  ok "$PROJECT can spend a token under a cron-shaped environment"
else
  bad "$PROJECT could NOT spend a token -- the account exists but dispatch would produce nothing"
fi

echo
printf 'provisioned %s: %d ok, %d missing, %d bad\n' "$PROJECT" "$PASS" "$GAPS" "$BAD"
cat <<EOF

NOT LANDED AND NOT ARMED, deliberately. Next, as $PROJECT:
    bin/land-selfdev.sh --check      # then --land
and only then a reviewed change to schedule/_paced.$(hostname -s).conf.
Adding a participant is a judgment, not a side effect of creating an account.
EOF
[ "$BAD" -eq 0 ]
