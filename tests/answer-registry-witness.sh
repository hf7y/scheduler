#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"
echo "answer-registry-witness"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export ANSWER_REGISTRY_FILE="$W/registry.tsv"
. "$HERE/../lib/answer-registry.sh"

[ ! -e "$ANSWER_REGISTRY_FILE" ] && ok "sourcing the library creates nothing" \
  || bad "sourcing wrote a file -- a library must not act"

( real="$HOME/.local/share/scheduler-answers/registry.tsv"
  had=no; [ -e "$real" ] && had=yes
  bash -c ". '$HERE/../lib/answer-registry.sh'; export ANSWER_REGISTRY_FILE='$W/late.tsv'; answer_registry_record proj 1 relay hi" 2>/dev/null
  [ -s "$W/late.tsv" ] || { echo FAILLATE; exit 0; }
  now=no; [ -e "$real" ] && now=yes
  [ "$had" = "$now" ] || { echo FAILREAL; exit 0; }
  echo OKLATE ) > "$W/late.res" 2>/dev/null
case "$(cat "$W/late.res" 2>/dev/null)" in
  OKLATE)   ok "ANSWER_REGISTRY_FILE export is honoured, and the real registry is untouched" ;;
  FAILLATE) bad "exporting ANSWER_REGISTRY_FILE after sourcing had no effect -- writes go to the default" ;;
  FAILREAL) bad "the test wrote to the REAL registry -- isolation is broken" ;;
  *)        bad "the per-call resolution check did not run" ;;
esac

answer_registry_record proj 10 relay "first answer"
answer_registry_record proj 11 relay "second answer"
n=$(grep -c . "$ANSWER_REGISTRY_FILE")
[ "$n" -eq 2 ] && ok "two records produce two rows" || bad "expected 2 rows, got $n"
first="$(head -1 "$ANSWER_REGISTRY_FILE")"
answer_registry_record proj 10 relay "again"
[ "$(head -1 "$ANSWER_REGISTRY_FILE")" = "$first" ] && ok "the first row is untouched by a later record" \
  || bad "an earlier row changed -- this is not append-only"

before=$(grep -c . "$ANSWER_REGISTRY_FILE")
answer_registry_record proj 12 relay "$(printf 'line one\twith a tab\nline two')"
after=$(grep -c . "$ANSWER_REGISTRY_FILE")
[ $((after - before)) -eq 1 ] && ok "a multi-line, tab-carrying answer still writes exactly one row" \
  || bad "a hostile answer wrote $((after-before)) rows"

export ANSWER_REGISTRY_FILE="$W/proj.tsv"
answer_registry_record alpha 1 relay "alpha's answer"
answer_registry_record beta 2 relay "beta's answer"
got="$(answer_registry_unread alpha '')"
echo "$got" | grep -q "alpha's answer" && ok "unread(alpha) sees alpha's row" || bad "missing alpha's row: [$got]"
echo "$got" | grep -q "beta's answer" && bad "unread(alpha) leaked beta's row" || ok "unread(alpha) does not see beta's row"

export ANSWER_REGISTRY_FILE="$W/since.tsv"
printf '2026-01-01T00:00:00-00:00\tp\t1\trelay\told answer\n' >> "$ANSWER_REGISTRY_FILE"
printf '2026-06-01T00:00:00-00:00\tp\t2\trelay\tnew answer\n' >> "$ANSWER_REGISTRY_FILE"
got="$(answer_registry_unread p '2026-03-01T00:00:00-00:00')"
echo "$got" | grep -q "old answer" && bad "a row older than 'since' was returned" || ok "a row older than 'since' is excluded"
echo "$got" | grep -q "new answer" && ok "a row newer than 'since' is returned" || bad "missing the newer row: [$got]"
got="$(answer_registry_unread p '2026-01-01T00:00:00-00:00')"
echo "$got" | grep -q "old answer" && bad "'since' is not exclusive -- a row stamped exactly at the cutoff was returned" \
  || ok "'since' is exclusive: a row stamped exactly at the cutoff is not re-delivered"

got="$(answer_registry_unread p '')"
n=$(echo "$got" | grep -c .)
[ "$n" -eq 2 ] && ok "empty 'since' returns every row for the project" || bad "expected 2 rows with empty since, got $n: [$got]"

export ANSWER_REGISTRY_FILE="$W/nope.tsv"
got="$(answer_registry_unread ghost '' 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$got" ] && ok "no registry file yet -- unread prints nothing and exits 0" \
  || bad "expected empty output and rc=0, got rc=$rc out=[$got]"

export ANSWER_REGISTRY_FILE="$W/marker.tsv"
answer_registry_record p 1 "" "no marker given"
got="$(answer_registry_unread p '')"
echo "$got" | grep -qP '\trelay\t' && ok "an empty marker defaults to 'relay'" || bad "marker did not default: [$got]"

export ANSWER_REGISTRY_FILE="$W/roundtrip.tsv"
answer_registry_record p 9 relay "$(printf 'line one\nline two\tindented')"
row="$(answer_registry_unread p '')"
text_field="$(printf '%s' "$row" | cut -f4-)"
rendered="$(printf '%b' "$text_field")"
expected="$(printf 'line one\nline two\tindented')"
[ "$rendered" = "$expected" ] && ok "the recorded text round-trips through printf '%b'" \
  || bad "round-trip failed: got [$rendered] want [$expected]"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
