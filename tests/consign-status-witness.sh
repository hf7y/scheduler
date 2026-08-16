#!/usr/bin/env bash
# Witness for bin/consign-status.sh -- hermetic: builds a fixture vault and
# a fixture repo tree in a temp dir, never touches /srv/ecosystem1-vault or
# the live repo. Proves each of the four outcomes the script distinguishes:
# DUPLICATE (actionable), DIVERGED (informational, not actionable), REAPED
# (already removed, the success state), and BLIND (vault unreadable).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SCRIPT=bin/consign-status.sh

TMP="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

note() {  # note <vault-dir> <rel-path-in-note> <sha256> <consigned-date>
  local vault="$1" rel="$2" sha="$3" consigned="$4"
  local out="$vault/$(basename "$rel" .md).md"
  mkdir -p "$vault"
  {
    echo "---"
    echo "source_repo: /home/zach/Documents/Projects/scheduler"
    echo "source_path: $rel"
    echo "source_sha256: $sha"
    echo "consigned: $consigned"
    echo "project: scheduler"
    echo "---"
    echo "# $rel"
    echo "body"
  } > "$out"
}

echo "consign-status-witness"

# --- 1. a byte-identical duplicate is reported and exit is 1 --------------
d="$TMP/dup"; repo="$d/repo"; vault="$d/vault"
mkdir -p "$repo/docs"
printf 'unchanged content\n' > "$repo/docs/x.md"
sha="$(sha256sum "$repo/docs/x.md" | awk '{print $1}')"
note "$vault" "docs/x.md" "$sha" "2026-08-01"
out="$(SCHED_ROOT="$repo" CONSIGN_VAULT_ROOT="$vault" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "a real duplicate exits 1" || bad "exited $rc (want 1): $out"
case "$out" in *"DUPLICATE: docs/x.md"*) ok "duplicate is named" ;; *) bad "duplicate not named: $out" ;; esac

# --- 2. a diverged file (repo moved on) is informational, not a failure ---
d="$TMP/diverged"; repo="$d/repo"; vault="$d/vault"
mkdir -p "$repo/docs"
printf 'edited since consign\n' > "$repo/docs/y.md"
note "$vault" "docs/y.md" "0000000000000000000000000000000000000000000000000000000000000000" "2026-08-01"
out="$(SCHED_ROOT="$repo" CONSIGN_VAULT_ROOT="$vault" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a solely-diverged tree exits 0 (not actionable)" || bad "exited $rc (want 0): $out"
case "$out" in *"DIVERGED:  docs/y.md"*) ok "divergence is named" ;; *) bad "divergence not named: $out" ;; esac

# --- 3. already reaped (repo file gone) counts, does not fail -------------
d="$TMP/reaped"; repo="$d/repo"; vault="$d/vault"
mkdir -p "$repo"
note "$vault" "GONE.md" "deadbeef" "2026-08-01"
out="$(SCHED_ROOT="$repo" CONSIGN_VAULT_ROOT="$vault" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "an already-removed repo file exits 0" || bad "exited $rc (want 0): $out"
case "$out" in *"0 duplicate"*"1 already reaped"*) ok "reaped file is counted, not flagged" ;; *) bad "reaped count wrong: $out" ;; esac

# --- 4. missing vault root is BLIND, never reported as a clean queue ------
out="$(SCHED_ROOT="$TMP" CONSIGN_VAULT_ROOT="$TMP/no-such-vault" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "unreadable vault root is BLIND (exit 2)" || bad "exited $rc (want 2): $out"

# --- 5. mixed tree: duplicates drive the exit code even alongside others --
d="$TMP/mixed"; repo="$d/repo"; vault="$d/vault"
mkdir -p "$repo/docs"
printf 'still identical\n' > "$repo/docs/a.md"
sha_a="$(sha256sum "$repo/docs/a.md" | awk '{print $1}')"
note "$vault" "docs/a.md" "$sha_a" "2026-08-05"
note "$vault" "docs/b.md" "irrelevant-because-file-is-gone" "2026-08-05"
out="$(SCHED_ROOT="$repo" CONSIGN_VAULT_ROOT="$vault" bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "one duplicate among a mixed set still exits 1" || bad "exited $rc (want 1): $out"
case "$out" in *"1 duplicate"*"0 diverged"*"1 already reaped"*) ok "mixed-set counts line up" ;; *) bad "mixed-set counts wrong: $out" ;; esac

echo
echo "consign-status-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
