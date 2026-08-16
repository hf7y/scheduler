#!/usr/bin/env bash
# Witness for the free-probe fallback in bin/usage-gate.sh (hf7y/scheduler#133).
#
# GET /api/oauth/usage is free but 403s for a `claude setup-token` credential
# -- confirmed live 2026-08-13 against a real monkey self-dev token. #110
# made that endpoint the ONLY probe and it 403'd on every such account at
# once, holding ALL self-dev dispatch (ERROR is HOLD by design) until #132
# reverted it. This witness proves the fallback this time degrades safely:
# free is tried first, but anything short of a clean 200 with a parseable
# body -- 403, 429, or an unrecognised 200 shape -- falls straight through to
# the paid probe that was already working, in exactly one call per tick.
#
# Hermetic: a fake curl on PATH speaks for both api.anthropic.com endpoints,
# keyed off the URL. Never touches the live estate or a real token.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/bin/usage-gate.sh"
[ -x "$GATE" ] || { echo "not found or not executable: $GATE"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

echo "usage-gate-free-probe-witness"

WORK="$(mktemp -d)" || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/curl" <<'EOF'
#!/usr/bin/env bash
url=""; outfile=""; hdrfile=""; prev=""
for a in "$@"; do
  case "$a" in https://*) url="$a" ;; esac
  [ "$prev" = "-o" ] && outfile="$a"
  [ "$prev" = "-D" ] && hdrfile="$a"
  prev="$a"
done
case "$url" in
  *oauth/usage*)
    [ -n "$outfile" ] && printf '%s' "${FAKE_FREE_BODY:-}" > "$outfile"
    printf '%s' "${FAKE_FREE_CODE:-200}"
    ;;
  *v1/messages*)
    if [ "${FAKE_PAID_SHOULD_NOT_BE_CALLED:-0}" = "1" ]; then
      echo "fake curl: paid probe called when it must not be" >&2
      exit 9
    fi
    [ -n "${FAKE_PAID_CALL_LOG:-}" ] && echo "call" >> "$FAKE_PAID_CALL_LOG"
    [ -n "$hdrfile" ] && printf '%s' "${FAKE_PAID_HEADERS:-}" > "$hdrfile"
    printf '%s' "${FAKE_PAID_CODE:-200}"
    ;;
  *)
    echo "fake curl: unexpected url: $url" >&2; exit 2 ;;
esac
EOF
chmod +x "$FAKEBIN/curl"

FAKEHOME="$WORK/home"; mkdir -p "$FAKEHOME/.claude"
cat > "$FAKEHOME/.claude/settings.json" <<'EOF'
{"env":{"CLAUDE_CODE_OAUTH_TOKEN":"sk-ant-oat01-fake-token-for-tests"}}
EOF

EMPTYCONF="$WORK/emptyconf"; mkdir -p "$EMPTYCONF"

run_gate() {
  PATH="$FAKEBIN:$PATH" HOME="$FAKEHOME" USAGE_CONF_DIR="$EMPTYCONF" \
    USAGE_GATE_QUIET=0 "$GATE"
}

# --- 1. free 200, well-formed body -> used directly, paid never called -----
FAKE_FREE_CODE=200
FAKE_FREE_BODY='{"five_hour":{"utilization":7.0,"resets_at":"2026-08-12T06:00:00Z"},"seven_day":{"utilization":39.0,"resets_at":"2026-08-19T00:00:00Z"}}'
FAKE_PAID_SHOULD_NOT_BE_CALLED=1
out="$(FAKE_FREE_CODE="$FAKE_FREE_CODE" FAKE_FREE_BODY="$FAKE_FREE_BODY" \
       FAKE_PAID_SHOULD_NOT_BE_CALLED="$FAKE_PAID_SHOULD_NOT_BE_CALLED" run_gate)"; rc=$?
