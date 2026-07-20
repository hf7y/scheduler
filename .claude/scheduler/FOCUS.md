# FOCUS — scheduler (what its own nightly job should work on)

The scheduler's Tier 2 job (`/nightly-batch`) is scoped by this file, same
as every other project. Difference: this project is the **meta-tool** that
controls all the other jobs.

**Push policy (changed 2026-07-18, human-approved):** the nightly job MAY
push its own commits directly to `origin/main` — no `nightly/<date>` branch,
no human merge step required. This is *not* a license to skip review after
the fact: every push MUST be flagged prominently in that night's report
(what was pushed, why, and how to revert it — e.g. `git revert <sha>`) so
the human can review it the next morning same as before, just after the
fact instead of before. See item 6 in Current focus for the sequencing
requirement (push after other jobs, before morning) and conflict-awareness
work still to build before leaning on this. Until that safety work lands,
prefer the old review-gate branch behavior for any change riskier than a
docs/FOCUS-only edit.

**Merge policy (changed 2026-07-19, human-directed):** `bin/scheduler-dev-cycle.sh`
now merges each finished paced cycle's commits from `paced/<date>` into
*local* `main` right after the cycle (`git merge --no-ff`), instead of
leaving them on the branch for a manual merge first. Review still happens —
just after the fact (`git show <merge-sha>`, revert with
`git revert -m 1 <merge-sha>`) instead of before. This is a **toggleable
flag**, not a rewrite of the safety model: `~/.local/share/scheduler-paced-dev/merge_mode`
holds `merge` (default, new behavior) or `branch` (old behavior, commits
stay on the branch for manual review/merge). The cycle also self-guards:
if `main` isn't clean and checked out in the scheduler repo when a cycle
finishes (e.g. another session has an in-progress edit, as has happened
with `crt.conf`), it automatically falls back to leaving commits unmerged
rather than merging into a dirty tree. **Still separate from and unaffected
by this: pushing to `origin` stays exactly as cautious as the push policy
above** — this only changes local-main merge timing, not whether/when
anything reaches GitHub.

## This project dogfoods its own system

The scheduler uses the exact pieces every registered project uses, no
bespoke ones:

- **Its files live in `.claude/scheduler/`** (this folder): `FOCUS.md`,
  `QUESTIONS.md`, `schedule.conf`. Registration symlinks them into
  scheduler's aggregation folders (`focus/`, `questions/`, `schedule/`) —
  `schedule/scheduler.conf` is already a symlink back to
  `.claude/scheduler/schedule.conf`.
- **Reports** go to `~/reports/scheduler/` like everyone else.
- **The backlog lives HERE, in this file** (the section below) — not in a
  separate `TODO.md` anymore (retired 2026-07-18). The scheduler has no
  tracker and no end users filing reports, so FOCUS.md is both scope *and*
  backlog. Introduce an idea by adding a line to the Backlog section; that's
  the whole intake mechanism.
- **Questions** (`.claude/scheduler/QUESTIONS.md`) for anything needing a
  human decision — appended, never acted on unilaterally.

## Cost insight (2026-07-18 usage audit — read before touching model/effort settings)

Audited real token usage across `~/.claude/projects/*.jsonl` since 2026-07-17.
Findings, so this doesn't get re-litigated or blamed on the wrong thing:

- **The bug sweeper is cheap** (~$72 of ~$1245 total, ~6%). It was suspected
  as the usage drain and it is not — don't spend effort "fixing" it on that
  theory.
- **Interactive human chats are ~73% of spend** (~$907), automation
  (nightly-batch + bug-sweep + scheduler self-runs combined) is ~27% (~$339).
- **The real per-token cost lever is model choice, not reasoning effort.**
  Opus is ~5x Sonnet's price per token (both input and output/thinking).
  Effort level only trims how many tokens Opus emits per turn — "Opus on
  low effort" for routine work still pays the full Opus per-token premium
  for a lower-quality answer. Human default model has been switched to
  Sonnet 5 (2026-07-18) for exactly this reason.
