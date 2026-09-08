#!/usr/bin/env bash
# Shared PASS/FAIL witness counters, sourced by tests/*-witness.sh.
# See hf7y/scheduler#210: 51 files each defined their own ok()/bad(),
# already diverged into 6 distinct signatures before anything noticed.
PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS: %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$*"; }

# witness_stub_getent <fakebin-dir> -- "which accounts exist on this box?"
#
# HERE ONCE. Since #432 "does this project run here" is `getent passwd
# <project>`, so a real getent sits on every roster witness's dispatch path --
# and fixture projects are not accounts on the suite's host, so without a stub
# the rotation empties and every case passes VACUOUSLY.
#
# Says YES except to names in $FAKE_GETENT_FAIL (now a space-separated list).
# TWO FORMS: a file on PATH for witnesses that exec the script, a shell
# function for those that eval a function out of it. CALL IT LAST -- a second
# `cat >` to one path silently wins.
witness_stub_getent() {
  local bin="${1:-}"
  if [ -n "$bin" ]; then
    cat > "$bin/getent" <<'WITNESS_GETENT'
#!/usr/bin/env bash
[ "${1:-}" = passwd ] && [ -n "${2:-}" ] || exit 2
for _n in ${FAKE_GETENT_FAIL:-}; do [ "$2" = "$_n" ] && exit 2; done
printf '%s:x:9999:9999::/home/%s:/bin/bash\n' "$2" "$2"
WITNESS_GETENT
    chmod +x "$bin/getent"
  fi
  # shellcheck disable=SC2317  # called indirectly, by the code under test
  getent() {
    [ "${1:-}" = passwd ] && [ -n "${2:-}" ] || return 2
    local _n; for _n in ${FAKE_GETENT_FAIL:-}; do [ "$2" = "$_n" ] && return 2; done
    printf '%s:x:9999:9999::/home/%s:/bin/bash\n' "$2" "$2"
  }
}
