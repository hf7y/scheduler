#!/usr/bin/env bash
# Witness for bin/deploy-drift-check.sh's DECLARED-SET check.
#
# THE LOAD-BEARING CASE IS A: a path this repo's config names under
# $DEPLOY_DIR, with nothing installed there, must FLAG and exit 1.
#
# Until 2026-08-02 it did not, and could not. The script iterated
# "per file in this repo's bin/ that ALSO EXISTS in $DEPLOY_DIR" -- the
# intersection -- and `continue`d when the installed file was absent, so a
# link that SHOULD exist but did not was never examined. Only a DANGLING
# symlink was caught, never an ABSENT one. With no overlap at all it printed
# "nothing in $DEPLOY_DIR shares a name with this repo's bin/ -- nothing to
# check" and exited 0: a clean bill of health for a host where every declared
# path is missing. That is the same exit-0 no-op the repo's own build
# discipline forbids, sitting inside the guard built to catch deploy problems,
# and it is why the 2026-07-29 bare-host bootstrap reported clean while
# dispatch was totally down.
#
# The rule, from DEXTER-MIGRATION-NOTES-20260729.md:
#   check the DECLARED set, never the intersection, or absence reports clean.
#
# Hermetic: builds a throwaway repo and deploy dir. It never reads this
# machine's real ~/.local/bin and never writes outside its temp dir.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/deploy-drift-check.sh"
[ -f "$SRC" ] || { echo "script under test not found: $SRC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

DEPLOY="$TMP/deploy"

# A throwaway repo carrying only what the check reads: bin/ and the configs
# the declaration is derived from.
new_repo() {
  rm -rf "$TMP/repo" "$DEPLOY"
  mkdir -p "$TMP/repo/bin" "$TMP/repo/schedule" "$TMP/repo/.scheduler" "$DEPLOY"
  cp "$SRC" "$TMP/repo/bin/deploy-drift-check.sh"
  chmod +x "$TMP/repo/bin/deploy-drift-check.sh"
}

run() { DEPLOY_DIR="$DEPLOY" bash "$TMP/repo/bin/deploy-drift-check.sh" 2>&1; }

# ---------------------------------------------------------------------- A ---
# Declared by config, source present in bin/, NOTHING installed.
new_repo
printf '#!/bin/sh\necho hi\n' > "$TMP/repo/bin/runner.sh"; chmod +x "$TMP/repo/bin/runner.sh"
printf 'RUNNER_CMD="%s/runner.sh"\n' "$DEPLOY" > "$TMP/repo/schedule/_runner.conf"

out="$(run)"; rc=$?
if [ "$rc" = 1 ]; then ok "A1 an absent declared install exits 1 (was 0: the whole defect)"
else bad "A1 an absent declared install exits 1 (got $rc)"; fi
# Anchored to the ABSENT ROW, not to the word: the script's own prose mentions
# absence, so a bare `grep ABSENT` would pass on the explanatory text alone.
if printf '%s' "$out" | grep -qE '^ABSENT runner\.sh'; then ok "A2 the absent install is named in an ABSENT row"
else bad "A2 the absent install is named in an ABSENT row"; fi
if printf '%s' "$out" | grep -q 'NOTHING IS INSTALLED THERE'; then ok "A3 it says plainly that nothing is installed"
else bad "A3 it says plainly that nothing is installed"; fi
if printf '%s' "$out" | grep -q 'nothing to check'; then bad "A4 it no longer reports 'nothing to check'"
else ok "A4 it no longer reports 'nothing to check'"; fi

# ---------------------------------------------------------------------- B ---
# The same declaration, satisfied by a symlink, is clean.
ln -sfn "$TMP/repo/bin/runner.sh" "$DEPLOY/runner.sh"
out="$(run)"; rc=$?
if [ "$rc" = 0 ]; then ok "B1 a satisfied declaration exits 0"
else bad "B1 a satisfied declaration exits 0 (got $rc)"; fi
if printf '%s' "$out" | grep -qE '^ABSENT'; then bad "B2 nothing is reported absent once installed"
else ok "B2 nothing is reported absent once installed"; fi

# ---------------------------------------------------------------------- C ---
# A commented-out path is discussion, not a declaration. schedule/_paced.dexter.conf
# talks about installed wrappers at length precisely to say it does NOT use them,
# and reading those as declarations would flag a correct host.
new_repo
printf '#!/bin/sh\n' > "$TMP/repo/bin/ghost.sh"; chmod +x "$TMP/repo/bin/ghost.sh"
printf 'REAL_CMD="%s/real.sh"\n# EXAMPLE ONLY: %s/ghost.sh\n' "$DEPLOY" "$DEPLOY" \
  > "$TMP/repo/schedule/_x.conf"
printf '#!/bin/sh\n' > "$TMP/repo/bin/real.sh"; chmod +x "$TMP/repo/bin/real.sh"
out="$(run)"
if printf '%s' "$out" | grep -qE '^ABSENT ghost\.sh'; then bad "C1 a commented path is not a declaration"
else ok "C1 a commented path is not a declaration"; fi
if printf '%s' "$out" | grep -qE '^ABSENT real\.sh'; then ok "C2 the uncommented path on the same file still is"
else bad "C2 the uncommented path on the same file still is"; fi

# ---------------------------------------------------------------------- D ---
# Declared, but this repo has nothing to install from. Not fixable by symlink,
# so it must not be reported as if `ln -sfn` would solve it.
new_repo
printf 'ORPHAN_CMD="%s/no-such.sh"\n' "$DEPLOY" > "$TMP/repo/schedule/_y.conf"
out="$(run)"; rc=$?
if [ "$rc" = 1 ]; then ok "D1 a declaration with no source exits 1"
else bad "D1 a declaration with no source exits 1 (got $rc)"; fi
if printf '%s' "$out" | grep -qE '^NOSRC no-such\.sh'; then ok "D2 it is NOSRC, not ABSENT"
else bad "D2 it is NOSRC, not ABSENT"; fi

# ---------------------------------------------------------------------- E ---
# Zero declarations is a DERIVATION failure, not a clean host. If this ever
# reports clean, the check has quietly stopped checking -- which is the exact
# shape of the bug this file exists for, one level up.
new_repo
printf '# nothing declared here\n' > "$TMP/repo/schedule/_z.conf"
out="$(run)"; rc=$?
if [ "$rc" = 1 ]; then ok "E1 zero declarations fails loud rather than passing"
else bad "E1 zero declarations fails loud rather than passing (got $rc)"; fi
if printf '%s' "$out" | grep -q 'DERIVATION failure'; then ok "E2 it names the derivation as the suspect"
else bad "E2 it names the derivation as the suspect"; fi

echo
echo "deploy-declared-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