case "$out" in *"probe:oauth-usage,"*|*"probe:oauth-usage"$'\n'*) ok "1a free 200 is used (probe:oauth-usage)" ;; *) bad "1a probe tag missing: $out" ;; esac
case "$out" in *"http_code=200"*) ok "1b http_code is the free probe's 200" ;; *) bad "1b http_code wrong: $out" ;; esac
[ "$rc" -le 1 ] && ok "1c exits RUN or HOLD, not ERROR (rc=$rc)" || bad "1c exited ERROR (rc=$rc): $out"
case "$out" in *"window=5h util=0.070"*) ok "1d 7.0 (percent) normalised to 0.070 (fraction)" ;; *) bad "1d utilization not normalised: $out" ;; esac

# --- 2. free 403 (setup-token shape) -> falls through to paid --------------
out="$(FAKE_FREE_CODE=403 FAKE_FREE_BODY='{"type":"error"}' \
       FAKE_PAID_CODE=200 \
       FAKE_PAID_HEADERS=$'anthropic-ratelimit-unified-5h-utilization: 0.19\r\nanthropic-ratelimit-unified-5h-reset: 9999999999\r\nanthropic-ratelimit-unified-7d-utilization: 0.39\r\nanthropic-ratelimit-unified-7d-reset: 9999999999\r\n' \
       run_gate)"; rc=$?
case "$out" in *"probe:paid-fallback(free:403)"*) ok "2a 403 falls back to paid, tagged in probe" ;; *) bad "2a no fallback tag: $out" ;; esac
[ "$rc" -le 1 ] && ok "2b fallback still reaches a verdict (rc=$rc)" || bad "2b fallback errored (rc=$rc): $out"

# --- 3. free 429 -> falls through to paid, in exactly ONE call --------------
# The free endpoint rate-limits independently of account quota, so a 429 there
# says nothing about whether there is quota to dispatch on. Walling it off from
# the fallback held realisateur/ecosim/vim-arcade for 14h on 2026-08-13 with
# quota to spare. It now costs one paid call and yields a real verdict.
CALLS="$WORK/paid-calls"; : > "$CALLS"
out="$(FAKE_FREE_CODE=429 FAKE_FREE_BODY='{}' \
       FAKE_PAID_CODE=200 FAKE_PAID_CALL_LOG="$CALLS" \
       FAKE_PAID_HEADERS=$'anthropic-ratelimit-unified-5h-utilization: 0.19\r\nanthropic-ratelimit-unified-5h-reset: 9999999999\r\nanthropic-ratelimit-unified-7d-utilization: 0.39\r\nanthropic-ratelimit-unified-7d-reset: 9999999999\r\n' \
       run_gate)"; rc=$?
[ "$rc" -le 1 ] && ok "3a 429 reaches a real verdict, not ERROR (rc=$rc)" || bad "3a 429 still errors (rc=$rc): $out"
case "$out" in *"probe:paid-fallback(free:429)"*) ok "3b probe tag names the fallback and the 429 that caused it" ;; *) bad "3b probe tag missing: $out" ;; esac
case "$out" in *"http_code=200"*) ok "3c http_code is the paid probe's, not the free 429" ;; *) bad "3c http_code wrong: $out" ;; esac
n="$(wc -l < "$CALLS")"
[ "$n" -eq 1 ] && ok "3d exactly one paid call per tick (n=$n)" || bad "3d paid probe called $n times, want 1: $out"

# --- 4. free 200 but a body that doesn't parse -> falls through to paid ----
out="$(FAKE_FREE_CODE=200 FAKE_FREE_BODY='{"unexpected":"shape"}' \
       FAKE_PAID_CODE=200 \
       FAKE_PAID_HEADERS=$'anthropic-ratelimit-unified-5h-utilization: 0.10\r\nanthropic-ratelimit-unified-5h-reset: 9999999999\r\nanthropic-ratelimit-unified-7d-utilization: 0.20\r\nanthropic-ratelimit-unified-7d-reset: 9999999999\r\n' \
       run_gate)"; rc=$?
case "$out" in *"probe:paid-fallback(free:200)"*) ok "4a unparseable 200 body falls back to paid rather than guessing" ;; *) bad "4a no fallback on bad shape: $out" ;; esac
[ "$rc" -le 1 ] && ok "4b fallback still reaches a verdict (rc=$rc)" || bad "4b errored (rc=$rc): $out"

echo
echo "usage-gate-free-probe-witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
