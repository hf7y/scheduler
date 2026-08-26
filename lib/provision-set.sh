#!/usr/bin/env bash
# lib/provision-set.sh -- the provisioning set, in ONE place.
#
# WHAT THIS IS. The ordered set of scripts that stand a self-dev host, or one
# account on it, up. `bin/dresse.sh` runs them; this file says which they are,
# so a typed list in the runner cannot go stale in silence against the tree.
#
# WHY IT IS HERE AND NOT IN realisateur. It used to be one half of that repo's
# bin/lib/propagation-set.sh, whose other half describes the VERB BUILD's own
# channel -- bootstrap, payload, local. Those are two different questions:
# "how does a file reach a host" is realisateur's, because realisateur cuts
# the build; "what does standing an account up consist of" is this repo's,
# because this repo owns arming, ROSTER and dispatch. Keeping both in one file
# in one repo is what made the provisioning block un-moveable for nine days
# (realisateur#368).
#
# THE SET MUST MATCH bin/dresse.sh's step plan, in both directions: a step
# naming a script absent here, and a script here absent from the plan, are
# both findings. dresse --check asserts it, and tests/dresse.test.sh asserts
# that dresse asserts it.
#
# ONE ROW NAMES A FILE THIS REPO DOES NOT HOLD, and that is deliberate rather
# than an oversight. `wire-release-channel.sh` is realisateur's: it installs
# /usr/local/libexec/selfdev, and the set it installs includes realisateur's
# OWN ausculte probes (ausculte-cadence.sh, dexter-liveness.sh,
# decision-rot.sh), which is a fact about the verb build and not about
# provisioning. It stays there.
#
# dresse still runs it, because on a provisioned host dresse runs FROM that
# same libexec directory, where both repos' tools sit side by side. This set
# says which steps the plan consists of; it does not claim to own every file
# named. What it must never do is omit a step -- an undeclared step is how a
# typed list goes stale in silence, and that is the whole reason this file
# exists.

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

# THE HOST PIN, shared with realisateur and declared here rather than inlined.
# realisateur's bin/lib/propagation-set.sh owns PROP_HOST_PIN because
# realisateur cuts the verb build and decides its layout. bin/selfdev-hooks-
# provision.sh needs it to find the hook file the build ships. Two repos, one
# path: tests/dresse.test.sh reads realisateur's value when a checkout is
# reachable and FAILS if they disagree, rather than trusting this copy.
PROVISION_HOST_PIN="${VERB_HOST_BUILD_ROOT:-/usr/local/share/verb-builds}/current"

# provision_channel <script-basename> -- prints `provision`, or nothing (rc 1)
# when this repo does not own that script. Callers MUST treat rc 1 as a
# finding: it means the step plan names something no set declares.
provision_channel() {
  local n="$1" s
  for s in $PROVISION_SCRIPTS; do [ "$s" = "$n" ] && { echo provision; return 0; }; done
  return 1
}
