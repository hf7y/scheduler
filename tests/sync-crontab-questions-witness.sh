#!/usr/bin/env bash
# Witness for "which projects get a questions/<project>.md symlink, and what
# does bin/sync-crontab.sh create to point it at?"
#
# THE TWO BUGS THIS RETIRES (found 2026-08-06, both reproduced before the fix):
#
# 1. FABRICATED CHECKOUTS. The --apply path did
#        mkdir -p "$(dirname "$target")"; printf '%s' "$QUESTIONS_HEADER" > "$target"
#    with no check that PROJECT_REPO_PATH exists on THIS host as THIS account.
#    PROJECT_REPO_PATH is an absolute path -- a claim about this filesystem --
#    and every self-dev conf sets it to "$HOME/Documents/Projects/<p>", which
#    resolves under whichever account happens to be running the sync. So a sync
#    on an account with no clone of that project did not skip it: it built
#    ~/Documents/Projects/<p>/.claude/ and wrote a header into it, producing a
#    directory that looks like a checkout, has no .git, is never committed from
#    and is never read again.
#
#    Observed: /home/chezz/Documents/Projects/baudin/ (2026-08-05 02:21) and
#    /home/crt/Documents/Projects/baudin/ (2026-08-06 03:58) on monkey, each
#    containing exactly one file -- .claude/QUESTIONS.md, 336 bytes, the bare
#    header -- and each with a matching questions/baudin.md symlink in that
#    account's scheduler checkout. Same failure bin/scheduler's
#    require_repo_path() already refuses ("an absolute path that is not there
#    is a WRONG path, never a path to create"); this writer never asked.
#
#    The FOCUS.md block ten lines below it had the rule right all along --
#    "fabricating an empty one would mislead a nightly run into thinking it has
#    scope" -- and skipped. QUESTIONS.md did not.
#
# 2. ANSWER_CHANNEL LEAKED BETWEEN CONFS. The per-conf `unset` block resets
#    every field the format understands so a conf missing a var cannot inherit
#    the previous file's value. ANSWER_CHANNEL was never added to that list.
#    Confs are sourced in glob order, so once bibliothecaire.conf set
#    ANSWER_CHANNEL="issues", every conf after it in the alphabet inherited it
#    and was silently treated as migrated to the issues channel -- no symlink,
#    no link even for projects that DO have a local checkout.
#
#    That is why exactly one project ever fabricated anything: `baudin` sorts
#    first, ahead of `bibliothecaire`, so it was the only conf still seeing the
#    default "file" channel. Fixing bug 2 alone would have spread bug 1 from
#    one project to nine.
#
# Runs the REAL script against a throwaway fixture repo built from the tree
# this witness ships in (same rule as sync-crontab-paced-witness.sh -- never a
# hardcoded checkout). Preview mode only: --apply is not passed anywhere in
# this file, so no crontab and no project directory is ever written.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$ROOT/bin/sync-crontab.sh"
[ -f "$SYNC" ] || { echo "script under test not found: $SYNC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$(dirname "${BASH_SOURCE[0]}")/lib/witness-common.sh"

# --- fixture repo -----------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/schedule"
cp -r "$ROOT/bin/." "$REPO/bin/"
cp -r "$ROOT/lib/." "$REPO/lib/"

# Stand-in checkouts. qa/qb/qc have one; qd deliberately does NOT -- its
# PROJECT_REPO_PATH names a directory that is simply not on this filesystem,
# which is exactly the shape a self-dev account presents for every project it
# has not cloned.
CLONES="$TMP/clones"
mkdir -p "$CLONES/qa-plain" "$CLONES/qb-issues" "$CLONES/qc-after-issues"
MISSING="$CLONES/qd-noclone"   # never created

# Names chosen so glob order puts qb-issues BETWEEN qa-plain and
# qc-after-issues: the leak, if it is back, lands on qc and nothing else.
mkconf() {  # $1 = name, $2 = repo path, $3 = extra lines
  cat > "$REPO/schedule/$1.conf" <<EOF
PROJECT="$1"
PROJECT_REPO_PATH="$2"
SWEEP_JOB_NAME=""; SWEEP_SCRIPT=""; SWEEP_CRON=""
BATCH_JOB_NAME=""; BATCH_SCRIPT=""; BATCH_CRON=""
$3
EOF
}
mkconf qa-plain        "$CLONES/qa-plain"        ''
mkconf qb-issues       "$CLONES/qb-issues"       'ANSWER_CHANNEL="issues"'
mkconf qc-after-issues "$CLONES/qc-after-issues" ''
mkconf qd-noclone      "$MISSING"                ''

OUT="$( cd "$REPO" && "$REPO/bin/sync-crontab.sh" 2>&1 )"

# The artifact is the questions/ line the preview says it would create. Match
# the link, not any incidental mention of the project name elsewhere.
links() { printf '%s\n' "$OUT" | grep -q "^questions/$1\.md -> "; }

echo "== a project with a checkout on this host gets its link"
if links qa-plain; then
  ok "qa-plain (file channel, checkout present) is linked"
else
  bad "qa-plain lost its questions link -- over-suppression; every other case"\
      "in this file would pass on a script that linked nothing at all"
fi

echo "== ANSWER_CHANNEL=issues suppresses the link, and does not leak forward"
if links qb-issues; then
  bad "qb-issues got a questions link -- a migrated project must have no file surface"
else
  ok "qb-issues (issues channel) is not linked"
fi
if links qc-after-issues; then
  ok "qc-after-issues keeps its link -- ANSWER_CHANNEL did not leak from qb-issues"
else
  bad "qc-after-issues lost its questions link -- ANSWER_CHANNEL leaked from the"\
      "PREVIOUS conf in glob order; add it to the per-conf unset block"
fi

echo "== a project with NO checkout on this host is skipped, never fabricated"
if links qd-noclone; then
  bad "qd-noclone is queued for a link at $MISSING/.claude/QUESTIONS.md, which"\
      "--apply would mkdir -p into existence -- a fabricated checkout, the"\
      "chezz/crt baudin stubs of 2026-08-06"
else
  ok "qd-noclone is not linked -- no phantom checkout to point at"
fi
if printf '%s\n' "$OUT" | grep -q "qd-noclone.*PROJECT_REPO_PATH"; then
  ok "and it says so out loud, naming the path that is not there"
else
  bad "qd-noclone was dropped SILENTLY -- a skipped project with no message is"\
      "indistinguishable from a project the sync forgot about"
fi
if printf '%s\n' "$OUT" | grep -q "^focus/qd-noclone\.md -> "; then
  bad "qd-noclone still queued for a focus/ link into a directory that does not exist"
else
  ok "focus/ link is skipped for the same project, for the same reason"
fi

echo "== the guard is in the writer, not only in the collector"
if grep -q 'refusing to fabricate' "$SYNC"; then
  ok "bin/sync-crontab.sh keeps a backstop at the point of the mkdir/write"
else
  bad "the only check is where QUESTIONS_LINKS is built -- the write site is far"\
      "from it, and the next edit that appends an entry re-opens the hole"
fi

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
