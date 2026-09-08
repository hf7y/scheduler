#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPO="$ROOT/bin/tempo.sh"
[ -x "$TEMPO" ] || { echo "FAIL: no tempo at $TEMPO"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

HOURS=(0.1 0.4 0.8 1.5 2.5 3.5 5.0 6.5 7.2 7.9 8.6 9.3 10.0 10.7 11.4 12.1 12.8
       14.1 14.8 15.9 17.0 18.1 19.2 20.3 21.4 23.5 25.0 27.5 30.0 32.5 35.5
       38.5 41.5 44.5 48.0 51.8 55.0 58.0 61.0 63.5 65.5 67.0 68.5 69.8 70.9
       71.8 73.0 78.0 83.0 88.0 92.0 96.0 101.0 106.3 112.0 120.0 130.0 145.0
       160.0 170.0 175.0 180.0 187.0 193.5 200.0 210.0 220.0 230.0 245.0 260.0
       279.1)

N=${#HOURS[@]}
[ "$N" -eq 71 ] \
  && ok "fixture carries n=71, matching the estate-wide sample in hf7y/scheduler#670" \
  || bad "fixture has $N entries, want 71"

SORTED="$(printf '%s\n' "${HOURS[@]}" | sort -n)"
val_at() { awk -v n="$1" 'NR==n{print; exit}' <<<"$SORTED"; }
MIN_H="$(val_at 1)"; P25_H="$(val_at 18)"; MEDIAN_H="$(val_at 36)"
P75_H="$(val_at 54)"; P90_H="$(val_at 64)"; MAX_H="$(val_at 71)"

[ "$MIN_H" = "0.1" ] && [ "$P25_H" = "14.1" ] && [ "$MEDIAN_H" = "51.8" ] \
  && [ "$P75_H" = "106.3" ] && [ "$P90_H" = "193.5" ] && [ "$MAX_H" = "279.1" ] \
  && ok "fixture reproduces min/p25/median/p75/p90/max from the #670 sample" \
  || bad "fixture drifted: min=$MIN_H p25=$P25_H median=$MEDIAN_H p75=$P75_H p90=$P90_H max=$MAX_H"

MEDIAN_MIN="$(awk -v h="$MEDIAN_H" 'BEGIN{printf "%.0f", h*60}')"
FLOOR_TARGET=$(( MEDIAN_MIN / 2 ))
FLOOR_LO=$(( FLOOR_TARGET * 80 / 100 ))
FLOOR_HI=$(( FLOOR_TARGET * 120 / 100 ))

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = closed ] && { echo 0; exit 0; }; done
printf '1\t0\n'
STUB
chmod +x "$T/bin/gh"
: > "$T/ledger.tsv"

OUT="$(PATH="$T/bin:$PATH" STATE_DIR="$T/state" RUN_LEDGER_FILE="$T/ledger.tsv" \
  TEMPO_REPO="fixture/repo" TEMPO_CACHE_MIN=0 "$TEMPO" fixture-project 2>&1)"
WANT_MIN="$(sed -n 's/.*want_min=\([0-9]*\).*/\1/p' <<<"$OUT")"

case "$WANT_MIN" in
  ''|*[!0-9]*) bad "could not read want_min from tempo.sh against the live schedule/_tempo.conf: $OUT" ;;
  *) [ "$WANT_MIN" -ge "$FLOOR_LO" ] && [ "$WANT_MIN" -le "$FLOOR_HI" ] \
       && ok "schedule/_tempo.conf's derived floor want_min=$WANT_MIN sits in [$FLOOR_LO,$FLOOR_HI] (+-20% of half the fixture median ${MEDIAN_MIN}min)" \
       || bad "schedule/_tempo.conf's derived floor want_min=$WANT_MIN is outside [$FLOOR_LO,$FLOOR_HI] -- half the measured median is ${FLOOR_TARGET}min; re-check TEMPO_BASE_MIN/TEMPO_PIVOT_ISSUES/TEMPO_MAX_MIN" ;;
esac

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
