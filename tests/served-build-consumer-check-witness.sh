#!/usr/bin/env bash
# Witness for bin/served-build-consumer-check.sh (hf7y/realisateur#1143).
#
# THE INCIDENT THIS GUARDS AGAINST: schedule/ROSTER was dead on `main` and
# load-bearing on the served build at the same time -- #716 deleted it,
# #718 reverted it minutes later because the fleet's actual build still had
# `fetch_roster() { fetch_repo_file schedule/ROSTER; }`. This witness proves
# the check would have said FOUND/exit 1 against that build, and CLEAR/exit
# 0 once a cut build drops the reference -- and, just as load-bearing, that
# "I could not find a served build at all" reports BLIND/exit 6, never the
# same exit 0 a genuinely clean build gets (the #511 lesson: a scan that
# could not look must never read the same as a scan that looked and found
# nothing).
#
# Hermetic: every case builds its own throwaway verb-builds tree under a
# mktemp dir and points the script at it via VERB_HOST_BUILD_ROOT. It never
# reads this machine's real /usr/local/share/verb-builds.
set -uo pipefail

SCHED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCHED_ROOT/bin/served-build-consumer-check.sh"
[ -x "$SCRIPT" ] || { echo "script under test not found or not executable: $SCRIPT"; exit 1; }

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

run() { local root="$1"; shift; VERB_HOST_BUILD_ROOT="$root" "$SCRIPT" "$@"; }

# ---------------------------------------------------------------------- A ---
# No served build at all -- BLIND, never CLEAR.
ROOT_A="$TMP/a"
out="$(run "$ROOT_A" schedule/ROSTER 2>&1)"; rc=$?
if [ "$rc" = 6 ]; then ok "A1 no served build at all exits 6 (BLIND)"
else bad "A1 no served build at all exits 6 (BLIND) (got $rc)"; fi
if printf '%s' "$out" | grep -q '^BLIND:'; then ok "A2 says BLIND, not clean"
else bad "A2 says BLIND, not clean"; fi
if printf '%s' "$out" | grep -qi 'not evidence the deletion is safe'; then
  ok "A3 explicitly disclaims that BLIND means safe"
else bad "A3 explicitly disclaims that BLIND means safe"; fi

# ---------------------------------------------------------------------- B ---
# Served build directory exists but is empty -- also BLIND, not CLEAR.
ROOT_B="$TMP/b"
mkdir -p "$ROOT_B/current/scheduler"
out="$(run "$ROOT_B" schedule/ROSTER 2>&1)"; rc=$?
if [ "$rc" = 6 ]; then ok "B1 an empty served build exits 6 (BLIND)"
else bad "B1 an empty served build exits 6 (BLIND) (got $rc)"; fi
if printf '%s' "$out" | grep -q 'contains no files'; then ok "B2 names the empty-tree reason"
else bad "B2 names the empty-tree reason"; fi

# ---------------------------------------------------------------------- C ---
# THE LOAD-BEARING CASE: served build still has the old fetch_roster() that
# reads schedule/ROSTER directly, exactly like build 2026-09-07T031807Z did.
ROOT_C="$TMP/c"
mkdir -p "$ROOT_C/2026-09-07T031807Z/scheduler/lib" "$ROOT_C/2026-09-07T031807Z/scheduler/bin"
cat > "$ROOT_C/2026-09-07T031807Z/scheduler/lib/dose-common.sh" <<'EOF'
fetch_roster() { fetch_repo_file schedule/ROSTER; }
EOF
ln -sfn "$ROOT_C/2026-09-07T031807Z" "$ROOT_C/current"
out="$(run "$ROOT_C" schedule/ROSTER 2>&1)"; rc=$?
if [ "$rc" = 1 ]; then ok "C1 a served build that still reads the needle exits 1 (FOUND/refuse)"
else bad "C1 a served build that still reads the needle exits 1 (FOUND/refuse) (got $rc)"; fi
if printf '%s' "$out" | grep -q '^FOUND:.*schedule/ROSTER'; then ok "C2 names the needle in a FOUND row"
else bad "C2 names the needle in a FOUND row"; fi
if printf '%s' "$out" | grep -q 'dose-common.sh:1:fetch_roster'; then
  ok "C3 points at the actual file:line that still reads it"
else bad "C3 points at the actual file:line that still reads it"; fi
if printf '%s' "$out" | grep -q '2026-09-07T031807Z'; then
  ok "C4 resolves and names which build (the symlink target), not just 'the served build'"
else bad "C4 resolves and names which build (the symlink target), not just 'the served build'"; fi
if printf '%s' "$out" | grep -q 'hf7y/realisateur#1143'; then
  ok "C5 the refusal cites the incident, so a human hitting this cold has the story"
else bad "C5 the refusal cites the incident, so a human hitting this cold has the story"; fi

# ---------------------------------------------------------------------- D ---
# A later, cut build that reads the roster SERVICE instead -- CLEAR/exit 0.
ROOT_D="$TMP/d"
mkdir -p "$ROOT_D/2026-10-07T031807Z/scheduler/lib"
cat > "$ROOT_D/2026-10-07T031807Z/scheduler/lib/dose-common.sh" <<'EOF'
fetch_roster() { curl -fsS --max-time 10 "$ROSTER_URL/roster"; }
EOF
ln -sfn "$ROOT_D/2026-10-07T031807Z" "$ROOT_D/current"
out="$(run "$ROOT_D" schedule/ROSTER 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then ok "D1 a served build that no longer reads the needle exits 0 (CLEAR)"
else bad "D1 a served build that no longer reads the needle exits 0 (CLEAR) (got $rc)"; fi
if printf '%s' "$out" | grep -q '^CLEAR:'; then ok "D2 says CLEAR"
else bad "D2 says CLEAR"; fi

# ---------------------------------------------------------------------- E ---
# Multiple needles: one still referenced, one not -- exit 1 overall (ANY
# match refuses), and both rows are reported so nothing is hidden.
out="$(run "$ROOT_C" schedule/ROSTER a-symbol-nobody-uses 2>&1)"; rc=$?
if [ "$rc" = 1 ]; then ok "E1 one FOUND among several needles still refuses (exit 1)"
else bad "E1 one FOUND among several needles still refuses (exit 1) (got $rc)"; fi
if printf '%s' "$out" | grep -q "clear: 'a-symbol-nobody-uses'"; then
  ok "E2 the needle that IS clear is still reported, not swallowed by the refusal"
else bad "E2 the needle that IS clear is still reported, not swallowed by the refusal"; fi

# ---------------------------------------------------------------------- F ---
# Usage: no needle at all is a usage error, not a vacuous CLEAR.
out="$("$SCRIPT" 2>&1)"; rc=$?
if [ "$rc" = 2 ]; then ok "F1 no needle given exits 2 (usage)"
else bad "F1 no needle given exits 2 (usage) (got $rc)"; fi

# ---------------------------------------------------------------------- G ---
# The check leaves its own runtime witness (docs/offline-first-checks.md's
# "a check must prove it ran" rule) -- confirmed against a throwaway witness
# dir so this test never touches the real one.
WITNESS_DIR="$TMP/witnesses"
CHECK_WITNESS_DIR="$WITNESS_DIR" VERB_HOST_BUILD_ROOT="$ROOT_D" "$SCRIPT" schedule/ROSTER >/dev/null 2>&1
if [ -f "$WITNESS_DIR/served-build-consumer-check.sh.lastrun" ]; then
  ok "G1 running the check writes its own check-witness-lint witness"
else bad "G1 running the check writes its own check-witness-lint witness"; fi

echo
echo "== served-build-consumer-check: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