- **Scheduler's own self-runs and the nightly batches are a real, separate
  cost center worth slimming** — 07-18 alone saw automation jump to ~$284
  in one day (scheduler self-run ~$134, vkv-inventory-nightly ~$73,
  chezz-nightly ~$28). Action item: scheduler should look at what model/
  effort each `*_TIER*_MODEL` in `schedule/*.conf` is actually set to, and
  whether nightly/batch tiers that don't need Opus-grade reasoning (routine
  sweeps, mechanical migrations) can run on Sonnet instead. This is a
  concrete, cheap win — fold it into the "Optimal-usage scheduling" backlog
  item below rather than treating it as a new one-off.

## Current focus

0. **Collapse report + questions into one file I actually read.** Today I
   have to open a report AND separately edit `QUESTIONS.md` to answer
   things — too many files, and the answer workflow is disconnected from
   where I actually see the question. Preferred workflow (may partially be
   superseded by the TUI in item 3 below, but worth building now — could be
   good enough on its own even once the TUI lands):
   - The **morning report and the open questions/decisions live in a single
     markdown file**, one per project, owned by scheduler.
   - I open that one file, read what happened + what's pending, and **write
     my answers inline right there** (e.g. under each question, same `> `
     convention as today's QUESTIONS.md).
   - That file is what's symlinked into each project today (or, once a
     project has no local checkout per item 4's design, copied into the
     ephemeral clone before `claude` runs) — so the next night's job reads
     my inline answers straight out of it, same round-trip QUESTIONS.md
     already does, just merged with the report instead of a separate file.
   - Concretely: look at whether `focus/<project>.md` (scope),
     `questions/<project>.md`, and `~/reports/<project>/...` can become one
     `report/<project>.md`-shaped file per project — newest report on top or
     appended, open questions inline, my `> ` replies picked up and cleared
     next run. Don't lose the history reports currently have; append rather
     than overwrite.
   - Do this incrementally and verifiably like everything else in this file
     — pick one project (scheduler itself is the safest first mover, as in
     item 4) to prototype the merged-file shape before touching others.

1. **Migrate every project's `schedule/*.conf` onto the new
   `bin/scheduler-run` entrypoint, per `MIGRATION.md`.** The generic
   entrypoint + backwards-compat mechanism landed 2026-07-18; the confs are
   still on legacy `*_SCRIPT` wrappers. For each of `chezz`, `vkv-inventory`,
   `home-assistant`, `wtul`: READ its `~/.local/bin/<...>-loop.sh` wrapper
   (reading outside the repo is fine; **editing** it is not), copy each
   config variable into that project's `schedule/<project>.conf` runtime
   fields (`REPO_URL`, `<TIER>_PROMPT`, `<TIER>_MAX_TURNS`, `<TIER>_MODEL`,
   `<TIER>_PRECHECK_CMD`, …), and **leave the `*_SCRIPT` line in place**
   (commented) so nothing flips until a human drops it and runs `--apply`.
   Verify with `bin/sync-crontab.sh` (preview, NO `--apply`): output must
   stay byte-identical while `*_SCRIPT` is still set. One commit per project.

2. **Propagate the self-contained-folder model to the other projects** (what
   scheduler just adopted): each project's scheduler files
   (`FOCUS.md`/`QUESTIONS.md`) grouped under `.claude/scheduler/`, with a
   `SCHEDULER_SUBDIR=".claude/scheduler"` line in its conf so
   `bin/sync-crontab.sh` points its `focus/`+`questions/` symlinks there.
   This touches other projects' `.claude/` layout and their `/nightly-batch`
   command's FOCUS path — write it up as a per-project proposal in the
   report (and a QUESTIONS entry) rather than editing other repos from here.

