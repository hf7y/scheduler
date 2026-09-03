#!/usr/bin/env bash
# land-selfdev.sh -- stand the self-dev ecosystem up on a host that has nothing.
# RUN THIS ON THE TARGET HOST, as the project user. Deliberately not a
# curl-pipe-bash one-liner: getting it onto the machine is a human act, and it
# is the last one that should be invisible.
#
#   ./land-selfdev.sh          --check (default): probes, writes NOTHING
#   ./land-selfdev.sh --land   clone, install, stop before arming cron
# TRAPS (the rest of this header is in
# vault:scheduler/provisioning-block-headers-20260826.md):
# TRAP: it NEVER writes a crontab. dose-project.sh runs in --check (preview)
#   and the --apply is PRINTED for a human. Arming dispatch is the one step
#   that spends a shared quota, and every guard here stops short of it.
# TRAP: ancestry is vkv/office/provision/land-office.sh -- same OK/MISSING/DO
#   vocabulary, same idempotence, same refusal to arm without a flag.

set -uo pipefail

MODE="${1:---check}"
case "$MODE" in --check|--land) ;; *) echo "usage: $0 [--check|--land]" >&2; exit 2 ;; esac

# One name for "where projects live", shared with install-verbs.sh, verb-set.sh
# and installe -- four tools that must not be able to disagree about this.
PROJECTS="${INSTALLE_PROJECTS:-$HOME/Documents/Projects}"
GH_OWNER="${SELFDEV_GH_OWNER:-hf7y}"

# NOT collapsed into lib/provision-witness.sh (#517): this script is staged
# and run as a lone file with no lib/ sibling -- setup-selfdev-project.sh
# `install`s it alone into $STAGE, and tests/land-selfdev-deployment-guard-
# witness.sh proves --land works from a `cp`-of-one. A lib/ dependency here
# breaks silently on both paths (bash -u treats the missing helpers as
# unbound vars mid-run, past the point of a clean early exit).
PASS=0; GAPS=0; BAD=0
ok()  { printf '  OK      %s\n' "$*"; PASS=$((PASS+1)); }
gap() { printf '  MISSING %s\n' "$*"; GAPS=$((GAPS+1)); }
bad() { printf '  BAD     %s\n' "$*"; BAD=$((BAD+1)); }
act() { printf '  DO      %s\n' "$*"; }

echo "== land-selfdev ($MODE) -- host $(hostname -s), user $(id -un) =="

for c in git python3 node claude; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c on PATH ($(command -v "$c"))"
  else gap "$c is not on PATH"; fi
done

# TRAP: ~/.local/bin must EXIST at login or Ubuntu ~/.profile does not add it -- a correctly-installed verb that cannot be found.
if [ -d "$HOME/.local/bin" ]; then ok "~/.local/bin exists"
else gap "~/.local/bin does not exist -- create it BEFORE the next login or .profile will not add it to PATH"; fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ok "~/.local/bin is on PATH" ;;
                  *) gap "~/.local/bin is not on this shell's PATH" ;; esac

if systemctl --user show-environment >/dev/null 2>&1; then ok "systemd --user is running"
else gap "systemd --user is not available to this session"; fi

# Linger is not needed for cron; it is what lets a --user unit survive logout later. Cheap now, needs root later.
linger="$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)"
case "$linger" in yes) ok "linger enabled" ;; *) gap "linger is not enabled (needs root: loginctl enable-linger $(id -un))" ;; esac

# TRAP: THE ONE THAT SILENTLY DISPATCHES THE WRONG ROTATION. scheduler falls back from _paced.$(hostname -s).conf to the SHARED _paced.conf; on a new host that is not a default, it is another machine's rotation. What matters is WHAT would be inherited -- mandark reads the shared one deliberately.
HOST="$(hostname -s)"
SHARED_PACED="$PROJECTS/scheduler/schedule/_paced.conf"
if [ -f "$PROJECTS/scheduler/schedule/_paced.$HOST.conf" ]; then
  ok "schedule/_paced.$HOST.conf exists -- this host has its own rotation"
elif [ -d "$PROJECTS/scheduler" ]; then
  enabled=$(grep -cE '^[a-z][^|]*\|1\|' "$SHARED_PACED" 2>/dev/null || echo 0)
  if [ "${enabled:-0}" -gt 0 ]; then
    bad "no schedule/_paced.$HOST.conf, and the shared _paced.conf has $enabled ENABLED row(s) -- this host would silently dispatch another machine's rotation"
  else
    gap "no schedule/_paced.$HOST.conf; this host falls back to the shared _paced.conf, which currently has 0 enabled rows (inert, but give this host its own file before arming anything)"
  fi
