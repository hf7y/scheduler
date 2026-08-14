#!/usr/bin/env bash
# consign-status.sh -- the second half of `consign` that nothing was doing:
# a countable, prompted list of files still living in BOTH the repo and the
# vault, byte-identical, after deposit. hf7y/scheduler#86.
#
# consign-prose.sh (vendored in bibliothecaire, hf7y/bibliothecaire#24)
# deposits a copy into the vault and deliberately deletes nothing -- removal
# is a judgment the depositor cannot make. But nothing consumed the report it
# leaves behind, so a deposit satisfied `fauche` and then nobody looked
# again: fbdbae9 deposited 10 files on 2026-08-01, and 9 days later every one
# was still duplicated. #84 worked two of them by hand and called the
# CLASSIFICATION -- not the removal -- the expensive part; this script makes
# the classification queue visible instead of remembered.
#
# GUARD: which vault-consigned files are still byte-identical duplicates
#        sitting in this repo, unactioned?
# RUNNER: tests/consign-status-witness.sh
# VERIFIED: 2026-08-14 via bash bin/consign-status.sh (5 DUPLICATE, 3
#           DIVERGED, 2 REAPED against the live tree / live vault)
#
# CONTRACT
#   exit 0 -- no file is a byte-identical duplicate right now (queue empty)
#   exit 1 -- at least one DUPLICATE: same sha256 in vault frontmatter and in
#             this repo's working tree. Each is named on stdout with how many
#             days since it was consigned -- these are the ones a human or
#             agent should classify (does the premise this file records still
#             hold?) and, if not, remove from the repo.
#   exit 2 -- BLIND: the vault root is missing or unreadable. Never reported
#             as "queue empty" -- an unreadable vault is not a clean vault.
#
# A DIVERGED row (repo sha != vault frontmatter's source_sha256) is not a
# failure: the repo copy moved on since consign, so the repo -- not the
# vault -- is the live one and the vault note is simply stale. Printed for
# visibility, not counted toward the exit code; re-consigning it is a
# separate, deliberate act, not this script's job.
#
# CONSIGN_VAULT_ROOT overrides where consigned notes live (default: this
# project's own tree in the shared vault). SCHED_ROOT overrides the repo
# root being checked against, same convention as bin/roster-diff.sh, so the
# witness can point both at a hermetic fixture instead of the real vault.
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SCHED_ROOT="${SCHED_ROOT:-$ROOT}"
VAULT_ROOT="${CONSIGN_VAULT_ROOT:-/srv/ecosystem1-vault/scheduler}"

[ -d "$VAULT_ROOT" ] && [ -r "$VAULT_ROOT" ] || {
  echo "BLIND -- cannot read vault root: $VAULT_ROOT"
  exit 2
}

# frontmatter_field <file> <key> -- value of "key: value" inside the leading
# "---" ... "---" block only, so a key mentioned in the body can't leak in.
frontmatter_field() {
  awk -v key="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && index($0, key ":")==1 {
      sub("^" key ":[[:space:]]*", "");
      print;
      exit
    }
  ' "$1"
}

days_since() {
  local then="$1" now_epoch then_epoch
  then_epoch="$(date -d "$then" +%s 2>/dev/null)" || { echo "?"; return; }
  now_epoch="$(date +%s)"
  echo $(( (now_epoch - then_epoch) / 86400 ))
}

dup_count=0
diverged_count=0
reaped_count=0
blind=0

while IFS= read -r -d '' note; do
  src_path="$(frontmatter_field "$note" source_path)"
  src_sha="$(frontmatter_field "$note" source_sha256)"
  consigned="$(frontmatter_field "$note" consigned)"
  [ -n "$src_path" ] && [ -n "$src_sha" ] || continue   # not a consign-prose note

  target="$SCHED_ROOT/$src_path"
  if [ ! -f "$target" ]; then
    reaped_count=$((reaped_count + 1))
    continue
  fi
  if [ ! -r "$target" ]; then
    blind=1
    echo "BLIND: $src_path -- exists but is not readable"
    continue
  fi

  repo_sha="$(sha256sum "$target" 2>/dev/null | awk '{print $1}')"
  if [ "$repo_sha" = "$src_sha" ]; then
    dup_count=$((dup_count + 1))
    age="$(days_since "${consigned:-}")"
    echo "DUPLICATE: $src_path -- byte-identical to the vault copy, consigned ${consigned:-unknown} (${age}d ago)"
  else
    diverged_count=$((diverged_count + 1))
    echo "DIVERGED:  $src_path -- repo copy has changed since consign; vault note is stale, not this repo"
  fi
done < <(find "$VAULT_ROOT" -type f -name '*.md' -print0 | sort -z)

echo "consign-status: $dup_count duplicate, $diverged_count diverged, $reaped_count already reaped"

[ "$blind" -eq 1 ] && exit 2
[ "$dup_count" -gt 0 ] && exit 1
exit 0
