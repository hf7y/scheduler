# /nightly-batch — the scheduler improving itself

This is the scheduler's own Tier 2 job, run unattended overnight by
`~/.local/bin/scheduler-nightly-batch-loop.sh`. You are working in a
**throwaway git worktree on a `nightly/<date>` branch**, behind a **human
review gate** — your commits are inspected and merged by a person in the
morning, not activated automatically. Treat this like changing production
infrastructure, because you are: this repo controls every other project's
cron jobs.

## Orient (do this first)

1. Read the tracker: `gh issue list --repo hf7y/scheduler --limit 200`.
   This is both the scope and the backlog. **`FOCUS.md`, `QUESTIONS.md`
   and `BLOCKERS.md` are retired** (#66, 2026-08-07) — they are pointer
   stubs, and `bin/collect-feedback.sh`'s `--consume` path is retired with
   them (#193). Do not read, append to, or restore any of them.
2. Read the **comments** on any issue before treating it as unaddressed.
   Zach answers by commenting and leaving the issue open, so an open issue
   is not evidence of unaddressed work, and issue state is never an answer
   signal.
3. Read `README.md` — the architecture and the decisions already made, so
   you don't re-litigate or undo them.
4. Skim recent reports in `~/reports/scheduler/` if any, to see what prior
   runs already did or deferred.

## Pick work

From the open issues, choose the
**highest-value, lowest-risk** item(s) you can
**fully finish and verify tonight**. One well-tested change beats three
speculative ones. Good candidates are self-contained: a script fix, a new
read-only helper, a docs/consistency cleanup, a `schedule/*.conf` change
you can validate with a preview. Bad candidates for an unattended run:
anything whose only test is "wait and see if cron does the right thing
tomorrow," or anything that reshapes the engine every job depends on.

## Hard rules (safety)

- **Stay inside this worktree.** Make changes only as commits here. Do not
  edit anything outside this repository — especially not the installed
  wrappers under `~/.local/bin` or any other project's files.
- **Never touch the live crontab.** Do not run `crontab`. Do not run
  `bin/sync-crontab.sh --apply`. Running it **without** `--apply` (preview)
  is the correct way to validate a `schedule/*.conf` change — do that
  instead.
- **Verify here and now.** Prefer changes you can check immediately:
  `bash -n`, `shellcheck` if available, a dry run, or simulating cron's
  environment with `env -u SSH_AUTH_SOCK GIT_SSH_COMMAND="ssh -o BatchMode=yes" …`.
  If a change genuinely can't be verified without going live, **don't
  commit it** — write it up as a proposal in tonight's report instead.
- **Don't invent scope.** If an item is ambiguous or needs a real
  judgment call, **file a GitHub issue** (`scheduler -i`, or `gh issue
  create --repo hf7y/scheduler --body-file <file>`) and describe it in the
  report rather than guessing. Never hand-type it into a markdown file.
- **No new markdown files.** `schedule/_standing-rules.md` rule 5 and
  `bin/markdown-cost.sh` both enforce this: a branch fails if it adds any
  new top-level `.md`, or if >30% of its added lines are markdown.
  Deletions are free.
- Keep `README.md` honest — if you change how something works, update the
  README in the same commit.
- If you complete a backlog item, close its issue in the same change
  (`Closes #N` in the commit or PR body) so the tracker stays accurate.

## Finish

1. Commit each finished change with a clear message (imperative subject +
   a why). Leave everything on the `nightly/<date>` branch — do not merge.
2. Write `~/reports/scheduler/$(date +%Y-%m-%dT%H%M).md` and update
   `~/reports/scheduler/LATEST.md` to match, a 30-second read covering:
   **what you changed and why**, **how you verified it**, **what you
   deliberately deferred (and why)**, and **any open questions**.
3. A change that isn't committed on the branch didn't happen. If you did
   nothing (nothing safe to do tonight), still write a short report saying
   so — proof-of-life beats silence.
