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
# HERE ONCE, NOT PER WITNESS. Since hf7y/scheduler#432 the roster carries state
# and nothing else, so `does this project run here` is answered by `getent
# passwd <project>` rather than by an `account@host` column. That puts a real
# getent on the dispatch path of every roster witness, and a witness's fixture
# projects are not accounts on whatever machine runs the suite -- so without a
# stub the whole rotation silently empties and every case passes vacuously.
#
# Says YES to any name except those in $FAKE_GETENT_FAIL -- the knob three
# witnesses already use to mean "this account is not here". It takes a
# SPACE-SEPARATED LIST now; a single name, which is how every existing caller
# sets it, is a list of one.
#
# TWO FORMS, because the witnesses reach the code two ways. Those that exec
# the script need a file on PATH; those that `eval` a function out of it run it
# IN THIS SHELL, where a shell function shadows PATH and a fakebin never would.
# Called with a dir it does both, which is always safe.
#
# CALL IT LAST, after the witness's own stubs: two `cat >` to one path is
# decided by whichever runs later, and a duplicate stub is invisible until the
# case it was meant to cover fails for the wrong reason.
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
