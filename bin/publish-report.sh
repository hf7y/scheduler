#!/usr/bin/env bash
# publish-report.sh <project> <dated-file> [--from <source>]
#
# The ONE way to publish a run's report and re-point
# ~/reports/<project>/LATEST.md at it.
#
# RETIRES the convention "write the dated file, then `cp` it onto
# LATEST.md" that /nightly-batch and this repo's prompt generators asked
# authors to remember. That convention destroyed a report on 2026-07-28:
# LATEST.md was a symlink to 2026-07-27-paced.md, `cp today.md LATEST.md`
# FOLLOWED the symlink, and yesterday's report was overwritten in place.
# ~/reports is not a git repo and has no backup, so the tail of that file
# is permanently gone. A rule an author has to remember is a latent bug;
# this script is the version that can't be forgotten wrong.
#
# What it guarantees:
#   * LATEST.md is always a SYMLINK to a dated file, never a copy, and is
#     replaced atomically (ln -sfn to a temp name + mv -T) -- so a reader
#     never sees a half-written pointer, and no write can ever follow the
#     old pointer into a past report.
#   * The dated target is written with `cat > tmp && mv -T` when --from is
#     given, so that write can't follow a symlink either.
#   * A pre-existing REGULAR-file LATEST.md (the legacy copy shape, still
#     live for several projects as of 2026-07-28) is never deleted
#     blindly: if its content differs from the new target it is preserved
#     as LATEST.md.orphaned-<utc-stamp> and the fact is printed loudly.
#
# Arguments:
#   <project>      report directory name under $REPORTS_ROOT (default
#                  ~/reports, override with SCHEDULER_REPORTS_ROOT -- this
#                  is what the test path and any dry run should set).
#   <dated-file>   the report file, as a bare name ("2026-07-28-paced.md")
#                  or a path inside that project's report directory. Must
#                  NOT be LATEST.md.
#   --from <src>   install <src>'s content as <dated-file> first ("-" for
#                  stdin). Without it, <dated-file> must already exist --
#                  the common case where the author already wrote/appended
#                  the report and only the pointer needs refreshing.
#
# Exits non-zero and says why on any refusal. Nothing is silent.

set -euo pipefail

REPORTS_ROOT="${SCHEDULER_REPORTS_ROOT:-$HOME/reports}"

die() { echo "publish-report.sh: ERROR: $*" >&2; exit 1; }

usage() {
  echo "usage: publish-report.sh <project> <dated-file> [--from <source>|-]" >&2
  exit 2
}

PROJECT=""; DATED=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] || usage; FROM="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) die "unknown option: $1" ;;
    *)
      if   [ -z "$PROJECT" ]; then PROJECT="$1"
      elif [ -z "$DATED" ];   then DATED="$1"
      else die "unexpected extra argument: $1"
      fi
      shift ;;
  esac
done
[ -n "$PROJECT" ] && [ -n "$DATED" ] || usage

case "$PROJECT" in */*|.|..) die "<project> must be a plain directory name, got: $PROJECT" ;; esac

DIR="$REPORTS_ROOT/$PROJECT"
[ -d "$DIR" ] || die "no report directory: $DIR (create it first -- refusing to guess)"

# Accept a bare name or a path, but it must land inside $DIR.
BASE="$(basename -- "$DATED")"
case "$DATED" in
  */*) [ "$(cd -- "$(dirname -- "$DATED")" && pwd -P)" = "$(cd -- "$DIR" && pwd -P)" ] \
         || die "<dated-file> must be inside $DIR, got: $DATED" ;;
esac
[ "$BASE" != "LATEST.md" ] || die "<dated-file> cannot be LATEST.md -- that is the pointer, not a report"

TARGET="$DIR/$BASE"
LATEST="$DIR/LATEST.md"

if [ -n "$FROM" ]; then
  [ ! -L "$TARGET" ] || die "$TARGET is a symlink; refusing to write through it"
  tmp="$TARGET.publish.$$"
  if [ "$FROM" = "-" ]; then cat > "$tmp"
  else [ -r "$FROM" ] || die "--from source not readable: $FROM"; cat -- "$FROM" > "$tmp"
  fi
  mv -T -- "$tmp" "$TARGET"
else
  [ -f "$TARGET" ] || die "$TARGET does not exist (write the report first, or pass --from)"
fi

# A legacy regular-file LATEST.md may be the ONLY copy of some past
# report. Never let re-pointing be the thing that deletes it.
if [ -f "$LATEST" ] && [ ! -L "$LATEST" ]; then
  if cmp -s -- "$LATEST" "$TARGET"; then
    rm -f -- "$LATEST"
  else
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    orphan="$DIR/LATEST.md.orphaned-$stamp"
    mv -n -- "$LATEST" "$orphan"
    echo "publish-report.sh: NOTE: $LATEST was a regular file with content not"
    echo "publish-report.sh:       matching $BASE -- preserved as $(basename -- "$orphan")"
    echo "publish-report.sh:       rather than deleted. Check whether it is a report"
    echo "publish-report.sh:       that never got a dated file of its own."
  fi
fi

# Atomic re-point: build the new link under a temp name, then rename over
# LATEST.md. `ln -sfn` straight onto LATEST.md is NOT enough -- with a
# symlink-to-directory it would write inside the target.
tmplink="$DIR/.LATEST.md.publish.$$"
ln -sfn -- "$BASE" "$tmplink"
mv -T -- "$tmplink" "$LATEST"

echo "published: $LATEST -> $BASE"
