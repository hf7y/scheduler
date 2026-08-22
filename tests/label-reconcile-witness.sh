#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's reconcile_own_labels().
#
# THE BUG THIS EXISTS TO PREVENT, measured across hf7y on 2026-08-22:
#
#   ANSWERED = 12   UNANSWERED = 36   BLIND = 0
#
# Twelve open `needs-human` issues had already been answered by the human --
# seven of them in one repo -- and every one still carried the label.
# realisateur's `etiquette` detects exactly this (issue_answered() in
# bin/lib/answered.sh) and removes it. NOTHING RAN IT: no cron, no CI, no
# brief, nowhere in the estate. A correct mechanism with no invoker.
#
# It is not cosmetic. bin/tempo.sh subtracts `needs-human` from `actionable`
# before dividing -- the subtraction #262 kept when it capped drive at
# closures -- so a label left on an ANSWERED decision lengthens that project's
# own dispatch interval. The human's answer applies the brake it was meant to
# release.
#
# So the assertion is not "etiquette exists". It is that the ENGINE calls it,
# on ITS OWN repo and no other, and that neither a missing verb nor a BLIND
# read can make it fail quietly or take the run down with it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

eq()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- expected [$3] got [$2]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- no [$3] in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 -- unexpected [$3] in: $2" ;; *) ok "$1" ;; esac; }

# Sourcing the whole engine would run a real job (clone, claude, push), so
# lift just the one function out -- same technique as
# verdict-closeout-witness.sh. An extraction that stops matching is a FAILURE,
# not a pass by absence.
# own_repo_slug() too: reconcile_own_labels calls it, and lifting only the
# caller made this suite fail with `own_repo_slug: command not found` the
# moment the slug derivation was factored out for apply_decision_defaults to
# share. An extraction that silently loses a dependency reports the FUNCTION
# as broken when the TEST is.
awk '/^own_repo_slug\(\) \{$/,/^\}$/'          "$LIB" >  "$TMP/fn.sh"
awk '/^reconcile_own_labels\(\) \{$/,/^\}$/'   "$LIB" >> "$TMP/fn.sh"
grep -q 'etiquette' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract reconcile_own_labels() from $LIB"; exit 1; }
grep -q '^own_repo_slug()' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract own_repo_slug() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

mkdir -p "$TMP/bin" "$TMP/empty"
# The stub records the argv it was called with, so this can assert WHICH repo
# was reconciled -- the containment question, not merely "it ran".
stub_etiquette() { # <exit-code>
  cat > "$TMP/bin/etiquette" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TMP/argv"
echo "  -label    #6     needs-human removed"
echo "1 label(s) reconciled, 0 label(s) provisioned."
exit ${1:-0}
STUB
  chmod +x "$TMP/bin/etiquette"
  : > "$TMP/argv"
}

echo "label-reconcile-witness"

# --- 1. it calls etiquette on THIS project's repo, and applies -------------
stub_etiquette 0
REPO_URL="https://github.com/hf7y/senechal.git"
out="$(PATH="$TMP/bin:$PATH" reconcile_own_labels 2>&1)"; rc=$?
eq  "exit 0 -- a label sweep never decides a run's fate" "$rc" "0"
eq  "it reconciles ITS OWN repo, derived from REPO_URL" "$(cat "$TMP/argv")" "hf7y/senechal --apply"
has "and the removed label is reported, not swallowed" "$out" "needs-human removed"

# --- 2. an ssh remote resolves to the same slug ----------------------------
stub_etiquette 0
REPO_URL="git@github.com:hf7y/gardien.git"
PATH="$TMP/bin:$PATH" reconcile_own_labels >/dev/null 2>&1
eq "an ssh remote names the same owner/repo" "$(cat "$TMP/argv")" "hf7y/gardien --apply"

# --- 3. a remote with no tracker is SKIPPED, out loud ----------------------
# crt's REPO_URL is a bare repo local to mandark: no GitHub tracker behind it,
# so there is nothing to reconcile -- and saying nothing would read exactly
# like a successful sweep.
stub_etiquette 0
REPO_URL="/srv/git/crt.git"
out="$(PATH="$TMP/bin:$PATH" reconcile_own_labels 2>&1)"; rc=$?
eq  "a local/bare remote exits 0" "$rc" "0"
has "...and SAYS it skipped, naming the URL" "$out" "SKIPPED"
eq  "...and reaches etiquette not at all" "$(cat "$TMP/argv")" ""

# --- 4. a missing verb is a finding, not a silent no-op --------------------
REPO_URL="https://github.com/hf7y/senechal.git"
out="$(PATH="$TMP/empty" reconcile_own_labels 2>&1)"; rc=$?
eq  "no etiquette on PATH still exits 0 -- the run goes on" "$rc" "0"
has "...and says the labels were NOT reconciled" "$out" "NOT reconciled"

# --- 5. BLIND is not 'reconciled', and findings are not BLIND --------------
# etiquette exits 6 when it cannot read the grammar or the issue list. Exit 1
# is ORDINARY -- findings it cannot fix, e.g. an UNDECLARED body -- and must
# never be reported as a failure to look.
stub_etiquette 6
out="$(PATH="$TMP/bin:$PATH" reconcile_own_labels 2>&1)"; rc=$?
eq  "a BLIND etiquette still exits 0" "$rc" "0"
has "...and says so, rather than implying a sweep that did not happen" "$out" "BLIND"

stub_etiquette 1
out="$(PATH="$TMP/bin:$PATH" reconcile_own_labels 2>&1)"; rc=$?
eq    "findings (exit 1) are ordinary, not BLIND" "$rc" "0"
hasnt "...and are never reported as a failure to look" "$out" "BLIND"

# --- 6. the engine actually calls it, before the run reads its backlog -----
# The whole defect class here is a correct function nothing invokes.
CALL_LN="$(grep -n '^  reconcile_own_labels$' "$LIB" | head -1 | cut -d: -f1)"
if [ -n "$CALL_LN" ]; then
  ok "the engine calls reconcile_own_labels at line $CALL_LN"
else
  bad "reconcile_own_labels is DEFINED AND NEVER CALLED -- the exact shape it was written to end"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
