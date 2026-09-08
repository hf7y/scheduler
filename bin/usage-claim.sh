#!/usr/bin/env bash
set -uo pipefail  # human CLI for lib/usage-claim.sh, hf7y/scheduler#339

SELF_REAL="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"; [ -n "$SELF_REAL" ] || SELF_REAL="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF_REAL")" && pwd)"
[ -r "$SELF_DIR/../lib/usage-claim.sh" ] || { echo "usage-claim.sh: cannot find $SELF_DIR/../lib/usage-claim.sh" >&2; exit 2; }
. "$SELF_DIR/../lib/usage-claim.sh"

usage() {
  cat <<'EOF'
usage: usage-claim.sh status
       usage-claim.sh hold <label> -- <command...>

status          0=held (prints who/since), 1=free
hold <label>    runs <command...> with the claim held for its exact
                lifetime; usage-gate.sh HOLDs every account while it runs.
                Refuses (3) if another process already holds it.
EOF
}

case "${1:-}" in
  status) usage_claim_status; exit $? ;;
  hold)
    shift
    [ $# -ge 1 ] || { usage >&2; exit 2; }
    label="$1"; shift
    usage_claim_hold "$label" "$@"
    exit $?
    ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
