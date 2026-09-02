#!/usr/bin/env bash
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

BINDIR="$T/bin"; mkdir -p "$BINDIR"
cp "$REAL_SCRIPT" "$BINDIR/land-selfdev.sh"
SCRIPT="$BINDIR/land-selfdev.sh"

mkremote() {
  local d="$REMOTES/$1"; mkdir -p "$d"
  git -C "$d" init -q
  printf '%s fixture\n' "$1" > "$d/README"
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init -q
  echo "$d"
}

SCHED_REMOTE="$(mkremote scheduler)"
mkdir -p "$SCHED_REMOTE/schedule"
cat > "$SCHED_REMOTE/schedule/realisateur.conf" <<EOF
REPO_URL="https://github.com/fixtureowner/realisateur.git"
EOF
git -C "$SCHED_REMOTE" add -A
git -C "$SCHED_REMOTE" -c user.email=t@t -c user.name=t commit -qm "add realisateur.conf" -q
mkremote realisateur >/dev/null

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

section "A. --land clones both fixtures (redirected offline) and does not fail"
OUT="$("$SCRIPT" --land 2>&1)"; RC=$?
rc "A1 exits 0" 0 "$RC" || printf '%s\n' "$OUT" | sed 's/^/    /'
[ -d "$PROJECTS/scheduler/.git" ] && ok "A2 scheduler cloned" || bad "A2 scheduler not cloned"
[ -d "$PROJECTS/realisateur/.git" ] && ok "A3 realisateur cloned" || bad "A3 realisateur not cloned"

section "B. the account's own repo (scheduler, matches shimmed id -un) is NOT guarded"
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
