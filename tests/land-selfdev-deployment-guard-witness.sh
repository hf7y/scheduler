#!/usr/bin/env bash
# Witness for hf7y/scheduler#321's guard: land-selfdev.sh installs a
# pre-commit hook that refuses commits in any clone that is NOT this
# account's own dev target, so a local commit into a pure --ff-only
# deployment clone (the wtul/scheduler shape that wedged PULL for 3 ticks)
# fails loud at commit time instead of silently three ticks later.
#
# HERMETICITY: fully offline. `git clone https://github.com/<owner>/<name>`
# is redirected to a local fixture repo by a `git` shim placed early on
# PATH; `id -un` is shimmed to a fixed fake account name so the "own repo"
# vs. "foreign clone" branch is deterministic regardless of who runs this.
set -uo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/harness.sh"

REAL_SCRIPT="$(cd "$(dirname "$0")/../bin" && pwd)/land-selfdev.sh"
[ -x "$REAL_SCRIPT" ] || { echo "FAIL: $REAL_SCRIPT not executable"; exit 1; }

harness_tmp
REALGIT="$(command -v git)"
FAKEBIN="$T/fakebin"
REMOTES="$T/remotes"
PROJECTS="$T/projects"
mkdir -p "$FAKEBIN" "$REMOTES" "$PROJECTS"

# Run from an isolated copy with NO wire-selfdev-git.sh beside it: that
# script really registers ssh deploy keys and calls the GitHub API, which
# this witness must not do. Absent, land-selfdev.sh's own [ -x "$WIRE" ]
# check gaps harmlessly instead (bin/land-selfdev.sh:118).
BINDIR="$T/bin"; mkdir -p "$BINDIR"
cp "$REAL_SCRIPT" "$BINDIR/land-selfdev.sh"
SCRIPT="$BINDIR/land-selfdev.sh"

mkremote() {  # <name> [extra files...]
  local d="$REMOTES/$1"; mkdir -p "$d"
  git -C "$d" init -q
  printf '# %s fixture\n' "$1" > "$d/README"
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init -q
  echo "$d"
}

# "scheduler" carries a schedule/realisateur.conf so the SELFDEV_PROJECTS
# loop (set to just "realisateur" below) re-resolves the SAME fixture
# already cloned by the two hardcoded lines, instead of needing a third.
SCHED_REMOTE="$(mkremote scheduler)"
mkdir -p "$SCHED_REMOTE/schedule"
cat > "$SCHED_REMOTE/schedule/realisateur.conf" <<EOF
REPO_URL="https://github.com/fixtureowner/realisateur.git"
EOF
git -C "$SCHED_REMOTE" add -A
git -C "$SCHED_REMOTE" -c user.email=t@t -c user.name=t commit -qm "add realisateur.conf" -q
mkremote realisateur >/dev/null

# --- git shim: redirect https://github.com/fixtureowner/<name>.git clones to
# the local fixture remote; everything else (fetch/pull/rev-parse on an
# already-cloned dir) is untouched real git.
cat > "$FAKEBIN/git" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "clone" ]; then
  args=("\$@")
  for i in "\${!args[@]}"; do
    case "\${args[\$i]}" in
      https://github.com/fixtureowner/*.git)
        n="\$(basename "\${args[\$i]}" .git)"
        args[\$i]="$REMOTES/\$n"
        ;;
    esac
  done
  exec "$REALGIT" "\${args[@]}"
fi
exec "$REALGIT" "\$@"
SHIM
chmod +x "$FAKEBIN/git"

# --- id shim: land-selfdev.sh's own-repo test is `[ "$name" = "$(id -un)" ]`
# (bin/land-selfdev.sh:119, reused by the guard) -- pin it so "scheduler" is
# always this run's own account and "realisateur" is always foreign.
cat > "$FAKEBIN/id" <<SHIM
#!/usr/bin/env bash
[ "\$1" = "-un" ] && { echo scheduler; exit 0; }
exec /usr/bin/id "\$@"
SHIM
chmod +x "$FAKEBIN/id"

export PATH="$FAKEBIN:$PATH"
export INSTALLE_PROJECTS="$PROJECTS"
export SELFDEV_GH_OWNER="fixtureowner"
export SELFDEV_PROJECTS="realisateur"
export HOME="$T/home"; mkdir -p "$HOME"

section "A. --land clones both fixtures and does not fail"
OUT="$("$SCRIPT" --land 2>&1)"; RC=$?
rc "A1 exits 0" 0 "$RC" || printf '%s\n' "$OUT" | sed 's/^/    /'
[ -d "$PROJECTS/scheduler/.git" ] && ok "A2 scheduler cloned" || bad "A2 scheduler not cloned"
[ -d "$PROJECTS/realisateur/.git" ] && ok "A3 realisateur cloned" || bad "A3 realisateur not cloned"

section "B. the account's own repo (scheduler, matches id -un) is NOT guarded"
[ -x "$PROJECTS/scheduler/.git/hooks/pre-commit" ] \
  && bad "B1 scheduler has a pre-commit guard but is this account's own dev target" \
  || ok "B1 scheduler carries no pre-commit guard"
echo x > "$PROJECTS/scheduler/scratch"
git -C "$PROJECTS/scheduler" add scratch
git -C "$PROJECTS/scheduler" -c user.email=t@t -c user.name=t commit -qm scratch
rc "B2 a commit into scheduler's own clone succeeds" 0 "$?"

section "C. a foreign clone (realisateur) IS guarded"
[ -x "$PROJECTS/realisateur/.git/hooks/pre-commit" ] \
  && ok "C1 realisateur carries a pre-commit guard" \
  || bad "C1 realisateur has no pre-commit guard"
echo x > "$PROJECTS/realisateur/scratch"
git -C "$PROJECTS/realisateur" add scratch
OUT="$(git -C "$PROJECTS/realisateur" -c user.email=t@t -c user.name=t commit -qm scratch 2>&1)"; RC=$?
rc "C2 the commit is refused" 1 "$RC"
has "C3 the refusal names the deployment-clone reason" "$OUT" "deployment clone"

section "D. idempotent: a second --land re-converges the same guard state"
OUT2="$("$SCRIPT" --land 2>&1)"; RC2=$?
rc "D1 exits 0" 0 "$RC2" || printf '%s\n' "$OUT2" | sed 's/^/    /'
[ -x "$PROJECTS/scheduler/.git/hooks/pre-commit" ] \
  && bad "D2 scheduler grew a guard on the second run" \
  || ok "D2 scheduler still carries no guard"
[ -x "$PROJECTS/realisateur/.git/hooks/pre-commit" ] \
  && ok "D3 realisateur still carries the guard" \
  || bad "D3 realisateur's guard vanished on re-run"

summary
