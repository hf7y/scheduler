#!/usr/bin/env bash
# Witness for lib/sweep-loop-common.sh's apply_decision_defaults().
#
# WHY IT EXISTS. Measured across hf7y 2026-08-22: 36 open `needs-human`
# issues. Each subtracts from its repo's `actionable` count in bin/tempo.sh, so
# an unanswered question is ALSO A BRAKE ON THE REPO THAT ASKED IT. #262 named
# it: the only brake in the whole loop was a person's attention, "which is why
# the estate could not be left alone."
#
# The assertions are about RESTRAINT as much as action. A default engine that
# fires early, fires on a decision that declared none, or fires when it could
# not read the grammar is worse than no engine: it converts "waiting on a
# human" into "silently decided", which is the one outcome nobody could audit.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/sweep-loop-common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- no [$3] in: $2" ;; esac; }

awk '/^own_repo_slug\(\) \{$/,/^\}$/'          "$LIB" >  "$TMP/fn.sh"
awk '/^apply_decision_defaults\(\) \{$/,/^\}$/' "$LIB" >> "$TMP/fn.sh"
grep -q 'default-after' "$TMP/fn.sh" \
  || { echo "FAIL: could not extract apply_decision_defaults() from $LIB"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/fn.sh"

mkdir -p "$TMP/bin" "$TMP/empty"
# One stub answers every gh call this function makes, and records the writes.
# AGE and DEFAULT are the fixture knobs.
mk_gh() { # <days-old> <default-line> <default-after-rc> [<labels-csv>]
  local labels="${4:-}"
  cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --default-after) printf '$2'; exit $3 ;;
esac
case "\$1 \$2" in
  "issue list")  printf '7\t%s\t$labels\n' "\$(date -u -d '-$1 days' +%Y-%m-%dT%H:%M:%SZ)"; exit 0 ;;
  "issue view")  printf 'DECISION: @zach -- q\n'; exit 0 ;;
  "issue comment") printf '%s\n' "COMMENT \$*" >> "$TMP/writes"; exit 0 ;;
  "issue edit")    printf '%s\n' "EDIT \$*"    >> "$TMP/writes"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$TMP/bin/gh"; : > "$TMP/writes"
}
run() { OUT="$(PATH="$TMP/bin:$PATH" REPO_URL="https://github.com/hf7y/senechal.git" \
               apply_decision_defaults 2>&1)"; RC=$?; }

echo "decision-default-witness"

# --- 1. past its window, it acts -- and only comments and relabels ----------
mk_gh 20 '14\tclose it as declined' 0
run
eq  "exit 0" "$RC" "0"
has "it says which issue proceeded, and after how long" "$OUT" "#7 proceeded on its 14d default after 20d"
has "it COMMENTS the default rather than doing the work" "$(cat "$TMP/writes")" "COMMENT issue comment 7"
has "...and the comment quotes the declared action" "$(cat "$TMP/writes")" "close it as declined"
has "it drops needs-human, so the repo unbrakes" "$(cat "$TMP/writes")" "--remove-label needs-human"
has "...and labels it defaulted, so the act is visible" "$(cat "$TMP/writes")" "--add-label defaulted"
# ONE REQUEST WOULD LOSE THE LOAD-BEARING HALF. `gh issue edit --remove-label X
# --add-label Y` is a single call; if Y is not provisioned in that repo GitHub
# rejects the whole request and X survives -- so the brake stays on, silently,
# on exactly the repos that never got the label. Drop first, alone.
case "$(grep -c 'issue edit' "$TMP/writes")" in
  2) ok "the label change is TWO requests, so a missing 'defaulted' cannot strand needs-human" ;;
  *) bad "two separate issue-edit calls" "got $(grep -c 'issue edit' "$TMP/writes")" ;;
esac
first_edit="$(grep -m1 'issue edit' "$TMP/writes")"
case "$first_edit" in
  *--remove-label*) ok "...and the REMOVE goes first, because that is the half that unbrakes the repo" ;;
  *) bad "remove-label is the first edit" "got: $first_edit" ;;
esac
# The issue must NOT be closed: reversibility is the whole basis of the default.
case "$(cat "$TMP/writes")" in
  *"issue close"*) bad "the issue stays OPEN so Zach can reverse it -- it was closed" ;;
  *) ok "the issue stays OPEN, which is what makes the default reversible" ;;
esac

# --- 1b. already defaulted -- it does NOT re-fire ---------------------------
# needs-human is DERIVED: etiquette --apply (run immediately before this
# function in the dispatch path) reasserts it every tick straight from the
# body's still-open DECISION line, so an issue that already proceeded on its
# default reappears in this SAME --label needs-human query on the very next
# tick even though nothing changed. Without checking for `defaulted` this
# fires again, and again, forever -- measured as 6 duplicate comments in
# under 12h on hf7y/baudin#29 before this test existed.
mk_gh 20 '14\tclose it as declined' 0 'needs-human,defaulted'
run
eq "an issue already labelled defaulted is skipped, not re-defaulted" "$(cat "$TMP/writes")" ""
eq "...and it still exits 0" "$RC" "0"

# --- 2. inside its window, it does NOTHING ---------------------------------
mk_gh 3 '14\tclose it as declined' 0
run
eq "3 days into a 14d window, nothing is written" "$(cat "$TMP/writes")" ""
eq "...and it still exits 0" "$RC" "0"

# --- 3. a decision that declared NO default blocks forever, on purpose -----
# gh --default-after exits 1 for this. It is the correct outcome for an
# irreversible call, and firing here would be the worst possible bug.
mk_gh 400 '' 1
run
eq "no DEFAULT-AFTER means nothing is written, even 400 days later" "$(cat "$TMP/writes")" ""

# --- 4. BLIND is not consent ----------------------------------------------
# exit 6 = the grammar could not be read. Treating that as "no default" would
# be right by accident; treating it as "act" would decide for a human on the
# strength of a failed read. Neither may write.
mk_gh 400 '' 6
run
eq "a BLIND grammar read writes nothing -- could-not-look is not permission" "$(cat "$TMP/writes")" ""

# --- 5. own repo only, and never fatal ------------------------------------
OUT="$(PATH="$TMP/bin:$PATH" REPO_URL="/srv/git/crt.git" apply_decision_defaults 2>&1)"; RC=$?
eq  "a bare local remote exits 0" "$RC" "0"
has "...and SAYS it skipped, rather than reading as a clean sweep" "$OUT" "SKIPPED"
OUT="$(PATH="$TMP/empty" REPO_URL="https://github.com/hf7y/senechal.git" apply_decision_defaults 2>&1)"; RC=$?
eq  "no gh on PATH exits 0 -- the run goes on" "$RC" "0"
has "...and says so" "$OUT" "SKIPPED"

# --- 6. the engine actually runs at dispatch ------------------------------
if grep -q '^  apply_decision_defaults$' "$LIB"; then
  ok "the engine is CALLED in the dispatch path"
else
  bad "apply_decision_defaults is defined and never called -- the defect shape this session kept finding"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
