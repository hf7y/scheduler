#!/usr/bin/env bash
# provenance.sh -- the stamp that tells this project's own GitHub comment
# apart from a genuine human reply posted under the same shared token.
#
# hf7y/ecosim#40 found that hf7y/scheduler had never once stamped a comment
# it posted as `hf7y`, so ecosim's lib/sensors/blocked.py -- which reads this
# stamp to tell an agent's own reply apart from a real answer from Zach --
# reports BLIND_NO_STAMP_DISCIPLINE for this project instead of a real ratio
# (hf7y/scheduler#172). Format and detection are ported from
# hf7y/vim-arcade#34's provenance.py, re-expressed here rather than imported
# because the dependency would run cross-repo the wrong direction -- the
# same choice ecosim's own lib/provenance.py (commit 32fd897) made. bin/gh-
# comment.sh is what calls this when posting.
#
# Format: `<!-- agent: <project>/<job> <ISO8601> -->`, appended as its own
# trailing paragraph so it stays the LAST non-blank line -- deliberately,
# so a stamp quoted mid-body from another comment does not count.
#
# CONTRACT
#   provenance_is_stamped BODY               -- 0 if BODY's last non-blank
#                                                line is a stamp, 1 otherwise
#   provenance_format_stamp PROJECT JOB [WHEN] -- prints the stamp line
#   provenance_stamp_body BODY PROJECT JOB [WHEN] -- prints BODY with the
#                                                stamp appended
# WHEN overrides the timestamp (testing only); default is `date -u` at
# second precision.

provenance_is_stamped() {
  local body="$1" last
  last="$(printf '%s\n' "$body" | sed '/^[[:space:]]*$/d' | tail -n1)"
  [[ "$last" =~ ^"<!--"[[:space:]]*agent:[[:space:]]*[^[:space:]]+/[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]*"-->"$ ]]
}

provenance_format_stamp() {
  local project="$1" job="$2" when="${3:-}"
  [ -n "$when" ] || when="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '<!-- agent: %s/%s %s -->' "$project" "$job" "$when"
}

provenance_stamp_body() {
  local body="$1" project="$2" job="$3" when="${4:-}" stamp
  stamp="$(provenance_format_stamp "$project" "$job" "$when")"
  if [ -n "$body" ]; then
    printf '%s\n\n%s' "$body" "$stamp"
  else
    printf '%s' "$stamp"
  fi
}
