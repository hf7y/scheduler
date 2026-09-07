#!/usr/bin/env bash
# claim-agreement-witness.sh -- tempo.sh and next-issue.sh must agree on what
# counts as CLAIMED (#663): two independent jq predicates over one field, so
# drift brakes the pacer for an issue the picker still hands out and nothing
# else looks. Same shape as tests/paced-conf-witness.sh. HERMETIC -- one fake
# gh, one fixture, and each script's OWN filter run against it.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
TEMPO="$PWD/bin/tempo.sh"; NEXT="$PWD/bin/next-issue.sh"

echo "claim-agreement-witness"
for t in "$TEMPO" "$NEXT"; do
  [ -x "$t" ] || { echo "  FAIL: $t missing or not executable"; echo "claim-agreement-witness: 0 passed, 1 failed"; exit 1; }
done

T="$(mktemp -d)" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
FIXTURE="$T/issues.json"

cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = closed ] && { echo 5; exit 0; }; done
prev=''
for a in "$@"; do
  [ "$prev" = --jq ] && { jq -r "$a" "$GH_FIXTURE"; exit 0; }   # tempo's own filter
  prev="$a"
done
case "$1 $2" in
  "issue list") cat "$GH_FIXTURE"; exit 0 ;;                    # next-issue parses it itself
esac
exit 1
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_FIXTURE="$FIXTURE"
export STATE_DIR="$T/state" RUN_LEDGER_FILE="$T/ledger.tsv" TEMPO_REPO="fake/repo"

# No labels anywhere: the assignee is then the only thing that can block, which
# is what makes the two counts comparable.
write_fixture() { printf '%s\n' "$1" > "$FIXTURE"; rm -f "$STATE_DIR"/tempo-*.count; }

tempo_field() { sed -n "s/.*$1=\([0-9]*\).*/\1/p" <<<"$2" | head -1; }

check() {  # <label> <want_actionable> <want_claimed> <want_eligible_numbers>
  local label="$1" want_a="$2" want_c="$3" want_nums="$4" tout nout nerr nums claimed
  tout="$(TEMPO_CACHE_MIN=0 "$TEMPO" p 2>&1)"
  nout="$("$NEXT" fake/repo --limit 50 2>"$T/err")"; nerr="$(cat "$T/err")"
  nums="$(grep -oE '^#[0-9]+' <<<"$nout" | tr -d '#' | tr '\n' ',' | sed 's/,$//')"
  claimed="$(grep -c 'claimed by' <<<"$nerr")"
  local a b
  a="$(tempo_field actionable "$tout")"; b="$(tempo_field blocked "$tout")"
  if [ "$a" = "$want_a" ] && [ "$b" = "$want_c" ] && [ "$nums" = "$want_nums" ] && [ "$claimed" = "$want_c" ]; then
    ok "$label -- tempo actionable=$a blocked=$b, next-issue eligible {$nums} claimed=$claimed"
  else
    bad "$label -- tempo actionable=$a blocked=$b (want $want_a/$want_c); next-issue {$nums} claimed=$claimed (want {$want_nums}/$want_c)"
  fi
}

write_fixture '[
  {"number":10,"title":"unassigned","createdAt":"2026-08-01T00:00:00Z","body":"","labels":[],"assignees":[]},
  {"number":11,"title":"assigned","createdAt":"2026-08-02T00:00:00Z","body":"","labels":[],"assignees":[{"login":"hf7y"}]},
  {"number":12,"title":"empty list","createdAt":"2026-08-03T00:00:00Z","body":"","labels":[],"assignees":[]},
  {"number":13,"title":"assigned to another","createdAt":"2026-08-04T00:00:00Z","body":"","labels":[],"assignees":[{"login":"someone-else"}]}
]'
check "a claim brakes the pacer and hides the row from the picker" 2 2 "10,12"

# The all-claimed end: if one predicate stops reading the field, one number
# moves and the other does not. Mutation-tested both directions.
write_fixture '[
  {"number":20,"title":"a","createdAt":"2026-08-01T00:00:00Z","body":"","labels":[],"assignees":[{"login":"hf7y"}]},
  {"number":21,"title":"b","createdAt":"2026-08-02T00:00:00Z","body":"","labels":[],"assignees":[{"login":"hf7y"}]}
]'
check "every issue claimed: nothing paces, nothing is suggested" 0 2 ""

echo "claim-agreement-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
