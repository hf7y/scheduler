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

# scheduler is DELIBERATELY a remote-only fixture (hf7y/realisateur#1138):
# land-selfdev.sh no longer clones it, so this witness must prove schedule/
# lookups work off it read via the `gh` shim below, not off a checkout.
SCHED_REMOTE="$(mkremote scheduler)"
mkdir -p "$SCHED_REMOTE/schedule"
cat > "$SCHED_REMOTE/schedule/senechal.conf" <<EOF
REPO_URL="https://github.com/fixtureowner/senechal.git"
EOF
git -C "$SCHED_REMOTE" add -A
git -C "$SCHED_REMOTE" -c user.email=t@t -c user.name=t commit -qm "add senechal.conf" -q
mkremote realisateur >/dev/null
mkremote senechal >/dev/null

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
[ "\$1" = "-un" ] && { echo realisateur; exit 0; }
exec /usr/bin/id "\$@"
SHIM
chmod +x "$FAKEBIN/id"

cat > "$FAKEBIN/installe" <<SHIM
#!/usr/bin/env bash
exit 0
SHIM
chmod +x "$FAKEBIN/installe"

# fetch_schedule_file's whole reason to exist: read schedule/<rel> over `gh
# api ... --jq '.content'` with NO local scheduler checkout. This shim serves
# that call straight out of SCHED_REMOTE/schedule, base64-encoded, the same
# shape the real .content field carries.
cat > "$FAKEBIN/gh" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "api" ]; then
  path="\${2#repos/fixtureowner/scheduler/contents/schedule/}"
  path="\${path%%\?*}"
  f="$SCHED_REMOTE/schedule/\$path"
  [ -f "\$f" ] && { base64 -w0 "\$f" 2>/dev/null || base64 "\$f"; exit 0; }
  exit 1
fi
exit 1
SHIM
chmod +x "$FAKEBIN/gh"

export PATH="$FAKEBIN:$PATH"
export INSTALLE_PROJECTS="$PROJECTS"
export SELFDEV_GH_OWNER="fixtureowner"
export SELFDEV_PROJECTS="senechal"
export HOME="$T/home"; mkdir -p "$HOME"

section "A. --land clones realisateur and the derived project (redirected offline); scheduler is NEVER cloned (#1138)"
OUT="$("$SCRIPT" --land 2>&1)"; RC=$?
rc "A1 exits 0" 0 "$RC" || printf '%s\n' "$OUT" | sed 's/^/    /'
[ -d "$PROJECTS/realisateur/.git" ] && ok "A2 realisateur cloned" || bad "A2 realisateur not cloned"
[ -d "$PROJECTS/senechal/.git" ] && ok "A3 senechal cloned (its REPO_URL was read off scheduler via gh, no checkout)" || bad "A3 senechal not cloned"
[ -e "$PROJECTS/scheduler" ] && bad "A4 scheduler was cloned/created -- it must not be (#1138)" || ok "A4 no \$PROJECTS/scheduler exists"
has "A5 the derivation loop names how it read senechal.conf" "$OUT" "senechal: schedule/senechal.conf read via gh"

section "B. the account's own repo (realisateur, matches shimmed id -un) is NOT guarded"
[ -x "$PROJECTS/realisateur/.git/hooks/pre-commit" ] \
  && bad "B1 realisateur has a pre-commit guard but is this account's own dev target" \
  || ok "B1 realisateur carries no pre-commit guard"
echo x > "$PROJECTS/realisateur/scratch"
git -C "$PROJECTS/realisateur" add scratch
git -C "$PROJECTS/realisateur" -c user.email=t@t -c user.name=t commit -qm scratch
rc "B2 a commit into realisateur's own clone succeeds" 0 "$?"

section "C. a foreign, derived clone (senechal) IS guarded"
[ -x "$PROJECTS/senechal/.git/hooks/pre-commit" ] \
  && ok "C1 senechal carries a pre-commit guard" \
  || bad "C1 senechal has no pre-commit guard"
echo x > "$PROJECTS/senechal/scratch"
git -C "$PROJECTS/senechal" add scratch
OUT="$(git -C "$PROJECTS/senechal" -c user.email=t@t -c user.name=t commit -qm scratch 2>&1)"; RC=$?
rc "C2 the commit is refused" 1 "$RC"
has "C3 the refusal names the deployment-clone reason" "$OUT" "deployment clone"

section "D. idempotent: a second --land re-converges the same guard state, still with no scheduler clone"
OUT2="$("$SCRIPT" --land 2>&1)"; RC2=$?
rc "D1 exits 0" 0 "$RC2" || printf '%s\n' "$OUT2" | sed 's/^/    /'
[ -x "$PROJECTS/realisateur/.git/hooks/pre-commit" ] \
  && bad "D2 realisateur grew a guard on the second run" \
  || ok "D2 realisateur still carries no guard"
[ -x "$PROJECTS/senechal/.git/hooks/pre-commit" ] \
  && ok "D3 senechal still carries the guard" \
  || bad "D3 senechal's guard vanished on re-run"
[ -e "$PROJECTS/scheduler" ] && bad "D4 scheduler appeared on the second run" || ok "D4 still no \$PROJECTS/scheduler"

summary
