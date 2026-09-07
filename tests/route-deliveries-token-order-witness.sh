#!/usr/bin/env bash
# Witness for hf7y/scheduler#657: route-deliveries.sh must see the minted
# GH_TOKEN, not run before it exists.
#
# THE DEFECT. bin/scheduler-run calls route-deliveries.sh (delivering an
# issue's blockers before the run picks tonight's work, #299) BEFORE it mints
# the GitHub App installation token. On an account authenticated purely by
# App token -- no ~/.config/gh/hosts.yml, the arrangement gen-2 wants and the
# one `dog@vaporwave` already has -- route-deliveries runs with no credential
# at all and goes BLIND, one tick stale, silently (never fatal by design, so
# nothing surfaces it). Every account on monkey carries a stored gho_ token,
# which is exactly why this went unnoticed there.
#
# THIS WITNESS never touches GitHub: route-deliveries.sh is stubbed to record
# what GH_TOKEN held at the moment it was invoked, same fixture shape as
# tests/gh-app-token-witness.sh (whose case 1 this borrows).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/bin/scheduler-run"
[ -f "$RUN" ] || { echo "scheduler-run not found: $RUN"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "route-deliveries-token-order-witness"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

FX="$TMP/repo"
mkdir -p "$FX/bin" "$FX/lib" "$FX/schedule"
cp "$RUN" "$FX/bin/scheduler-run"
cp "$ROOT/lib/dose-common.sh" "$FX/lib/dose-common.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/bin/freeze-check.sh"
chmod +x "$FX/bin/freeze-check.sh" "$FX/bin/scheduler-run"
printf 'exit 0\n' > "$FX/lib/sweep-loop-common.sh"

SEEN="$TMP/route-deliveries-saw-token"
cat > "$FX/bin/route-deliveries.sh" <<EOF
#!/usr/bin/env bash
printf '%s' "\${GH_TOKEN:-<unset>}" > "$SEEN"
exit 0
EOF
chmod +x "$FX/bin/route-deliveries.sh"

cat > "$FX/schedule/proj.conf" <<'EOF'
REPO_URL="https://example.invalid/fixture.git"
BATCH_JOB_NAME="proj-batch"
BATCH_PROMPT="OWN PROMPT."
EOF

HELPER="$TMP/selfdev-gh-app.sh"
CONF="$TMP/gh-app.conf"
: > "$CONF"
printf '%s\n' '#!/usr/bin/env bash' 'echo ghs_FIXTURE_TOKEN' > "$HELPER"
chmod +x "$HELPER"

mkdir -p "$TMP/stub"
cat > "$TMP/stub/gh" <<'EOF'
#!/usr/bin/env bash
echo hf7y/proj
EOF
chmod +x "$TMP/stub/gh"

( cd "$FX" \
  && unset GH_TOKEN \
  && PATH="$TMP/stub:$PATH" \
     SELFDEV_APP_CONF="$CONF" SELFDEV_GH_APP_SH="$HELPER" GH_OWN_REPO="hf7y/proj" \
     bash bin/scheduler-run proj batch >"$TMP/out" 2>"$TMP/err" )
rc=$?

seen="$(cat "$SEEN" 2>/dev/null || echo '<never called>')"

if [ "$rc" -ne 0 ]; then
  bad "scheduler-run exited $rc, want 0: $(cat "$TMP/err")"
elif [ "$seen" = "ghs_FIXTURE_TOKEN" ]; then
  ok "route-deliveries.sh saw the minted GH_TOKEN -- ordering is correct"
elif [ "$seen" = "<unset>" ]; then
  bad "route-deliveries.sh ran with GH_TOKEN unset -- it ran BEFORE the mint (hf7y/scheduler#657)"
else
  bad "route-deliveries.sh saw an unexpected token/state: [$seen]"
fi

printf '\nroute-deliveries-token-order-witness: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
