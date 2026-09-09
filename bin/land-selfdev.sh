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

# fetch_schedule_file <rel-under-schedule/>: print that file's content read
# over `gh api`, no local scheduler checkout needed -- the same "served build"
# design bin/scheduler-run's read_schedule_rel/fetch_repo_file already use
# (hf7y/scheduler#350). land-selfdev.sh no longer clones scheduler into every
# account (hf7y/realisateur#1138), so the checks below that used to read
# $PROJECTS/scheduler/schedule/* off a clone this same run had just made now
# read it this way instead, whether or not a local scheduler checkout happens
# to exist. NOT sourced from lib/dose-common.sh's fetch_repo_file: this script
# is staged and run as a lone file with no lib/ sibling (see the note above
# PASS/GAPS/BAD), so this is a deliberately self-contained inline copy, kept
# simple -- land-selfdev's own OK/MISSING/BAD vocabulary has no BLIND/GAP
# split to preserve, so callers just treat any nonzero return as MISSING.
fetch_schedule_file() {
  local rel="${1:?fetch_schedule_file needs a schedule/-relative path}" out
  command -v gh >/dev/null 2>&1 || return 1
  out="$(gh api "repos/$GH_OWNER/scheduler/contents/schedule/$rel?ref=main" --jq '.content' 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out" | tr -d '\n' | base64 -d 2>/dev/null
}

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
PACED_HOST_REL="_paced.$HOST.conf"
if [ -f "$PROJECTS/scheduler/schedule/$PACED_HOST_REL" ]; then
  ok "schedule/$PACED_HOST_REL exists locally -- this host has its own rotation"
elif fetch_schedule_file "$PACED_HOST_REL" >/dev/null; then
  ok "schedule/$PACED_HOST_REL exists (read via gh, no local scheduler checkout -- #350) -- this host has its own rotation"
else
  # No host-scoped file, local or remote: this host would fall back to the
  # shared _paced.conf. Read THAT the same way -- local if a checkout happens
  # to exist (a human dev clone), else via gh, so this stays informative on a
  # host with nothing locally, same as scheduler-run itself.
  shared_content="" shared_src=""
  if [ -f "$PROJECTS/scheduler/schedule/_paced.conf" ]; then
    shared_content="$(cat "$PROJECTS/scheduler/schedule/_paced.conf")"; shared_src="local"
  elif shared_content="$(fetch_schedule_file "_paced.conf")"; then
    shared_src="fetched via gh"
  fi
  if [ -n "$shared_src" ]; then
    enabled=$(grep -cE '^[a-z][^|]*\|1\|' <<<"$shared_content" 2>/dev/null || echo 0)
    if [ "${enabled:-0}" -gt 0 ]; then
      bad "no schedule/$PACED_HOST_REL, and the shared schedule/_paced.conf ($shared_src) has $enabled ENABLED row(s) -- this host would silently dispatch another machine's rotation"
    else
      gap "no schedule/$PACED_HOST_REL; this host falls back to the shared schedule/_paced.conf ($shared_src), which currently has 0 enabled rows (inert, but give this host its own file before arming anything)"
    fi
  else
    gap "could not read schedule/$PACED_HOST_REL or the shared schedule/_paced.conf, locally or via gh -- cannot check this host's rotation (gh unauthenticated? see the GitHub read/write checks below)"
  fi
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

# The one that must exist before anything else can be derived from it.
clone_or_update realisateur "https://github.com/$GH_OWNER/realisateur.git"

# scheduler is DELIBERATELY NOT cloned here (hf7y/realisateur#1138): dispatch
# reads schedule/<project>.conf over `gh api` when there is no local
# schedule/ (bin/scheduler-run's read_schedule_rel, #350), and dose-project.sh
# dispatches from the installed build (DOSE_BUILD_ROOT), never a per-account
# checkout, because a checkout can go stale until hand-pulled --
# hf7y/scheduler#321 is what that looked like: a dispatch checkout diverged
# and ran stale code for three ticks before a human reset it by hand. An
# account whose OWN project self-dev IS scheduler still gets a real,
# writable checkout of it -- via the derived loop below, same as any other
# project, if "scheduler" is in its SELFDEV_PROJECTS.

# EVERY OTHER REPO IS DERIVED, NOT TYPED: schedule/<p>.conf declares REPO_URL and IS the registry. A typed list here would be a second source that drifts.
# Read local-if-present, else via gh (fetch_schedule_file, #350 again) --
# there is no longer a scheduler clone this run could have just made to read
# off of, on any account, so this must not assume one exists.
for p in ${SELFDEV_PROJECTS:-senechal ecosim}; do
  conf_content=""
  if [ -f "$PROJECTS/scheduler/schedule/$p.conf" ]; then
    conf_content="$(cat "$PROJECTS/scheduler/schedule/$p.conf")"
  elif conf_content="$(fetch_schedule_file "$p.conf")"; then
    act "$p: schedule/$p.conf read via gh, no scheduler clone needed (#350)"
  else
    bad "$p: no schedule/$p.conf -- not a registered project (checked locally and via gh; no scheduler clone needed, #350)"
    continue
  fi
  url="$(grep -hE '^REPO_URL=' <<<"$conf_content" | head -1 | cut -d'"' -f2)"
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
# dose-project.sh dispatches from the INSTALLED build, never a per-account
# checkout (same DOSE_BUILD_ROOT convention as bin/dose-project.sh and
# bin/usage-paced-runner.sh themselves, #350) -- preview from there first.
# The local-checkout branch only fires on the rare account that develops
# scheduler itself and so has a real clone of it (see the derived-project
# loop above); it did the same `cd`-and-run before this change.
DOSE_INSTALLED="${VERB_HOST_BUILD_ROOT:-/usr/local/share/verb-builds}/current/scheduler/bin/dose-project.sh"
if [ -x "$DOSE_INSTALLED" ]; then
  "$DOSE_INSTALLED" "$(id -un)" --check || true
elif [ -x "$PROJECTS/scheduler/bin/dose-project.sh" ]; then
  ( cd "$PROJECTS/scheduler" && ./bin/dose-project.sh "$(id -un)" --check ) || true
else
  gap "no dose-project.sh at the installed build ($DOSE_INSTALLED) or a local scheduler checkout -- cannot preview dispatch (a host-level verb build install is out of this script's scope)"
fi
cat <<EOF

land-selfdev: $PASS ok, $GAPS missing, $BAD bad.

NOTHING IS SCHEDULED YET, deliberately. Read the preview above; there must be
ZERO lines beginning "BROKEN". A live schedule/ROSTER row for $(id -un) is a
human-only act (dose <project> --arm, #291) and has to exist before this can
converge. Then, and only as a separate act:

    $DOSE_INSTALLED "$(id -un)" --apply

(that's the installed build, not a checkout -- $PROJECTS/scheduler generally
does not exist; see #1138. If it isn't there yet, a host-level verb build
install is what puts it there, out of this script's scope.)

Arming dispatch is the one step that spends a shared quota, and on this
ecosystem's accounting mandark, dexter and this host all draw on the same
weekly budget.
EOF
[ "$BAD" -eq 0 ]