else
  gap "scheduler not cloned yet; cannot check for _paced.$HOST.conf"
fi

CRED="$HOME/.claude/.credentials.json"
SETTINGS="$HOME/.claude/settings.json"
auth=""
if [ -f "$CRED" ]; then auth="$CRED"
elif [ -f "$SETTINGS" ] && grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$SETTINGS" 2>/dev/null; then auth="$SETTINGS"
fi
if [ -n "$auth" ]; then
  m="$(stat -c%a "$auth" 2>/dev/null || echo '?')"
  [ "$m" = "600" ] && ok "claude auth configured in $(basename "$auth"), mode 600" \
                   || bad "$auth is mode $m, expected 600 -- a readable token is a finding"
elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  gap "auth is only in this shell's environment -- cron will not have it; run \`claude setup-token\` and put it in $SETTINGS"
else
  gap "no claude auth for $(id -un) -- dispatch would run and produce NOTHING, silently"
fi
# Configuration is not capability. The only real proof is a call, and it costs
# a token, so it is not run here -- but say so, rather than letting "ok" above
# read as more than it is.
[ -n "$auth" ] && printf '  ..      the witness is a live call, not this file: claude -p "reply ok"\n'

# Read AND write: a key existing is not GitHub accepting it -- four days lost to that distinction.
if git ls-remote "https://github.com/$GH_OWNER/realisateur.git" HEAD >/dev/null 2>&1; then
  ok "GitHub read path works"
else gap "cannot read https://github.com/$GH_OWNER/realisateur.git"; fi
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  ok "gh is authenticated (file-based token survives cron with no session bus)"
else gap "gh is not authenticated -- the WRITE path is unproven, and a read probe does not establish it"; fi

avail="$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9' || true)"
[ -n "$avail" ] && { [ "$avail" -ge 10 ] && ok "${avail}G free on \$HOME" || gap "only ${avail}G free on \$HOME"; }

if [ "$MODE" = --check ]; then
  echo
  printf 'check only, nothing changed: %d ok, %d missing, %d bad\n' "$PASS" "$GAPS" "$BAD"
  [ "$BAD" -eq 0 ] || { echo "resolve the BAD rows before --land."; exit 5; }
  echo "Next: $0 --land"
  exit 0
fi

[ "$BAD" -eq 0 ] || { echo; echo "land-selfdev: refusing to land with $BAD BAD row(s) above." >&2; exit 5; }
echo
echo "== landing =="
mkdir -p "$PROJECTS"

# Credentials come BEFORE the clone that needs them, per repo.
WIRE="$(dirname "$0")/wire-selfdev-git.sh"

wire_repo() {
  local name="$1" access=""
  [ -x "$WIRE" ] || { gap "$name: wire-selfdev-git.sh not found beside $(basename "$0") -- clone will use whatever credential happens to exist"; return 0; }
  [ "$name" = "$(id -un)" ] && access="--rw"
  # NOT piped into sed: a pipeline's status is the LAST command's, so `| sed`
  # would swallow every failure this script exists to surface.
  local out rc
  out="$("$WIRE" "$name" --apply $access 2>&1)"; rc=$?
  printf '%s\n' "$out" | sed 's/^/    /'
  [ "$rc" -eq 0 ] || bad "$name: git credentials could not be wired (rc=$rc)"
}

clone_or_update() {
  local name="$1" url="$2" dir="$PROJECTS/$1"
  case "$url" in *"github.com/$GH_OWNER/"*|*"github.com:$GH_OWNER/"*) wire_repo "$name" ;; esac
  if [ -d "$dir/.git" ]; then
    act "$name: fast-forward only"
    git -C "$dir" fetch -q origin && git -C "$dir" pull -q --ff-only || \
      { bad "$name: could not fast-forward (diverged or dirty) -- left untouched"; return 1; }
    ok "$name at $(git -C "$dir" rev-parse --short HEAD)"
  else
    act "$name: clone $url"
    git clone -q "$url" "$dir" || { bad "$name: clone failed"; return 1; }
    ok "$name cloned at $(git -C "$dir" rev-parse --short HEAD)"
  fi
  guard_foreign_clone "$name" "$dir"
}

