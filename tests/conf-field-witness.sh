#!/usr/bin/env bash
# Witness for "does a conf mean the same path to every reader?"
#
# THE BUG THIS RETIRES (2026-08-03, live, and it broke the front door):
# schedule/*.conf has TWO kinds of reader and they disagreed.
#
#   sourced   bin/sync-crontab.sh, bin/scheduler-run
#             PROJECT_REPO_PATH="$HOME/Documents/Projects/senechal" -> expands
#   grepped   bin/scheduler's conf_field(): grep | cut | tr -d '"'
#             the SAME line -> the literal characters $HOME/Documents/...
#
# Every caller of conf_field treats the result as a real path, so
# `scheduler -i senechal` -- the ecosystem's front door, and what
# notify-senechal files through -- refused with:
#
#   scheduler: senechal's PROJECT_REPO_PATH does not exist on this host:
#   $HOME/Documents/Projects/senechal
#
# The portability pass that introduced it verified the sourced readers and
# never ran a text reader, and its witness asserted only "no conf hardcodes
# /home/" -- a test that passes while the feature is broken.
#
# What must hold:
#   1. a $HOME-relative PROJECT_REPO_PATH resolves to a real absolute path
#   2. ${HOME} and ~ resolve too (the other two portable leading forms)
#   3. an ALREADY-absolute path is returned unchanged (no regression)
#   4. conf_field does not EVAL: a conf carrying a command substitution comes
#      back as inert text, because this reader must never execute conf content
#   5. every SHIPPED project conf resolves to an absolute path -- the check
#      that would actually have caught the outage, run against real confs
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHED="$ROOT/bin/scheduler"
[ -f "$SCHED" ] || { echo "script under test not found: $SCHED"; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Extract the real conf_field from the script under test and run it in
# isolation. Sourcing bin/scheduler wholesale would execute its dispatch; this
# takes the actual function body so the test cannot drift from the source.
sed -n '/^conf_field() {/,/^}/p' "$SCHED" > "$TMP/conf_field.sh"
[ -s "$TMP/conf_field.sh" ] || { echo "could not extract conf_field from $SCHED"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/conf_field.sh"

SCHED_ROOT="$TMP/fixture"; mkdir -p "$SCHED_ROOT/schedule"
mk() { printf 'PROJECT="%s"\nPROJECT_REPO_PATH="%s"\n' "$1" "$2" > "$SCHED_ROOT/schedule/$1.conf"; }

echo "== a conf means the same path to every reader"
mk homerel '$HOME/Documents/Projects/thing'
got="$(conf_field homerel PROJECT_REPO_PATH)"
[ "$got" = "$HOME/Documents/Projects/thing" ] \
  && ok "\$HOME-relative resolves to an absolute path" \
  || bad "\$HOME-relative did not expand (got: $got)"

mk braced '${HOME}/Documents/Projects/thing'
got="$(conf_field braced PROJECT_REPO_PATH)"
[ "$got" = "$HOME/Documents/Projects/thing" ] \
  && ok "\${HOME}-relative resolves" || bad "\${HOME} did not expand (got: $got)"

mk tilde '~/Documents/Projects/thing'
got="$(conf_field tilde PROJECT_REPO_PATH)"
[ "$got" = "$HOME/Documents/Projects/thing" ] \
  && ok "~-relative resolves" || bad "~ did not expand (got: $got)"

echo "== and an absolute path still means exactly itself"
mk abs '/srv/elsewhere/thing'
got="$(conf_field abs PROJECT_REPO_PATH)"
[ "$got" = "/srv/elsewhere/thing" ] \
  && ok "an absolute path is unchanged" || bad "an absolute path was rewritten (got: $got)"

echo "== expansion is not evaluation"
# A conf is data. If this reader ever ran conf content, a conf would be a
# remote-code path into every caller of conf_field.
mk evil '$(touch '"$TMP"'/PWNED)/x'
got="$(conf_field evil PROJECT_REPO_PATH)"
[ -e "$TMP/PWNED" ] && bad "conf_field EXECUTED a command substitution from a conf" \
                    || ok "a command substitution in a conf is inert text"
case "$got" in *'$('*) ok "the unexpanded text is returned as-is" ;;
                     *) bad "command substitution was altered unexpectedly (got: $got)" ;; esac

echo "== every SHIPPED project conf resolves to an absolute path"
# The check that would actually have caught the outage: run the real reader
# against the real confs, and require a usable path out.
SCHED_ROOT="$ROOT"
shopt -s nullglob
for c in "$ROOT"/schedule/*.conf; do
  b="$(basename "$c" .conf)"
  case "$b" in _*) continue ;; esac          # meta confs have no project path
  grep -qE '^PROJECT_REPO_PATH=' "$c" || continue
  got="$(conf_field "$b" PROJECT_REPO_PATH)"
  case "$got" in
    /*) ok "$b -> $got" ;;
    *)  bad "$b did not resolve to an absolute path (got: $got) -- every conf_field caller treats this as a real path" ;;
  esac
done

echo
echo "conf-field witness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
