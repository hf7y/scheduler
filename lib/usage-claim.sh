#!/usr/bin/env bash
: "${USAGE_CLAIM_DIR:=}"  # a hand-spawned run's claim on the shared quota window; flock, not ROSTER/pid-file -- rationale in PR body, hf7y/scheduler#339
if [ -z "$USAGE_CLAIM_DIR" ]; then
  USAGE_CLAIM_DIR="/var/lib/scheduler-usage-claim"
  mkdir -p "$USAGE_CLAIM_DIR" 2>/dev/null
  [ -w "$USAGE_CLAIM_DIR" ] || USAGE_CLAIM_DIR="$HOME/.local/share/scheduler-usage-claim"
fi
USAGE_CLAIM_LOCK="$USAGE_CLAIM_DIR/claim.lock"
USAGE_CLAIM_MARKER="$USAGE_CLAIM_DIR/claim.active"

usage_claim_status() {  # 0 held (prints marker), 1 free; sweeps a dead holder's marker
  command -v flock >/dev/null 2>&1 || { echo "free"; return 1; }
  [ -d "$USAGE_CLAIM_DIR" ] || { echo "free"; return 1; }
  if flock -n "$USAGE_CLAIM_LOCK" -c true 2>/dev/null; then
    rm -f "$USAGE_CLAIM_MARKER" 2>/dev/null
    echo "free"
    return 1
  fi
  echo "held $(cat "$USAGE_CLAIM_MARKER" 2>/dev/null || echo '(no marker)')"
  return 0
}

usage_claim_acquire() {  # <label> -- via an exec'd fd in THIS process; 0 acquired, 3 held, 2 could-not-try
  command -v flock >/dev/null 2>&1 || return 2
  mkdir -p "$USAGE_CLAIM_DIR" 2>/dev/null || return 2
  exec 209>"$USAGE_CLAIM_LOCK" || return 2
  flock -n 209 || return 3
  printf 'label=%s pid=%s started_at=%s host=%s\n' \
    "${1:-claim}" "$$" "$(date -Is)" "$(hostname -s 2>/dev/null || echo unknown)" \
    > "$USAGE_CLAIM_MARKER" 2>/dev/null
  return 0
}

usage_claim_release() {  # cosmetic only -- a crash releases fd 209 without this ever running
  rm -f "$USAGE_CLAIM_MARKER" 2>/dev/null
  flock -u 209 2>/dev/null
  return 0
}

usage_claim_hold() {  # <label> -- <command...>: acquire/run/release, propagate exit; 3 if already held
  local label="$1"; shift
  [ "${1:-}" = "--" ] && shift
  usage_claim_acquire "$label"
  local arc=$?
  [ "$arc" -eq 3 ] && { echo "REFUSED: quota claim already held -- $(usage_claim_status)" >&2; return 3; }
  [ "$arc" -eq 0 ] || return "$arc"
  "$@"; local rc=$?
  usage_claim_release
  return $rc
}