guard_foreign_clone() {
  local name="$1" dir="$2" hook="$2/.git/hooks/pre-commit"
  [ "$name" = "$(id -un)" ] && { rm -f "$hook"; return 0; }
  cat > "$hook" <<'HOOK'
#!/bin/sh
echo "REFUSED: this is a deployment clone, pulled --ff-only, not a dev checkout -- a local commit here can never fast-forward past again and silently wedges every future pull. Develop this project from its own self-dev account instead." >&2
exit 1
HOOK
  chmod +x "$hook"
}

# The two that must exist before anything can be derived from them.
clone_or_update realisateur "https://github.com/$GH_OWNER/realisateur.git"
clone_or_update scheduler   "https://github.com/$GH_OWNER/scheduler.git"

# EVERY OTHER REPO IS DERIVED, NOT TYPED: schedule/<p>.conf declares REPO_URL and IS the registry. A typed list here would be a second source that drifts.
for p in ${SELFDEV_PROJECTS:-senechal ecosim}; do
  conf="$PROJECTS/scheduler/schedule/$p.conf"
  if [ ! -f "$conf" ]; then bad "$p: no schedule/$p.conf -- not a registered project"; continue; fi
  url="$(grep -hE '^REPO_URL=' "$conf" | head -1 | cut -d'"' -f2)"
  [ -n "$url" ] || { bad "$p: schedule/$p.conf declares no REPO_URL"; continue; }
  clone_or_update "$p" "$url"
done

if ! command -v installe >/dev/null 2>&1; then
  if [ -x "$PROJECTS/realisateur/bin/install-verb-build.sh" ]; then
    act "installe: bootstrap by installing the pinned verb build"
    if "$PROJECTS/realisateur/bin/install-verb-build.sh" --latest --apply --link; then
      command -v installe >/dev/null 2>&1 \
        && ok "verb build installed; installe on PATH" \
        || bad "the verb build installed but installe is still not on PATH"
    else
      bad "could not install a verb build (see above) -- no verb can be installed on this host"
    fi
  else
    bad "no $PROJECTS/realisateur/bin/install-verb-build.sh -- cannot obtain a verb build, so no verb can be installed"
  fi
else ok "installe already on PATH"; fi

# NO SHIM STEP: #264 got off shims and #511 deleted the installer. Commands and hooks ride the verb build (bin/lib/carries.tsv); settings.json is selfdev-hooks-provision.sh, run by root.
if [ -x "$PROJECTS/realisateur/bin/install-verbs.sh" ]; then
  act "install-verbs.sh --apply (every write routed through installe)"
  "$PROJECTS/realisateur/bin/install-verbs.sh" --apply \
    && ok "verb surface installed" || gap "install-verbs.sh reported gaps -- read them above"
fi

if [ -x "$PROJECTS/realisateur/bin/guard-readonly-clone.sh" ]; then
  act "guard-readonly-clone.sh --apply (refuse a local commit into realisateur/scheduler/senechal)"
  "$PROJECTS/realisateur/bin/guard-readonly-clone.sh" --apply \
    && ok "read-only clones guarded against a local commit" \
    || gap "guard-readonly-clone.sh reported gaps -- read them above"
else
  gap "no $PROJECTS/realisateur/bin/guard-readonly-clone.sh -- read-only clones are NOT guarded against a local commit"
fi

echo
echo "== dispatch preview (NOTHING armed) =="
if [ -x "$PROJECTS/scheduler/bin/dose-project.sh" ]; then
  ( cd "$PROJECTS/scheduler" && ./bin/dose-project.sh "$(id -un)" --check ) || true
fi
cat <<EOF

land-selfdev: $PASS ok, $GAPS missing, $BAD bad.

NOTHING IS SCHEDULED YET, deliberately. Read the preview above; there must be
ZERO lines beginning "BROKEN". A live schedule/ROSTER row for $(id -un) is a
human-only act (dose <project> --arm, #291) and has to exist before this can
converge. Then, and only as a separate act:

    cd $PROJECTS/scheduler && ./bin/dose-project.sh "$(id -un)" --apply

Arming dispatch is the one step that spends a shared quota, and on this
ecosystem's accounting mandark, dexter and this host all draw on the same
weekly budget.
EOF
[ "$BAD" -eq 0 ]
