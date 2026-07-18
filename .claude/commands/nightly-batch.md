# /nightly-batch — the scheduler improving itself

This is the scheduler's own Tier 2 job, run unattended overnight by
`~/.local/bin/scheduler-nightly-batch-loop.sh`. You are working in a
**throwaway git worktree on a `nightly/<date>` branch**, behind a **human
review gate** — your commits are inspected and merged by a person in the
morning, not activated automatically. Treat this like changing production
infrastructure, because you are: this repo controls every other project's
cron jobs.

## Orient (do this first)

1. Read `.claude/scheduler/FOCUS.md` — it states the current posture, the
   current focus, AND the backlog (its "Backlog" section). There is no
   separate `TODO.md` anymore; FOCUS.md is both scope and backlog.
2. Read `README.md` — the architecture and the decisions already made, so
   you don't re-litigate or undo them.
3. Skim recent reports in `~/reports/scheduler/` if any, to see what prior
   runs already did or deferred.

## Pick work

From `.claude/scheduler/FOCUS.md` (its focus + backlog), choose the
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
  judgment call, append the question to `.claude/scheduler/QUESTIONS.md` and
  describe it in the report rather than guessing.
- Keep `README.md` honest — if you change how something works, update the
  README in the same commit.
- If you complete a backlog item, remove or check off its line in
  `.claude/scheduler/FOCUS.md` as part of the same change so it stays
  accurate.

## Finish

1. Commit each finished change with a clear message (imperative subject +
   a why). Leave everything on the `nightly/<date>` branch — do not merge.
2. Write `~/reports/scheduler/$(date +%Y-%m-%d).md` and update
   `~/reports/scheduler/LATEST.md` to match, a 30-second read covering:
   **what you changed and why**, **how you verified it**, **what you
   deliberately deferred (and why)**, and **any open questions**.
3. A change that isn't committed on the branch didn't happen. If you did
   nothing (nothing safe to do tonight), still write a short report saying
   so — proof-of-life beats silence.
