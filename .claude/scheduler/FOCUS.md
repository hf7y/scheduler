# FOCUS — scheduler (what its own nightly job should work on)

The scheduler's Tier 2 job (`/nightly-batch`) is scoped by this file, same
as every other project. Difference: this project is the **meta-tool** that
controls all the other jobs, so its nightly run is a **review gate** — work
lands on a `nightly/<date>` branch for a human to merge, never auto-applied.

The repo now has a GitHub remote (`git@github.com:hf7y/scheduler.git`),
pushed by a human. The nightly still does NOT push or merge on its own.

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

3. Develop a TUI or webapp experience (whatever is slimmest) for the morning reports and other interactions. Maybe this ends up as a progam installed in my local bin. I'd like to open up a terminal, run "scheduler" or similar cool name, see at a glance what's scheduled. Then I should be able to see past reports, inline edit open questions, see what tasks each project has scheduled to run.

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
- **Right-size per-tier model choice** (see Cost insight above) — audit each
  registered project's `schedule/*.conf` `<TIER>_MODEL` fields; identify
  which nightly/batch tiers are running Opus (or Opus-priced reasoning) for
  work that's mechanical enough for Sonnet, and propose the downgrade
  per-project (don't silently change other repos' confs from here — flag it,
  same as other cross-project proposals). Opus is ~5x Sonnet per token, so
  this is likely the single cheapest lever for slimming automation cost.

## Out of scope for an unattended run

- Anything that can only be tested by waiting for a live cron fire.
- Editing installed wrappers under `~/.local/bin`, the live crontab, or any
  other project's files.
  nightly still never pushes).
