#!/usr/bin/env bash
# lib/provision-set.sh -- the ordered set of scripts that stand a self-dev host,
# or one account on it, up. bin/dresse.sh runs them; this says which they are.
#
# It was realisateur's PROP_PROVISION_SCRIPTS until 2026-08-26. The other half
# of that file -- bootstrap/payload/local, how a file REACHES a host -- stayed
# there, because that is the verb build's question and this is not.
#
# TRAP: the set must match dresse's step plan in BOTH directions. A step naming
#   an undeclared script, and a script here absent from the plan, are both
#   findings. dresse --check asserts it; tests/dresse.test.sh asserts that.
# TRAP: wire-release-channel.sh is a row and this repo does NOT hold it. It is
#   realisateur's -- it installs /usr/local/libexec/selfdev, and the set it
#   installs includes realisateur's own ausculte probes. dresse still runs it,
#   because on a provisioned host dresse runs FROM that libexec directory where
#   both repos' tools sit side by side.
# TRAP: PROVISION_HOST_PIN must equal realisateur's PROP_HOST_PIN -- two repos,
#   one path. bin/selfdev-hooks-provision.sh reads it to find the hook file the
#   verb build ships.
PROVISION_HOST_PIN="${VERB_HOST_BUILD_ROOT:-/usr/local/share/verb-builds}/current"

PROVISION_SCRIPTS="
dresse.sh
land-selfdev.sh
provision-selfdev-user.sh
setup-selfdev-project.sh
enrole-selfdev.sh
wire-selfdev-git.sh
wire-release-channel.sh
selfdev-app-key.sh
selfdev-claude-token.sh
selfdev-permissions-provision.sh
selfdev-hooks-provision.sh
vault-group-provision.sh
"

# provision_channel <script> -- `provision`, or nothing (rc 1). rc 1 is a
# FINDING: the step plan named something no set declares.
provision_channel() {
  local n="$1" s
  for s in $PROVISION_SCRIPTS; do [ "$s" = "$n" ] && { echo provision; return 0; }; done
  return 1
}