3. **"scheduler" glance command (scoped 2026-07-19).** Goal: run `scheduler`
   in a terminal, see at a glance what's scheduled per project + whether it
   has open questions, then jump into a report and answer inline — vim
   native, not a custom UI.
   - **First cut BUILT 2026-07-20** (`~/.local/bin/scheduler`, NOT in this
     repo's git history, same as every other `~/.local/bin` wrapper): `scheduler`
     (glance -- project, open-question count from `questions/*.md`, open
     `BLOCKERS.md` item count per project), `scheduler -b`/`blockers`,
     `scheduler -f`/`focus [project]`, `scheduler -q`/`questions [project]`,
     `scheduler -r`/`report [project]` (opens `~/reports/<project>/LATEST.md`
     in `$EDITOR`). This is (b) below in spirit but skipped ahead of (a) --
     it reads today's separate `focus/`/`questions/`/`LATEST.md` files
     as-is rather than waiting on the merged-file design, so it's a real
     shortcut today, not a placeholder for the eventual merged file. Open
     question/blocker counts are a rough heuristic (bullet-line count minus
     lines matching "resolved"/"acknowledged", or bullets under a matching
     `## <project>` heading in `BLOCKERS.md`) -- not a real parser, will
     miscount on anything that doesn't follow the usual `- **` convention.
     Not yet showing next-dispatch timing (paced-rotation position / cron
     time) or `git log main..<branch>` awaiting-review counts -- still
     open, see (b)/(c) below.
   Sequencing (build item 0's merged file FIRST; the command is mostly a
   thin wrapper around it):
   a. **Prototype the merged `report/<project>.md` file on scheduler itself**
      (item 0 above) — newest run appended, `## Questions` section using the
      existing `> ` reply convention, next cycle reads its own prior answers
      back out of the same file. Don't lose history; append don't overwrite.
   b. **Add a `scheduler` subcommand** (`bin/scheduler-run scheduler` or a
      thin new `bin/scheduler` wrapper) that prints one screen: per project,
      next scheduled dispatch (paced-rotation position for paced
      participants, cron time for fixed ones) and an open-questions flag;
      and `scheduler open <project>` that just execs `$EDITOR` on that
      project's merged report file — no custom TUI framework, no parsing
      layer beyond what already reads `QUESTIONS.md` today.
   c. **Blocker "approve/clear" = `git log main..<branch>` + manual
      `git merge`/`git revert`**, same as the merge-policy note above — the
      glance screen can show "N commits on <branch> awaiting review" and
      shell out to `git log`/`git diff` on demand, but do not auto-merge
      from inside this command; that stays a human action (or the separate,
      already-toggleable `scheduler-dev-cycle.sh` merge policy for this
      project's own self-dev branch specifically).
   d. Migrate one project at a time after scheduler's own prototype is
      verified; old `LATEST.md`/`QUESTIONS.md` stay as fallback until each
      project's wrapper is confirmed reading the merged file correctly.
   Pick off (a) first, verify it round-trips a real inline reply before
   touching (b)-(d).

4. Lay the groundwork for a long term design which allows me to remove these github hosted projects from my system entirely. The code lives on github and only gets pulled if necessary to do work. If it's better to cache the downloaded repo somewhere, that's fine. The goal here is to clean up my working environment so me moving these projects around to different locations doesn't effect scheduler's ability to run their improvements.

   **Design direction (decided 2026-07-18 with the human — build toward this, don't
   land it in one run).** The blocker is that today's `focus/`+`questions/`
   symlinks point *out of scheduler into each project's local working copy*
   (`focus/chezz.md -> /…/chezz/.claude/FOCUS.md`). Delete that checkout and
   the symlink dangles — so "no local checkout" and "symlink into the
   checkout" are fundamentally incompatible. The batch already does NOT read
   through the symlink anyway: it clones `origin/main` fresh, `reset --hard`,
   and reads FOCUS.md from *that ephemeral clone*. The symlink is only a
   human browse/edit convenience, and edits to it still have to be committed
   + pushed before a clone sees them.

   The target shape that survives removing the checkout:
   - **Scheduler owns the human-authored scope.** Store each project's
     FOCUS.md (and QUESTIONS.md) *inside scheduler* as the master — the
     natural home is the existing `focus/<project>.md` / `questions/<project>.md`
     slots, but as **real files, not symlinks** once a project has no local
     checkout. The project repo's `.claude/FOCUS.md` flips from master to a
     synced artifact.
   - **The run injects scope into the ephemeral clone.** `scheduler-run`
     (or the engine) writes the scheduler-owned FOCUS.md/QUESTIONS.md into
     the throwaway clone after `reset --hard`, before invoking `claude`, so
     the project's `/nightly-batch` still just reads `.claude/FOCUS.md` as it
     does today — no per-project command change needed. If a question got a
     `> ` answer, the same round-trip carries the edit back.
   - **Repo cache, not a checkout.** Pull-on-demand into a scheduler-managed
     cache dir (keyed by repo, reused across runs — this is the dedicated
     clone the engine already maintains per `JOB_NAME`); a human moving or
     deleting the project's own working copy no longer affects anything.
   - **Migration is incremental and per-project.** A project keeps its
     symlink (checkout present) until it's explicitly switched to
     scheduler-owned scope; don't flag-day it. Design a single flag/marker
     (e.g. a conf field like `SCOPE_SOURCE=scheduler|repo`) that
     `sync-crontab.sh` reads to decide symlink-vs-real-file, mirroring how
     `SCHEDULER_SUBDIR` and the `*_SCRIPT` backwards-compat already work.
   - **Out of scope of this design, unchanged:** a project's *public intake*
     (e.g. chezz's web tracker fed by player chat submissions) is web-hosted
     and independent of where code lives — it stays as-is. Only the
     human-authored scope migrates into scheduler; do NOT try to pull player
     backlogs into FOCUS.md (two stores that would drift). FOCUS.md points at
     and prioritizes tracker items; it does not duplicate them.

   First verifiable pieces (pick off one per run, review-gate as usual): (a)
   a `SCOPE_SOURCE` conf field + `sync-crontab.sh` honoring it (real file vs
   symlink) with a preview that stays byte-identical for existing
   `repo`-source projects; (b) the inject-scope-into-clone step in the engine
   behind that flag; (c) the repo-cache reuse. Scheduler itself is the safest
   first mover (local-only, already dogfoods every mechanism).

5. Step 4 above should make it possible for scheduler to run on any machine, cloud host or my desktop, freeing up my laptop from this workflow. Since scheduler isn't usage aware right now, just lay the groundwork for features 4 and 5. 

6. Note: pushing this repo is now something scheduler can do itself. As long as that's revertable, it's just something that needs to be flagged for me to review (that it happened, what the consequences are/why I might want to revert it). To avoid conflicts with other scheduled jobs, we need awareness of effects. It makes sense to push/schedule this utility's development changes to occur after upcoming jobs are run, but before the morning.

## Watch and report tonight

- **Per-project pre-commit hook cost.** Unattended sweep/batch jobs commit
  *per item*, so each commit pays that project's pre-commit hook. chezz's
  hook runs the full Playwright suite (>2 min) — observed 2026-07-18 stalling
  a commit past a 2-min tool timeout. Across several commits that silently
  eats the turn/time budget and can leave a commit half-made on a timeout.
  Scheduler is the right place to be aware of this (it owns the budget and
  the optimal-usage work). Tonight: don't fix it, just **surface it** — note
  in the report which registered projects have a heavy pre-commit hook and
  roughly how long, and propose the cheapest awareness mechanism (e.g. the
  engine timing each `git commit` into the state dir so `morning-report.sh`
  can sum per-project commit overhead, and/or a conf note per project). A
  natural sibling to the `USAGE_GATE_CMD`/token-logging idea already in the
  backlog. Do not touch other projects' hooks or `--no-verify` their commits
  from here — that's each project's own call.

## Backlog (the intake — add a line to propose an idea)

- **Branch awareness in reports (decided 2026-07-19, human-directed).**
  Fixes the push-verification blind spot above (option 2): have each run
  self-report which branch(es) it touched (write branch name(s) to a small
  marker file rather than trying to infer purely from git state after the
  fact), and have `morning-report.sh`/the services view surface it — a
  per-project line naming any branch(es) beyond `main` that exist right
  now, flagging when there's a live/dev split. Also look into rendering an
  ASCII tree diagram of each project's branch structure (e.g. `git log
  --graph --oneline --all` shaped) in the report/dashboard so branch state
  is visible at a glance, not just named. General principle: keep the human
  informed about what branches exist, don't let them pile up silently.
- **Sweep cadence** — sweeps (esp. chezz) may run too often; tune
  `schedule/*.conf` cadence, validate with a `sync-crontab.sh` preview.
- **Auditability** — largely addressed by `bin/build-services-view.sh` /
  `services/` and the `focus/`+`questions/` aggregation; keep current,
  extend if gaps show up.
- **Optimal-usage scheduling** — token/%-usage reporting per project and
  scheduling jobs into unused capacity windows; ideally never hit the daily
  usage-limit window while maximizing weekly usage. Larger; break into
  verifiable pieces (e.g. a `USAGE_GATE_CMD` sibling to `PRECHECK_CMD`, plus
  per-run token logging into the state dir that `morning-report.sh` sums).
  Don't attempt wholesale in one unattended run.
  - **2026-07-19 (human direction, extends the above):** `usage-gate.sh`'s
    burn-rate governor should be TIME-OF-DAY-AWARE, not flat across the
    day — spend more of the weekly budget during hours the user is
    typically inactive (night), hold more back during hours they're
    typically active (day), so paced cycles don't compete with the user's
    own interactive usage right when they're most likely to be using
    Claude Code themselves. Needs an actual activity profile, not a guess
    at fixed hours — see next point.
  - **2026-07-19 (human direction): track usage-exhaustion history for
    dynamic budgeting.** Log every time the account actually runs out of
    weekly/daily quota (timestamp + which window), so the pacing curve
    above can be DATA-DRIVEN instead of hand-tuned: if exhaustion keeps
    happening at a particular time of day or day of week, that's a signal
    to pull back the daytime allowance further; if quota is consistently
    left unused, the night allowance can grow. This is the input the
    time-of-day curve should be tuned against, not a one-time guess.
    Needs a design pass: where the exhaustion log lives, what counts as
    "ran out" (a 429/rate-limit response vs. `usage-gate.sh` itself
    declining to dispatch), and how far back history should weight into
    the current curve.
- **crt registered 2026-07-19** — since resolved (superseding the 2026-07-18
  note above): now a git repo pushed to a local bare remote
  (`~/git-remotes/crt.git`, no GitHub/credentials needed), `schedule/crt.conf`
  wired in as a Tier-2-only paced participant (`schedule/_paced.conf`),
  `.claude/{FOCUS,QUESTIONS}.md` + `commands/nightly-batch.md` in place,
  `focus/crt.md`+`questions/crt.md` symlinks applied. First run
  (2026-07-19T18:33) got a stale clone (`de7ae87`, one commit behind
  `origin/main`'s `249deff` which is what actually added
  `.claude/commands/nightly-batch.md`) so it hit "Unknown command:
  `/nightly-batch`" and did nothing — a one-time ordering issue from
  registering before that commit was pushed, not a bug in the engine. The
  dedicated clone does a fresh `reset --hard` each run, so this should
  self-heal on tonight's next paced cycle since `origin/main` now has the
  command file — **worth confirming in tomorrow's report that it actually
  did**, since this is the first project exercising a raw `BATCH_PROMPT`
  (`/nightly-batch`) through the new generic `scheduler-run` engine rather
  than a legacy `*_SCRIPT` wrapper, so a real failure here would be worth
  distinguishing from the known stale-clone explanation.
- **Deploy-pending awareness in `morning-report.sh`.** Projects with a
  deploy step the nightly can't run (vkv-inventory: the batch commits +
  pushes but has no interactive `clasp` auth, so the live `/exec` silently
  falls behind `origin`) need the morning report to SAY "live is behind
  origin — run the deploy." Today the only cue is an ad-hoc QUESTIONS.md
  entry, which a code-shipping night that files no question won't produce —
  that's how vkv drifted 5 commits + a stale live site before a human
  noticed (2026-07-18). Add a per-project, opt-in deploy-freshness check: a
  conf field (e.g. `LIVE_URL` + a `DEPLOY_FRESH_CMD` probe, sibling to
  `PRECHECK_CMD`) that `morning-report.sh` runs and, if the live build is
  stale, prints a "DEPLOY PENDING" line with the exact deploy command.
  vkv-inventory's probe already exists and is cheap: `GET
  ?scope=sweep-status` returns HTML when stale, JSON when fresh (see that
  repo's `tools/deploy.sh`). Opt-in, so projects with no deploy step are
  unaffected and the report stays byte-identical for them.
- **Right-size per-tier model choice** (see Cost insight above) — audit each
  registered project's `schedule/*.conf` `<TIER>_MODEL` fields; identify
  which nightly/batch tiers are running Opus (or Opus-priced reasoning) for
  work that's mechanical enough for Sonnet, and propose the downgrade
  per-project (don't silently change other repos' confs from here — flag it,
  same as other cross-project proposals). Opus is ~5x Sonnet per token, so
  this is likely the single cheapest lever for slimming automation cost.

- **DONE 2026-07-19: inline `%%TAG` feedback in reports.** The human
  reviews a report/tracker file directly in vim (mappings in `~/.vimrc`,
  scoped to `~/reports/**/*.md` and this repo's `focus/`/`questions/`
  symlinks: `<leader>a/b/q/n/y/r` for ACTION/BLOCKER/QUESTION/NOTE/APPROVE/
  REJECT), leaves tagged comments inline, and the NEXT run for that project
  picks them up automatically and acts on them first — see
  `docs/feedback-tags.md` for the format and `bin/collect-feedback.sh` for
  the collector. Wired into `lib/sweep-loop-common.sh` (covers every
  project on the shared engine, including ones using `bin/scheduler-run`)
  and into the scheduler's own two bespoke wrappers
  (`scheduler-nightly-batch-loop.sh`, `scheduler-dev-cycle.sh`).
  Deliberately NOT wired into a chat interface — the point was to stop
  needing one for routine report feedback. Verified: `collect-feedback.sh`
  unit-tested against a hand-built sample file; the `%%TAG` → nnoremap →
  buffer-local-mapping chain verified in headless vim (`:nmap <buffer>`
  showed all six mappings with correct RHS); `bash -n` clean on all three
  edited scripts; a live dry-run (`SCHED_DRYRUN=1
  scheduler-dev-cycle.sh`) with a real `%%APPROVE` tag appended to
  `~/reports/scheduler/LATEST.md` confirmed the collector fires and would
  have prepended the block (removed the test tag after). **Not yet
  verified against a real (non-dry-run) `claude -p` invocation** — that
  needs an actual paced/nightly cycle to run for real confirmation the
  prepended prompt text lands as intended.
  - Not yet extended to crt/realisateur's actual report format (crt uses
    `crt-report.sh`, a different convention per the 2026-07-19 report
    section above) — only the standard `~/reports/<project>/LATEST.md`
    shape is covered so far.

- **Permission gate on `.claude/**` writes in unattended runs (raised
  2026-07-19, needs investigation before deciding a fix).** Both this
  project's own paced-dev cycle and vkv-inventory's nightly run report
  being unable to write `.claude/scheduler/QUESTIONS.md` /
  `.claude/QUESTIONS.md` in unattended `claude -p` invocations ("hard-
  blocked ... as a 'sensitive file'"), while `bin/` edits in the same runs
  go through fine. A same-session lookup (claude-code-guide agent, not
  independently verified against the actual docs) claims Claude Code has
  a hardcoded protected-path rule for `.claude/` that `permissions.allow`
  entries cannot pre-approve, and that it auto-denies in headless mode
  under `default`/`acceptEdits`/`dontAsk`, with unpredictable behavior
  under `auto` (classifier-decided). **This is in tension with observed
  behavior**: chezz's nightly run successfully committed edits to
  `.claude/FOCUS.md` AND `.claude/QUESTIONS.md` the same night
  (`97dd47d`) using the same shared engine and the same `ALLOWED_TOOLS` as
  the runs that got blocked — so either the protection isn't a blanket
  `.claude/` block, or something else differs per-run (permission mode,
  classifier judgment on the specific edit, etc.). Needs a real
  investigation (not another web lookup) before picking a fix: reproduce
  the block deliberately (e.g. a `SCHED_DRYRUN=0` test cycle that only
  tries to touch `.claude/scheduler/QUESTIONS.md`) and see what actually
  happens today. **Candidate fix if the block turns out to be real and
  path-based:** stop nesting tracker files under `.claude/` for any
  project relying on an unattended run to edit them — e.g. move the
  `SCHEDULER_SUBDIR` model's `FOCUS.md`/`QUESTIONS.md` to a top-level
  hidden dir outside `.claude/` (naming TBD, avoid colliding with the
  existing `schedule/` dir) — but don't migrate every project on this
  guess alone.

## Out of scope for an unattended run

- Anything that can only be tested by waiting for a live cron fire.
- Editing installed wrappers under `~/.local/bin`, the live crontab, or any
  other project's files.

- I manually pushed 6 changes to github, I think. Need to find a way to give this autonomy to the agent which said auto mode gates it
