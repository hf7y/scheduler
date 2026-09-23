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
# WHAT COUNTS AS AN ANSWER (2026-08-14). Zach answers a question issue by
# COMMENTING and LEAVING IT OPEN. He does not apply the `answered` label and
# does not want to, so neither issue STATE nor LABEL carries any information
# about whether he answered: an open question issue is NOT evidence it is
# unanswered. The predicate that needs no cooperation from anybody is this
# stamp -- an issue is ANSWERED if it carries a comment by the repo OWNER
# that is not agent-stamped. Under one shared `hf7y` token an agent's own
# reply looks exactly like his, which is what the stamp is for.
#
# PROVENANCE_ANSWERED_JQ below is that predicate as a jq prelude, because its
# consumer (bin/scheduler's issues_counts) reads `gh issue list --json`. It
# defines `is_stamped` and `is_answered($owner)`, and is the ONE place either
# is written in this repo -- the same predicate as chezz's
# scripts/answered-issues.mjs, ecosim's lib/sensors/blocked.py and
# realisateur's bin/gh-comment.sh, reused as a CONVENTION, not imported.
#
# CONTRACT
#   provenance_is_stamped BODY             -- 0 if BODY's last non-blank
#                                                line is a stamp, 1 otherwise
#   provenance_format_stamp PROJECT JOB [WHEN] -- prints the stamp line
#   provenance_stamp_body BODY PROJECT JOB [WHEN] -- prints BODY with the
#                                                stamp appended
# WHEN overrides the timestamp (testing only); default is `date -u` at
# second precision.

# jq prelude. Use with `--arg owner <repo owner login>` over a
# `gh issue list --json labels,comments` array. The `answered` label is
# honoured as an optional override where someone bothered to apply it, and is
# never required -- nothing but `scheduler -q`'s push path ever applies it.
PROVENANCE_ANSWERED_JQ='
def is_stamped:
  ((. // "") | split("\n") | map(sub("^\\s+";"") | sub("\\s+$";""))
   | map(select(length > 0)) | last // "")
  | test("^<!--\\s*agent:\\s*\\S+/\\S+\\s+\\S+\\s*-->$");
def is_answered($owner):
  (([(.labels // [])[].name] | index("answered")) != null)
  or ((.comments // []) | any(.author.login == $owner
                              and ((.body // "") | is_stamped | not)));
'

# THE OTHER DIALECT (#764). Everything above reads a COMMENT this repo posted:
# `<!-- agent: <project>/<job> <ISO8601> -->`. Issue BODIES across the estate
# are stamped by a different tool -- realisateur's bin/gh-sign.sh -- in a
# different shape: `<!-- agent: <account>@<host> <ISO8601> build <id> -->`.
# Neither regex matches the other, so `is_stamped` reads every gh-sign-stamped
# BODY as a human's. Anything asking WHO FILED an issue wants this predicate.
#
# Deliberately NOT a widening of `is_stamped`: that one feeds `is_answered`,
# where a stamped comment means "not Zach speaking", and broadening it would
# silently change which issues read as answered.
#
# `zach@<host>` COUNTS AS AN AGENT here, which is where this parts company with
# usage-paced-runner.sh's milestone_self_fed (that one calls the stamp a
# human's). The stamp names the ACCOUNT a job ran under, not a person: an agent
# working on mandark stamps `zach@mandark`. Treating it as human would leave the
# account most agents run under able to manufacture pace. An issue Zach filed by
# hand carries no stamp at all, and that is the line this draws.
PROVENANCE_FILER_JQ='
def body_agent_filer:
  (((. // "") | split("\n") | map(sub("^\\s+";"") | sub("\\s+$";""))
    | map(select(length > 0)) | last) // "") as $last
  | if   ($last | test("^<!--\\s*agent:\\s*[^@[:space:]]+@"))
    then ($last | capture("^<!--\\s*agent:\\s*(?<who>[^@]+)@") | .who)
  elif   ($last | test("^<!--\\s*agent:\\s*\\S+/\\S+\\s+\\S+\\s*-->$"))
    then ($last | capture("^<!--\\s*agent:\\s*(?<who>[^/]+)/") | .who)
  else null end;
def filed_by_agent: (body_agent_filer != null);
'

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
