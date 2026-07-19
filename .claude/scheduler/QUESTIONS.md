# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

- **2026-07-17 (wtul batch-job setup):** `lib/sweep-loop-common.sh`'s
  push-verification (the `pushed: yes/no/WARNING` log line) only compares
  local-vs-remote SHA on `$BRANCH` (default `main`). But every project's
  own nightly-batch/wtul-batch command template explicitly tells the run
  to give new feature work "its own branch off main... pushed on its
  own" -- not committed to `$BRANCH` directly. That means a run that did
  real work entirely on a feature branch will still log
  `pushed: no -- no new commits this run`, which reads as "nothing
  happened" even when something did. This isn't wtul-specific -- chezz
  and vkv-inventory share the identical engine and identical
  feature-branch guidance in their own nightly-batch.md files, so the
  same false-negative applies to both, today, already live in production
  for chezz.

  Options, not yet decided:
  1. After the `claude -p` run, diff `git branch -r` before/after (or
     `for-each-ref`) to find any new/updated branches, and verify each
     one's local ref matches its own remote counterpart, not just
     `$BRANCH`'s.
  2. Have the command file itself report which branch(es) it touched
     (e.g. write branch names to a small marker file) rather than trying
     to infer this purely from git state after the fact.
  3. Leave as-is if `$BRANCH`-direct commits turn out to be the common
     case in practice and feature branches are rare enough that a
     human skimming `~/reports/<project>/LATEST.md` catches it anyway --
     i.e. decide this is a report-writing discipline problem, not a
     git-verification one.

  Needs a real decision: which approach (if any) is worth building, and
  whether it's worth doing before or after more projects migrate onto
  this engine.
  > Just flag it in reports which branches exist when there's a live/dev
  > split (option 2 -- self-report touched branches, don't try to infer
  > purely from git state). Keep me informed about branches generally;
  > look into an ASCII tree diagram in the report/dashboard showing branch
  > structure per project. Standing direction -- fold into FOCUS.md.
